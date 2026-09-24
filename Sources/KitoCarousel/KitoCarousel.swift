//
//  KitoCarousel.swift
//  KitoCarousel
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import KitoCore

/// A snapping horizontal carousel with peeking neighbours, effect presets, optional infinite
/// looping and auto-play that pauses while the user touches it.
///
/// ```swift
/// @State private var page = 0
///
/// KitoCarousel(lodges, selection: $page, effect: .coverFlow, loops: true, autoPlay: 4) { lodge in
///     LodgeCard(lodge).frame(height: 240)
/// }
/// KitoPageIndicator(count: lodges.count, selection: $page, style: .worm)
/// ```
///
/// Give your content a height; the carousel sets the width. Each swipe moves one item and plays a
/// selection haptic. With Reduce Motion on, effects are switched off and auto-play stops. VoiceOver
/// users swipe up and down on an item to change page.
public struct KitoCarousel<Data: RandomAccessCollection, Content: View>: View where Data.Element: Identifiable {
    private let data: Data
    private let selection: Binding<Int>?
    private let effect: KitoCarouselEffect
    private let spacing: CGFloat
    private let peek: CGFloat
    private let loops: Bool
    private let autoPlay: TimeInterval?
    private let autoPlayProgress: Binding<Double>?
    private let cornerRadius: CGFloat?
    private let tint: Color?
    private let content: (Data.Element) -> Content

    @Environment(\.kitoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var ownSelection: Int
    @State private var scrolledID: Int?
    @State private var viewportWidth: CGFloat = 0
    @State private var hapticTick = 0
    @State private var runtime = KitoCarouselRuntime()

    /// - Parameters:
    ///   - data: the items.
    ///   - selection: the index of the centred item. Set it to scroll there.
    ///   - effect: how neighbours move as they scroll away from the centre.
    ///   - spacing: gap between items.
    ///   - peek: how much of each neighbour shows at the edges. 0 for full-width pages.
    ///   - loops: swipe past the last item back to the first, forever.
    ///   - autoPlay: seconds between automatic advances, or `nil` for none.
    ///   - autoPlayProgress: receives how far through the current page auto-play is, `0...1`.
    ///   - cornerRadius: item corner radius; the theme's `xl` by default, 0 for square.
    ///   - tint: colour of the soft shadow under each item.
    ///   - content: the view for one item.
    public init(
        _ data: Data,
        selection: Binding<Int>? = nil,
        effect: KitoCarouselEffect = .scale,
        spacing: CGFloat = 12,
        peek: CGFloat = 32,
        loops: Bool = false,
        autoPlay: TimeInterval? = nil,
        autoPlayProgress: Binding<Double>? = nil,
        cornerRadius: CGFloat? = nil,
        tint: Color? = nil,
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) {
        self.data = data
        self.selection = selection
        self.effect = effect
        self.spacing = max(spacing, 0)
        self.peek = max(peek, 0)
        self.loops = loops
        self.autoPlay = autoPlay
        self.autoPlayProgress = autoPlayProgress
        self.cornerRadius = cornerRadius
        self.tint = tint
        self.content = content

        let count = data.count
        let start = KitoLoopMath.wrap(selection?.wrappedValue ?? 0, count: count)
        _ownSelection = State(initialValue: start)
        let virtual = loops && count > 1
            ? KitoLoopMath.middleVirtualIndex(for: start, count: count, copies: Self.copies(for: effect))
            : start
        _scrolledID = State(initialValue: count > 0 ? virtual : nil)
    }

    public var body: some View {
        let itemWidth = max(viewportWidth - 2 * (peek + spacing), 0)
        let pageWidth = itemWidth + spacing
        ScrollViewReader { reader in
            ScrollView(.horizontal) {
                track(pageWidth: pageWidth, radius: cornerRadius ?? theme.radii.xl)
                    .scrollTargetLayout()
            }
            .onAppear {
                // A lazy stack ignores the starting position until its items exist; jump there once laid out.
                if let scrolledID { reader.scrollTo(scrolledID, anchor: .center) }
            }
        }
        .contentMargins(.horizontal, peek + spacing, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
        .scrollPosition(id: $scrolledID, anchor: .center)
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { viewportWidth = $0 }
        .modifier(KitoScrollInteractionObserver(isEnabled: autoPlay != nil) { touching in
            if touching {
                runtime.clock.pause(.touch)
            } else {
                runtime.clock.resume(.touch)
                runtime.clock.restart()
            }
        })
        .sensoryFeedback(.selection, trigger: hapticTick)
        .onChange(of: scrolledID) { _, newValue in scrolledChanged(to: newValue) }
        .onChange(of: selection?.wrappedValue) { _, newValue in
            if let newValue { scroll(toReal: newValue) }
        }
        .task(id: scrolledID) { await recenterWhenIdle() }
        .task(id: autoPlayKey) { await runAutoPlay() }
    }

    // MARK: Layout

    @ViewBuilder
    private func track(pageWidth: CGFloat, radius: CGFloat) -> some View {
        if effect == .stack {
            HStack(spacing: spacing) { cells(pageWidth: pageWidth, radius: radius) }
        } else {
            LazyHStack(spacing: spacing) { cells(pageWidth: pageWidth, radius: radius) }
        }
    }

    private func cells(pageWidth: CGFloat, radius: CGFloat) -> some View {
        let count = self.count
        let activeEffect = reduceMotion ? KitoCarouselEffect.none : effect
        let fallbackWidth = viewportWidth
        // Scroll-view frames are physical; flip so positive always means "towards the trailing edge".
        let direction: CGFloat = layoutDirection == .rightToLeft ? -1 : 1
        let shadow = (tint ?? theme.colors.onBackground).opacity(tint == nil ? 0.14 : 0.3)
        return ForEach(0..<virtualCount, id: \.self) { virtual in
            let real = KitoLoopMath.realIndex(forVirtual: virtual, count: count)
            if let element = data.kitoElement(at: real) {
                content(element)
                    .modifier(KitoParallaxContent(isEnabled: activeEffect == .parallax, direction: direction))
                    .containerRelativeFrame(.horizontal)
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                    .shadow(color: shadow, radius: 14, x: 0, y: 8)
                    .visualEffect { view, proxy in
                        let frame = proxy.frame(in: .scrollView(axis: .horizontal))
                        let viewport = proxy.bounds(of: .scrollView(axis: .horizontal))?.width ?? fallbackWidth
                        let position = direction * kitoCarouselPosition(frame: frame, viewportWidth: viewport, pageWidth: pageWidth)
                        let transform = KitoCarouselTransform(effect: activeEffect, position: position, pageWidth: pageWidth)
                        return view
                            .scaleEffect(transform.scale)
                            .rotationEffect(.degrees(transform.rotation), anchor: .bottom)
                            .rotation3DEffect(.degrees(transform.rotation3D), axis: (x: 0, y: 1, z: 0), perspective: 0.55)
                            .offset(x: transform.offsetX, y: transform.offsetY)
                            .opacity(transform.opacity)
                            .blur(radius: transform.blur)
                    }
                    .zIndex(activeEffect == .stack ? -Double(virtual) : 0)
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(Text("\(real + 1) of \(count)"))
                    .accessibilityAddTraits(real == currentIndex ? .isSelected : [])
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: move(by: 1)
                        case .decrement: move(by: -1)
                        @unknown default: break
                        }
                    }
            }
        }
    }

    // MARK: State

    private static func copies(for effect: KitoCarouselEffect) -> Int {
        effect == .stack ? 9 : 101
    }

    private var count: Int { data.count }
    private var isLooping: Bool { loops && count > 1 }
    private var copies: Int { Self.copies(for: effect) }
    private var virtualCount: Int { KitoLoopMath.virtualCount(for: count, loops: loops, copies: copies) }
    private var currentIndex: Int { selection?.wrappedValue ?? ownSelection }
    private var autoPlayKey: String { "\(autoPlay ?? 0)|\(reduceMotion)|\(voiceOverEnabled)|\(count)" }
    private var pageAnimation: Animation { .spring(response: 0.55, dampingFraction: 0.86) }

    private func setSelection(_ index: Int) {
        ownSelection = index
        if let selection, selection.wrappedValue != index { selection.wrappedValue = index }
    }

    private func scrolledChanged(to virtual: Int?) {
        guard let virtual, count > 0 else { return }
        let real = KitoLoopMath.realIndex(forVirtual: virtual, count: count)
        let suppressHaptic = runtime.suppressNextHaptic
        runtime.suppressNextHaptic = false
        runtime.clock.restart()
        autoPlayProgress?.wrappedValue = 0
        guard real != currentIndex else { return }
        if !suppressHaptic { hapticTick += 1 }
        setSelection(real)
    }

    private func move(by delta: Int) {
        let target = KitoLoopMath.step(currentIndex, by: delta, count: count, wraps: isLooping)
        guard target != currentIndex else { return }
        setSelection(target)
        scroll(toReal: target)
    }

    private func scroll(toReal index: Int) {
        guard count > 0 else { return }
        let target = KitoLoopMath.wrap(index, count: count)
        if ownSelection != target { ownSelection = target }
        guard let current = scrolledID, KitoLoopMath.realIndex(forVirtual: current, count: count) != target else { return }
        let virtual = isLooping ? KitoLoopMath.nearestVirtualIndex(to: target, from: current, count: count) : target
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : pageAnimation) {
            scrolledID = min(max(virtual, 0), max(virtualCount - 1, 0))
        }
    }

    private func recenterWhenIdle() async {
        guard isLooping, let current = scrolledID else { return }
        try? await Task.sleep(for: .milliseconds(700))
        guard !Task.isCancelled,
              let target = KitoLoopMath.recenteredIndex(current, count: count, copies: copies, margin: 2) else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { scrolledID = target }
    }

    private func runAutoPlay() async {
        guard let interval = autoPlay, interval > 0, count > 1, !reduceMotion else {
            autoPlayProgress?.wrappedValue = 0
            return
        }
        runtime.clock.interval = interval
        runtime.clock.restart()
        if voiceOverEnabled { runtime.clock.pause(.accessibility) } else { runtime.clock.resume(.accessibility) }
        let clock = ContinuousClock()
        var last = clock.now
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(33))
            let now = clock.now
            let delta = (now - last).kitoSeconds
            last = now
            if runtime.clock.tick(delta) { advance() }
            autoPlayProgress?.wrappedValue = runtime.clock.progress
        }
    }

    private func advance() {
        guard let current = scrolledID, count > 1 else { return }
        let next: Int
        if isLooping {
            next = min(current + 1, virtualCount - 1)
        } else {
            next = current + 1 < count ? current + 1 : 0
        }
        runtime.suppressNextHaptic = true
        withAnimation(pageAnimation) { scrolledID = next }
    }
}

/// Mutable bits the carousel needs between frames without re-rendering.
final class KitoCarouselRuntime {
    var clock = KitoAutoPlayState(interval: 4)
    var suppressNextHaptic = false
}

/// Zooms content slightly and drifts it against the scroll.
struct KitoParallaxContent: ViewModifier {
    let isEnabled: Bool
    /// -1 in right-to-left layouts, where frames are physical but offsets are mirrored.
    var direction: CGFloat = 1

    func body(content: Content) -> some View {
        if isEnabled {
            let direction = direction
            content
                .scaleEffect(1.22)
                .visualEffect { view, proxy in
                    let frame = proxy.frame(in: .scrollView(axis: .horizontal))
                    let viewport = proxy.bounds(of: .scrollView(axis: .horizontal))?.width ?? frame.width
                    let drift = kitoParallaxOffset(frame: frame, viewportWidth: viewport, overflow: frame.width * 0.1)
                    return view.offset(x: direction * drift)
                }
        } else {
            content
        }
    }
}

/// Reports whether the user is touching or flinging a scroll view.
struct KitoScrollInteractionObserver: ViewModifier {
    let isEnabled: Bool
    let onChange: (Bool) -> Void

    func body(content: Content) -> some View {
        if !isEnabled {
            content
        } else if #available(iOS 18.0, *) {
            content.onScrollPhaseChange { _, phase in
                onChange(phase == .tracking || phase == .interacting || phase == .decelerating)
            }
        } else {
            content.simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in onChange(true) }
                    .onEnded { _ in onChange(false) }
            )
        }
    }
}

extension Duration {
    /// The duration in seconds.
    var kitoSeconds: TimeInterval {
        let parts = components
        return Double(parts.seconds) + Double(parts.attoseconds) * 1e-18
    }
}
