//
//  KitoInfiniteMarquee.swift
//  KitoCarousel
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import KitoCore

/// Which way a `KitoInfiniteMarquee` drifts.
public enum KitoMarqueeDirection: String, CaseIterable, Hashable, Sendable {
    /// Content moves towards the leading edge.
    case leading
    /// Content moves towards the trailing edge.
    case trailing
}

/// An endless, auto-scrolling strip of logos, tags or headlines. Press and hold to stop it. With
/// Reduce Motion on it becomes a plain horizontal scroll.
///
/// ```swift
/// KitoInfiniteMarquee(partners, speed: 36) { partner in
///     PartnerLogo(partner)
/// }
/// ```
public struct KitoInfiniteMarquee<Data: RandomAccessCollection, Content: View>: View where Data.Element: Identifiable {
    private let data: Data
    private let speed: CGFloat
    private let spacing: CGFloat
    private let direction: KitoMarqueeDirection
    private let pausesOnPress: Bool
    private let fadesEdges: Bool
    private let tint: Color?
    private let content: (Data.Element) -> Content

    @Environment(\.kitoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rowWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var travelled: Double = 0
    @State private var startedAt = Date()
    @State private var isHeld = false

    /// - Parameters:
    ///   - data: the items; repeated as needed to fill the strip.
    ///   - speed: points per second.
    ///   - spacing: gap between items, and between the end and the start again.
    ///   - direction: which way it drifts.
    ///   - pausesOnPress: hold to stop.
    ///   - fadesEdges: soften the ends of the strip.
    ///   - tint: colour of the default separators between items; none when `nil`.
    ///   - content: one item.
    public init(
        _ data: Data,
        speed: CGFloat = 40,
        spacing: CGFloat = 28,
        direction: KitoMarqueeDirection = .leading,
        pausesOnPress: Bool = true,
        fadesEdges: Bool = true,
        tint: Color? = nil,
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) {
        self.data = data
        self.speed = max(speed, 0)
        self.spacing = spacing
        self.direction = direction
        self.pausesOnPress = pausesOnPress
        self.fadesEdges = fadesEdges
        self.tint = tint
        self.content = content
    }

    public var body: some View {
        Group {
            if reduceMotion {
                ScrollView(.horizontal) {
                    row.padding(.horizontal, theme.spacing.lg)
                }
                .scrollIndicators(.hidden)
            } else {
                marquee
            }
        }
        .mask {
            if fadesEdges {
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.08),
                    .init(color: .black, location: 0.92),
                    .init(color: .clear, location: 1),
                ], startPoint: .leading, endPoint: .trailing)
            } else {
                Rectangle()
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var marquee: some View {
        let cycle = rowWidth + spacing
        let copies = cycle > 0 ? max(Int((containerWidth / cycle).rounded(.up)) + 1, 2) : 1
        return TimelineView(.animation(minimumInterval: nil, paused: isHeld || cycle <= 0)) { context in
            let distance = isHeld ? travelled : travelled + context.date.timeIntervalSince(startedAt) * Double(speed)
            let shift = cycle > 0 ? CGFloat(distance.truncatingRemainder(dividingBy: Double(cycle))) : 0
            HStack(spacing: spacing) {
                ForEach(0..<copies, id: \.self) { copy in
                    row
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                            if copy == 0, rowWidth != width { rowWidth = width }
                        }
                        .accessibilityHidden(copy > 0)
                }
            }
            .fixedSize()
            .offset(x: direction == .leading ? -shift : shift - cycle)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .clipped()
        .contentShape(Rectangle())
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { containerWidth = $0 }
        .onLongPressGesture(minimumDuration: .infinity, maximumDistance: 60, perform: {}) { pressing in
            guard pausesOnPress else { return }
            setHeld(pressing)
        }
    }

    private var row: some View {
        HStack(spacing: spacing) {
            ForEach(Array(data.enumerated()), id: \.element.id) { offset, element in
                content(element)
                if let tint, offset < data.count - 1 {
                    Circle().fill(tint.opacity(0.5)).frame(width: 4, height: 4)
                }
            }
        }
        .fixedSize()
    }

    private func setHeld(_ held: Bool) {
        guard held != isHeld else { return }
        if held {
            travelled += Date().timeIntervalSince(startedAt) * Double(speed)
        } else {
            startedAt = Date()
        }
        isHeld = held
    }
}
