//
//  KitoStackedCards.swift
//  KitoCarousel
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import KitoCore

/// Wallet-style stacked cards. Collapsed, the cards sit in a tight pile with the edges of the ones
/// behind peeking out; tap to fan them out into a list, tap one to bring it forward with the rest
/// tucked beneath, tap it again to go back to the list.
///
/// ```swift
/// @State private var pass: TravelPass.ID?
/// @State private var fanned = false
///
/// KitoStackedCards(passes, selection: $pass, isExpanded: $fanned) { pass in
///     PassCard(pass)
/// }
/// ```
///
/// Later cards sit in front, as in Wallet.
public struct KitoStackedCards<Data: RandomAccessCollection, Content: View>: View where Data.Element: Identifiable {
    private let data: Data
    private let selection: Binding<Data.Element.ID?>?
    private let isExpanded: Binding<Bool>?
    private let cardHeight: CGFloat
    private let collapsedSpacing: CGFloat
    private let expandedSpacing: CGFloat
    private let maxCollapsedVisible: Int
    private let tint: Color?
    private let content: (Data.Element) -> Content

    @Environment(\.kitoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ownSelection: Data.Element.ID?
    @State private var ownExpanded = false

    /// - Parameters:
    ///   - data: the cards; later ones sit in front.
    ///   - selection: the card brought forward, or `nil`.
    ///   - isExpanded: whether the cards are fanned out.
    ///   - cardHeight: height of one card.
    ///   - collapsedSpacing: how much of each card behind peeks out when collapsed.
    ///   - expandedSpacing: how much of each card shows when fanned out.
    ///   - maxCollapsedVisible: cards drawn in the collapsed pile.
    ///   - tint: colour of the card shadows.
    ///   - content: one card.
    public init(
        _ data: Data,
        selection: Binding<Data.Element.ID?>? = nil,
        isExpanded: Binding<Bool>? = nil,
        cardHeight: CGFloat = 200,
        collapsedSpacing: CGFloat = 12,
        expandedSpacing: CGFloat = 72,
        maxCollapsedVisible: Int = 4,
        tint: Color? = nil,
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) {
        self.data = data
        self.selection = selection
        self.isExpanded = isExpanded
        self.cardHeight = cardHeight
        self.collapsedSpacing = collapsedSpacing
        self.expandedSpacing = expandedSpacing
        self.maxCollapsedVisible = max(maxCollapsedVisible, 1)
        self.tint = tint
        self.content = content
    }

    public var body: some View {
        let layout = layoutState
        ZStack(alignment: .top) {
            ForEach(Array(data.enumerated()), id: \.element.id) { offset, element in
                let placement = placement(for: offset, element: element, layout: layout)
                content(element)
                    .frame(maxWidth: .infinity)
                    .frame(height: cardHeight)
                    .clipShape(RoundedRectangle(cornerRadius: theme.radii.xl, style: .continuous))
                    .shadow(color: (tint ?? .black).opacity(placement.isFront ? 0.22 : 0.12), radius: placement.isFront ? 18 : 8, x: 0, y: placement.isFront ? 12 : 4)
                    .scaleEffect(placement.scale, anchor: .top)
                    .rotation3DEffect(.degrees(reduceMotion ? 0 : placement.tilt), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.6)
                    .offset(y: placement.y)
                    .opacity(placement.opacity)
                    .zIndex(placement.z)
                    .animation(cardAnimation(offset), value: layout)
                    .onTapGesture { tapped(element) }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAddTraits(layout == .selected(element.id) ? .isSelected : [])
                    .accessibilityHint(Text(hint(for: element, layout: layout)))
                    .accessibilityHidden(placement.opacity == 0)
            }
        }
        .frame(height: totalHeight(layout), alignment: .top)
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.82), value: layout)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: layout)
    }

    // MARK: Layout

    private enum LayoutState: Hashable {
        case collapsed
        case expanded
        case selected(Data.Element.ID)
    }

    private struct Placement {
        var y: CGFloat = 0
        var scale: CGFloat = 1
        var tilt: Double = 0
        var opacity: Double = 1
        var z: Double = 0
        var isFront = false
    }

    private var currentSelection: Data.Element.ID? { selection?.wrappedValue ?? ownSelection }
    private var currentExpanded: Bool { isExpanded?.wrappedValue ?? ownExpanded }

    private var layoutState: LayoutState {
        if let id = currentSelection, data.contains(where: { $0.id == id }) { return .selected(id) }
        return currentExpanded ? .expanded : .collapsed
    }

    private func placement(for offset: Int, element: Data.Element, layout: LayoutState) -> Placement {
        let count = data.count
        var result = Placement()
        result.z = Double(offset)
        switch layout {
        case .collapsed:
            let depth = count - 1 - offset
            let visibleDepth = min(depth, maxCollapsedVisible - 1)
            result.y = CGFloat(maxCollapsedVisible - 1 - visibleDepth) * collapsedSpacing - CGFloat(max(0, maxCollapsedVisible - count)) * collapsedSpacing
            result.scale = 1 - CGFloat(visibleDepth) * 0.05
            result.opacity = depth >= maxCollapsedVisible ? 0 : 1
            result.isFront = depth == 0
        case .expanded:
            result.y = CGFloat(offset) * expandedSpacing
            result.tilt = offset == count - 1 ? 0 : -4
            result.isFront = offset == count - 1
        case .selected(let id):
            if element.id == id {
                result.z = Double(count + 1)
                result.isFront = true
            } else {
                let others = data.filter { $0.id != id }
                let position = others.firstIndex { $0.id == element.id } ?? 0
                let depth = others.count - 1 - position
                let visibleDepth = min(depth, maxCollapsedVisible - 1)
                let tucked = min(others.count, maxCollapsedVisible)
                result.y = cardHeight + theme.spacing.xl + CGFloat(tucked - 1 - visibleDepth) * collapsedSpacing * 0.7
                result.scale = 0.92 - CGFloat(visibleDepth) * 0.04
                result.opacity = depth >= maxCollapsedVisible ? 0 : 1
            }
        }
        return result
    }

    private func totalHeight(_ layout: LayoutState) -> CGFloat {
        let count = data.count
        guard count > 0 else { return 0 }
        switch layout {
        case .collapsed:
            return CGFloat(min(count, maxCollapsedVisible) - 1) * collapsedSpacing + cardHeight
        case .expanded:
            return CGFloat(count - 1) * expandedSpacing + cardHeight
        case .selected:
            guard count > 1 else { return cardHeight }
            return cardHeight * 1.92 + theme.spacing.xl + CGFloat(min(count - 1, maxCollapsedVisible) - 1) * collapsedSpacing * 0.7
        }
    }

    private func cardAnimation(_ offset: Int) -> Animation {
        reduceMotion
            ? .easeInOut(duration: 0.2)
            : .spring(response: 0.5, dampingFraction: 0.78).delay(Double(offset) * 0.025)
    }

    // MARK: Interaction

    private func tapped(_ element: Data.Element) {
        switch layoutState {
        case .collapsed:
            setExpanded(true)
        case .expanded:
            setSelection(element.id)
        case .selected(let id):
            setSelection(nil)
            if id != element.id { setExpanded(true) }
        }
    }

    private func setSelection(_ id: Data.Element.ID?) {
        ownSelection = id
        selection?.wrappedValue = id
    }

    private func setExpanded(_ value: Bool) {
        ownExpanded = value
        isExpanded?.wrappedValue = value
    }

    private func hint(for element: Data.Element, layout: LayoutState) -> String {
        switch layout {
        case .collapsed: return "Shows all cards"
        case .expanded: return "Brings this card forward"
        case .selected: return "Goes back to all cards"
        }
    }
}
