//
//  KitoPageIndicator.swift
//  KitoCarousel
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import KitoCore

/// How a `KitoPageIndicator` draws the pages.
public enum KitoPageIndicatorStyle: String, CaseIterable, Hashable, Sendable {
    /// A row of dots; the current one grows and takes the tint.
    case dots
    /// The current dot stretches into a capsule.
    case capsule
    /// A liquid blob that stretches across to the next page and snaps back.
    case worm
    /// "3 / 8".
    case numbers
    /// The current dot is a capsule that fills with auto-play progress.
    case progress
}

/// A page indicator for carousels, banners and onboarding.
///
/// ```swift
/// KitoPageIndicator(count: 8, selection: $page, style: .worm)
/// KitoPageIndicator(count: 5, selection: $page, style: .progress, progress: autoPlayProgress)
/// ```
///
/// Tap a dot to jump to it, or drag along the row to scrub. VoiceOver reads "Page 3 of 8" and
/// swipes up or down to change page.
public struct KitoPageIndicator: View {
    private let count: Int
    @Binding private var selection: Int
    private let style: KitoPageIndicatorStyle
    private let progress: Double
    private let isInteractive: Bool
    private let dotSize: CGFloat
    private let tint: Color?

    @Environment(\.kitoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    @Namespace private var namespace
    @State private var scrubTick = 0

    /// - Parameters:
    ///   - count: number of pages.
    ///   - selection: the current page.
    ///   - style: how pages are drawn.
    ///   - progress: fill of the current page for `.progress`, `0...1`.
    ///   - isInteractive: tap and drag to change page.
    ///   - dotSize: diameter of one dot.
    ///   - tint: colour of the current page; the theme's `onBackground` by default.
    public init(
        count: Int,
        selection: Binding<Int>,
        style: KitoPageIndicatorStyle = .capsule,
        progress: Double = 0,
        isInteractive: Bool = true,
        dotSize: CGFloat = 8,
        tint: Color? = nil
    ) {
        self.count = max(count, 0)
        self._selection = selection
        self.style = style
        self.progress = min(max(progress, 0), 1)
        self.isInteractive = isInteractive
        self.dotSize = max(dotSize, 2)
        self.tint = tint
    }

    public var body: some View {
        Group {
            switch style {
            case .dots: dots
            case .capsule: capsules
            case .worm: worm
            case .numbers: numbers
            case .progress: progressBars
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .gesture(scrub, including: isInteractive && style != .numbers ? .all : .subviews)
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.42, dampingFraction: 0.72), value: current)
        .sensoryFeedback(.selection, trigger: scrubTick)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Page"))
        .accessibilityValue(Text("\(current + 1) of \(count)"))
        .accessibilityAdjustableAction { direction in
            guard isInteractive else { return }
            switch direction {
            case .increment: select(current + 1)
            case .decrement: select(current - 1)
            @unknown default: break
            }
        }
    }

    // MARK: Styles

    private var activeColor: Color { tint ?? theme.colors.onBackground }
    private var idleColor: Color { theme.colors.onBackground.opacity(0.22) }
    private var spacing: CGFloat { dotSize }
    private var current: Int { count > 0 ? min(max(selection, 0), count - 1) : 0 }

    private var dots: some View {
        HStack(spacing: spacing) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(idleColor)
                    .frame(width: dotSize, height: dotSize)
                    .overlay {
                        if index == current {
                            Circle()
                                .fill(activeColor)
                                .shadow(color: activeColor.opacity(0.45), radius: 4)
                                .matchedGeometryEffect(id: "active", in: namespace)
                                .scaleEffect(1.4)
                        }
                    }
            }
        }
    }

    private var capsules: some View {
        HStack(spacing: spacing) {
            ForEach(0..<count, id: \.self) { index in
                ZStack {
                    Capsule().fill(idleColor)
                    if index == current {
                        Capsule()
                            .fill(activeColor)
                            .matchedGeometryEffect(id: "active", in: namespace)
                    }
                }
                .frame(width: index == current ? dotSize * 3.2 : dotSize, height: dotSize)
            }
        }
    }

    private var worm: some View {
        let width = CGFloat(count) * dotSize + CGFloat(max(count - 1, 0)) * spacing
        return ZStack(alignment: .leading) {
            HStack(spacing: spacing) {
                ForEach(0..<count, id: \.self) { _ in
                    Circle().fill(idleColor).frame(width: dotSize, height: dotSize)
                }
            }
            KitoWormShape(position: Double(current), dotSize: dotSize, spacing: spacing)
                .fill(activeColor)
                .shadow(color: activeColor.opacity(0.4), radius: 4)
                .frame(width: width, height: dotSize)
        }
        .frame(width: width, height: dotSize)
    }

    private var numbers: some View {
        HStack(spacing: theme.spacing.sm) {
            chevron("chevron.backward", enabled: current > 0) { select(current - 1) }
            HStack(spacing: 3) {
                Text("\(current + 1)")
                    .foregroundStyle(activeColor)
                    .contentTransition(.numericText(value: Double(current)))
                Text("/").foregroundStyle(theme.colors.onBackground.opacity(0.4))
                Text("\(count)").foregroundStyle(theme.colors.onBackground.opacity(0.6))
            }
            .font(theme.typography.label.monospacedDigit())
            chevron("chevron.forward", enabled: current < count - 1) { select(current + 1) }
        }
        .padding(.horizontal, theme.spacing.md)
        .padding(.vertical, theme.spacing.xs + 2)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(theme.colors.border.opacity(0.6), lineWidth: 0.5))
    }

    private func chevron(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(theme.colors.onBackground.opacity(enabled ? 0.8 : 0.25))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled || !isInteractive)
    }

    private var progressBars: some View {
        HStack(spacing: spacing) {
            ForEach(0..<count, id: \.self) { index in
                let isCurrent = index == current
                Capsule()
                    .fill(idleColor)
                    .overlay(alignment: .leading) {
                        if isCurrent {
                            GeometryReader { proxy in
                                Capsule()
                                    .fill(activeColor)
                                    .frame(width: max(dotSize, proxy.size.width * progress))
                            }
                        }
                    }
                    .clipShape(Capsule())
                    .frame(width: isCurrent ? dotSize * 4.5 : dotSize, height: dotSize)
            }
        }
    }

    // MARK: Interaction

    private var scrub: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard count > 0 else { return }
                let width = indicatorWidth
                guard width > 0 else { return }
                // The dots mirror in right-to-left layouts; the touch location doesn't.
                let x = layoutDirection == .rightToLeft ? width - value.location.x : value.location.x
                let fraction = min(max(x / width, 0), 0.9999)
                select(Int(fraction * CGFloat(count)))
            }
    }

    private var indicatorWidth: CGFloat {
        let base = CGFloat(count) * dotSize + CGFloat(max(count - 1, 0)) * spacing
        switch style {
        case .capsule: return base + dotSize * 2.2
        case .progress: return base + dotSize * 3.5
        default: return base
        }
    }

    private func select(_ index: Int) {
        guard count > 0 else { return }
        let clamped = min(max(index, 0), count - 1)
        guard clamped != selection else { return }
        selection = clamped
        scrubTick += 1
    }
}

/// The worm indicator's blob; animating `position` makes it stretch and snap.
struct KitoWormShape: Shape {
    var position: Double
    let dotSize: CGFloat
    let spacing: CGFloat

    var animatableData: Double {
        get { position }
        set { position = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let frame = KitoWormMath.frame(at: max(position, 0), dotSize: dotSize, spacing: spacing)
        let span = KitoWormMath.span(at: max(position, 0))
        let squash = CGFloat(min(span.length, 1)) * dotSize * 0.18
        let bounds = CGRect(x: frame.minX, y: rect.midY - dotSize / 2 + squash / 2, width: frame.width, height: dotSize - squash)
        return Path(roundedRect: bounds, cornerRadius: bounds.height / 2)
    }
}
