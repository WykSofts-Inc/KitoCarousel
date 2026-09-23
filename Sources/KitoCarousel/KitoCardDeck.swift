//
//  KitoCardDeck.swift
//  KitoCarousel
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import Observation
import KitoCore

/// Drives a `KitoCardDeck` from outside: swipe the top card from your own buttons, undo, and read
/// how many cards are left.
///
/// ```swift
/// @State private var deck = KitoCardDeckController()
///
/// KitoCardDeck(dishes, controller: deck, showsControls: false) { DishCard($0) }
/// Button("Pass") { deck.swipe(.left) }
/// ```
@MainActor
@Observable
public final class KitoCardDeckController {
    enum Command: Equatable {
        case swipe(KitoSwipeDirection)
        case undo
    }

    /// Cards not yet swiped.
    public private(set) var remaining = 0
    /// Whether there's a swipe to take back.
    public private(set) var canUndo = false

    @ObservationIgnored var pending: [Command] = []
    var commandCount = 0

    public init() {}

    /// Throws the top card `direction`, as if the user had swiped it.
    public func swipe(_ direction: KitoSwipeDirection) {
        pending.append(.swipe(direction))
        commandCount += 1
    }

    /// Brings the last swiped card back to the top.
    public func undo() {
        pending.append(.undo)
        commandCount += 1
    }

    func sync(remaining: Int, canUndo: Bool) {
        if self.remaining != remaining { self.remaining = remaining }
        if self.canUndo != canUndo { self.canUndo = canUndo }
    }

    func drain() -> [Command] {
        defer { pending.removeAll() }
        return pending
    }
}

/// A Tinder-style swipe deck: drag the top card and it tilts, LIKE / NOPE stamps fade in, and a
/// quick flick or a long drag throws it off with momentum. Undo brings the last one back.
///
/// ```swift
/// KitoCardDeck(dishes) { dish in
///     DishCard(dish)
/// } onSwipe: { dish, direction in
///     if direction == .right { save(dish) }
/// }
/// ```
///
/// The deck fills the space it's given; set a frame. VoiceOver offers Like, Nope, Super like and
/// Undo as actions on the top card.
public struct KitoCardDeck<Data: RandomAccessCollection, Content: View>: View where Data.Element: Identifiable {
    private let data: Data
    private let controller: KitoCardDeckController?
    private let visibleCount: Int
    private let decision: KitoSwipeDecision
    private let showsControls: Bool
    private let labels: (like: String, nope: String, superLike: String)
    private let emptyTitle: String
    private let tint: Color?
    private let onSwipe: ((Data.Element, KitoSwipeDirection) -> Void)?
    private let onUndo: ((Data.Element) -> Void)?
    private let onEmpty: (() -> Void)?
    private let content: (Data.Element) -> Content

    @Environment(\.kitoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var top = 0
    @State private var drag: CGSize = .zero
    @State private var flying: [Int: CGSize] = [:]
    @State private var flights: [Int: Int] = [:]
    @State private var history: [KitoDeckSwipe] = []
    @State private var cardSize: CGSize = .zero
    @State private var armed: KitoSwipeDirection?
    @State private var swipeTick = 0

    /// - Parameters:
    ///   - data: the cards, first on top.
    ///   - controller: swipe and undo from outside.
    ///   - visibleCount: cards drawn in the pile.
    ///   - allowsSuperLike: whether throwing up counts.
    ///   - showsControls: the round Undo / Nope / Super like / Like buttons under the deck.
    ///   - likeLabel: stamp shown when dragging right.
    ///   - nopeLabel: stamp shown when dragging left.
    ///   - superLikeLabel: stamp shown when dragging up.
    ///   - emptyTitle: shown when every card is gone.
    ///   - tint: accent for the super-like button and stamp.
    ///   - content: one card.
    ///   - onSwipe: a card left the deck.
    ///   - onUndo: a card came back.
    ///   - onEmpty: the last card left.
    public init(
        _ data: Data,
        controller: KitoCardDeckController? = nil,
        visibleCount: Int = 3,
        allowsSuperLike: Bool = true,
        showsControls: Bool = true,
        likeLabel: String = "LIKE",
        nopeLabel: String = "NOPE",
        superLikeLabel: String = "SUPER",
        emptyTitle: String = "You're all caught up",
        tint: Color? = nil,
        @ViewBuilder content: @escaping (Data.Element) -> Content,
        onSwipe: ((Data.Element, KitoSwipeDirection) -> Void)? = nil,
        onUndo: ((Data.Element) -> Void)? = nil,
        onEmpty: (() -> Void)? = nil
    ) {
        self.data = data
        self.controller = controller
        self.visibleCount = max(visibleCount, 1)
        self.decision = KitoSwipeDecision(allowsUp: allowsSuperLike)
        self.showsControls = showsControls
        self.labels = (likeLabel, nopeLabel, superLikeLabel)
        self.emptyTitle = emptyTitle
        self.tint = tint
        self.onSwipe = onSwipe
        self.onUndo = onUndo
        self.onEmpty = onEmpty
        self.content = content
    }

    public var body: some View {
        VStack(spacing: theme.spacing.xl) {
            ZStack {
                if top >= count && flying.isEmpty {
                    emptyState.transition(.scale(scale: 0.9).combined(with: .opacity))
                }
                ForEach(renderedIndices, id: \.self) { index in
                    if let element = data.kitoElement(at: index) {
                        card(element, index: index)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { cardSize = $0 }

            if showsControls {
                controls
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: swipeTick)
        .sensoryFeedback(.selection, trigger: armed)
        .onChange(of: controller?.commandCount) { _, _ in runCommands() }
        .onChange(of: top, initial: true) { _, _ in syncController() }
        .onChange(of: history.count) { _, _ in syncController() }
    }

    // MARK: Cards

    private var count: Int { data.count }

    private var renderedIndices: [Int] {
        let pile = Array(top..<min(top + visibleCount + 1, max(count, top)))
        let thrown = flying.keys.sorted()
        return (pile + thrown.filter { !pile.contains($0) }).sorted(by: >)
    }

    private var dragProgress: CGFloat {
        guard cardSize.width > 0 else { return 0 }
        return min(hypot(drag.width, drag.height) / (cardSize.width * 0.5), 1)
    }

    private func offset(for index: Int) -> CGSize {
        if let thrown = flying[index] { return thrown }
        return index == top ? drag : .zero
    }

    private func card(_ element: Data.Element, index: Int) -> some View {
        let isThrown = flying[index] != nil
        let isTop = index == top && !isThrown
        let depth = isThrown ? 0 : CGFloat(index - top)
        let lifted = max(depth - (depth > 0 ? dragProgress : 0), 0)
        let cardOffset = offset(for: index)
        let swipe = decision.progress(translation: cardOffset, in: cardSize)
        let hidden = depth >= CGFloat(visibleCount)
        let rotation = reduceMotion ? 0 : KitoSwipeDecision.rotation(for: cardOffset, width: cardSize.width)

        return content(element)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.colors.surface)
            .overlay { edgeGlow(swipe) }
            .clipShape(RoundedRectangle(cornerRadius: theme.radii.xl + 8, style: .continuous))
            .overlay { stamps(swipe) }
            .shadow(color: .black.opacity(isTop || isThrown ? 0.18 : 0.08), radius: isTop ? 18 : 8, x: 0, y: isTop ? 12 : 4)
            .scaleEffect(1 - lifted * 0.05, anchor: .bottom)
            .offset(y: lifted * 14)
            .rotationEffect(.degrees(rotation), anchor: .bottom)
            .offset(cardOffset)
            .opacity(hidden ? 0 : 1)
            .zIndex(isThrown ? 1000 + Double(index) : -Double(index))
            .allowsHitTesting(isTop)
            .gesture(dragGesture, including: isTop ? .all : .subviews)
            .accessibilityElement(children: isTop ? .combine : .ignore)
            .accessibilityHidden(!isTop)
            .accessibilityHint(Text("Swipe right to like, left to pass"))
            .accessibilityAction(named: Text(labels.like.capitalized)) { throwTop(.right) }
            .accessibilityAction(named: Text(labels.nope.capitalized)) { throwTop(.left) }
            .accessibilityAction(named: Text("Undo")) { undo() }
    }

    private func edgeGlow(_ swipe: KitoSwipeProgress) -> some View {
        ZStack {
            LinearGradient(colors: [theme.colors.success.opacity(0.45 * swipe.right), .clear], startPoint: .leading, endPoint: .center)
            LinearGradient(colors: [theme.colors.danger.opacity(0.45 * swipe.left), .clear], startPoint: .trailing, endPoint: .center)
            LinearGradient(colors: [superColor.opacity(0.45 * swipe.up), .clear], startPoint: .bottom, endPoint: .center)
        }
        .allowsHitTesting(false)
    }

    private func stamps(_ swipe: KitoSwipeProgress) -> some View {
        ZStack {
            KitoDeckStamp(text: labels.like, color: theme.colors.success, amount: swipe.right)
                .rotationEffect(.degrees(-16))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            KitoDeckStamp(text: labels.nope, color: theme.colors.danger, amount: swipe.left)
                .rotationEffect(.degrees(16))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            KitoDeckStamp(text: labels.superLike, color: superColor, amount: swipe.up)
                .rotationEffect(.degrees(-6))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, theme.spacing.xxl)
        }
        .padding(theme.spacing.xl)
        .allowsHitTesting(false)
    }

    private var superColor: Color { tint ?? theme.colors.primary }

    private var emptyState: some View {
        VStack(spacing: theme.spacing.md) {
            Image(systemName: "sparkles")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(superColor.gradient)
                .symbolEffect(.bounce, value: top)
            Text(emptyTitle)
                .font(theme.typography.bodyEmphasized)
                .foregroundStyle(theme.colors.onBackground)
            if !history.isEmpty {
                Button { undo() } label: {
                    Label("Undo last", systemImage: "arrow.uturn.backward")
                        .font(theme.typography.label)
                        .padding(.horizontal, theme.spacing.lg)
                        .padding(.vertical, theme.spacing.sm)
                        .background(theme.colors.surfaceMuted, in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.colors.onSurface)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.colors.surfaceMuted.opacity(0.5), in: RoundedRectangle(cornerRadius: theme.radii.xl + 8, style: .continuous))
    }

    // MARK: Controls

    private var controls: some View {
        let swipe = decision.progress(translation: drag, in: cardSize)
        let enabled = top < count
        return HStack(spacing: theme.spacing.lg) {
            KitoDeckButton(symbol: "arrow.uturn.backward", color: theme.colors.warning, size: 48, emphasis: 0, isEnabled: !history.isEmpty) { undo() }
                .accessibilityLabel(Text("Undo"))
            KitoDeckButton(symbol: "xmark", color: theme.colors.danger, size: 64, emphasis: swipe.left, isEnabled: enabled) { throwTop(.left) }
                .accessibilityLabel(Text(labels.nope.capitalized))
            if decision.allowsUp {
                KitoDeckButton(symbol: "star.fill", color: superColor, size: 48, emphasis: swipe.up, isEnabled: enabled) { throwTop(.up) }
                    .accessibilityLabel(Text(labels.superLike.capitalized))
            }
            KitoDeckButton(symbol: "heart.fill", color: theme.colors.success, size: 64, emphasis: swipe.right, isEnabled: enabled) { throwTop(.right) }
                .accessibilityLabel(Text(labels.like.capitalized))
        }
    }

    // MARK: Gestures

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                drag = value.translation
                let direction = decision.progress(translation: value.translation, in: cardSize).dominant
                let nowArmed = direction.flatMap { $0.amount >= 1 ? $0.direction : nil }
                if nowArmed != armed { armed = nowArmed }
            }
            .onEnded { value in
                armed = nil
                if let direction = decision.direction(translation: value.translation, velocity: value.velocity, in: cardSize) {
                    throwTop(direction, from: value.translation, velocity: value.velocity)
                } else {
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.62)) { drag = .zero }
                }
            }
    }

    private func throwTop(_ direction: KitoSwipeDirection, from translation: CGSize = .zero, velocity: CGSize = .zero) {
        guard direction != .up || decision.allowsUp, let element = data.kitoElement(at: top) else { return }
        let index = top
        let size = cardSize == .zero ? CGSize(width: 320, height: 480) : cardSize
        let target = KitoSwipeDecision.exitOffset(for: direction, translation: translation, velocity: velocity, in: size)
        let remaining = hypot(target.width - translation.width, target.height - translation.height)
        let speed = hypot(velocity.width, velocity.height)
        let initialVelocity = remaining > 0 ? min(speed / remaining, 10) : 0

        flying[index] = translation
        drag = .zero
        history.append(KitoDeckSwipe(index: index, direction: direction))
        swipeTick += 1

        let throwAnimation: Animation = reduceMotion
            ? .easeIn(duration: 0.25)
            : .interpolatingSpring(mass: 1, stiffness: 140, damping: 22, initialVelocity: initialVelocity)
        let flight = (flights[index] ?? 0) + 1
        flights[index] = flight
        withAnimation(throwAnimation, completionCriteria: .logicallyComplete) {
            flying[index] = target
            top = index + 1
        } completion: {
            // Only the latest throw of this card may land it; an undo or re-throw supersedes older ones.
            if flights[index] == flight { flying[index] = nil }
        }

        onSwipe?(element, direction)
        if index + 1 >= count { onEmpty?() }
    }

    private func undo() {
        guard let last = history.popLast(), let element = data.kitoElement(at: last.index) else { return }
        let index = last.index
        flights[index] = (flights[index] ?? 0) + 1
        if flying[index] == nil {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                flying[index] = KitoSwipeDecision.exitOffset(for: last.direction, translation: .zero, velocity: .zero, in: cardSize)
            }
        }
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.74)) {
                top = index
                flying[index] = nil
            }
        }
        onUndo?(element)
    }

    private func runCommands() {
        guard let controller else { return }
        for command in controller.drain() {
            switch command {
            case .swipe(let direction): throwTop(direction)
            case .undo: undo()
            }
        }
    }

    private func syncController() {
        controller?.sync(remaining: max(count - top, 0), canUndo: !history.isEmpty)
    }
}

struct KitoDeckSwipe: Equatable {
    let index: Int
    let direction: KitoSwipeDirection
}

/// A rubber-stamp label that fades and settles in as the drag commits.
struct KitoDeckStamp: View {
    let text: String
    let color: Color
    let amount: Double

    var body: some View {
        Text(text)
            .font(.system(size: 34, weight: .black, design: .rounded))
            .tracking(2)
            .foregroundStyle(color)
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(color, lineWidth: 4))
            .scaleEffect(1.35 - 0.35 * amount)
            .opacity(amount)
            .accessibilityHidden(true)
    }
}

/// A round deck control that swells as the matching drag builds.
struct KitoDeckButton: View {
    let symbol: String
    let color: Color
    let size: CGFloat
    let emphasis: Double
    let isEnabled: Bool
    let action: () -> Void

    @Environment(\.kitoTheme) private var theme
    @State private var bounce = 0

    var body: some View {
        Button {
            bounce += 1
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(emphasis > 0.95 ? AnyShapeStyle(theme.colors.onPrimary) : AnyShapeStyle(color.gradient))
                .symbolEffect(.bounce, value: bounce)
                .frame(width: size, height: size)
                .background {
                    Circle()
                        .fill(theme.colors.surface)
                        .overlay(Circle().fill(color).opacity(emphasis > 0.95 ? 1 : emphasis * 0.18))
                        .shadow(color: color.opacity(0.25 + 0.3 * emphasis), radius: 10 + 8 * emphasis, x: 0, y: 6)
                }
                .overlay(Circle().strokeBorder(color.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(KitoPressScaleStyle())
        .scaleEffect(1 + 0.14 * emphasis)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: emphasis)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
    }
}

/// Springs down while pressed.
struct KitoPressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
