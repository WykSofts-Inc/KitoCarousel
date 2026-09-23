//
//  KitoStoryRing.swift
//  KitoCarousel
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import KitoCore

/// An avatar in a story ring: a bright gradient for new stories, a thin grey ring once seen, a
/// pulsing ring and LIVE badge when live, and a spinning ring while the story loads.
///
/// ```swift
/// KitoStoryRing(isSeen: user.seen, isLive: user.live) {
///     Image(user.photo).resizable().scaledToFill()
/// }
/// ```
public struct KitoStoryRing<Avatar: View>: View {
    private let isSeen: Bool
    private let isLive: Bool
    private let isLoading: Bool
    private let size: CGFloat
    private let lineWidth: CGFloat
    private let colors: [Color]?
    private let tint: Color?
    private let liveLabel: String
    private let avatar: Avatar

    @Environment(\.kitoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin = false
    @State private var pulse = false

    /// - Parameters:
    ///   - isSeen: all stories watched; the ring turns grey.
    ///   - isLive: broadcasting now; a pulsing ring and badge.
    ///   - isLoading: spins the ring, e.g. while the first story loads.
    ///   - size: outer diameter.
    ///   - lineWidth: ring thickness.
    ///   - colors: ring gradient; a sunset gradient by default.
    ///   - tint: when set, a gradient built from this colour.
    ///   - liveLabel: the badge text.
    ///   - avatar: the picture, clipped to a circle.
    public init(
        isSeen: Bool = false,
        isLive: Bool = false,
        isLoading: Bool = false,
        size: CGFloat = 68,
        lineWidth: CGFloat = 3,
        colors: [Color]? = nil,
        tint: Color? = nil,
        liveLabel: String = "LIVE",
        @ViewBuilder avatar: () -> Avatar
    ) {
        self.isSeen = isSeen
        self.isLive = isLive
        self.isLoading = isLoading
        self.size = size
        self.lineWidth = lineWidth
        self.colors = colors
        self.tint = tint
        self.liveLabel = liveLabel
        self.avatar = avatar()
    }

    public var body: some View {
        let gap = max(lineWidth, 2.5)
        ZStack {
            if isLive && !reduceMotion {
                Circle()
                    .stroke(LinearGradient(colors: liveColors, startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2)
                    .scaleEffect(pulse ? 1.16 : 1)
                    .opacity(pulse ? 0 : 0.8)
            }
            ring
            avatar
                .frame(width: size - (lineWidth + gap) * 2, height: size - (lineWidth + gap) * 2)
                .clipShape(Circle())
                .saturation(isSeen && !isLive ? 0.85 : 1)
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottom) {
            if isLive {
                Text(liveLabel)
                    .font(.system(size: max(size * 0.14, 8), weight: .heavy))
                    .tracking(0.5)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(LinearGradient(colors: liveColors, startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(theme.colors.background, lineWidth: 2))
                    .offset(y: 5)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: isSeen)
        .onAppear { startAnimations() }
        .onChange(of: isLive) { _, _ in startAnimations() }
        .onChange(of: isLoading) { _, _ in startAnimations() }
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(isLive ? "Live" : (isSeen ? "Seen" : "New story")))
    }

    @ViewBuilder
    private var ring: some View {
        if isLoading {
            Circle()
                .trim(from: 0, to: 0.82)
                .stroke(AngularGradient(colors: ringColors + [ringColors.first ?? .clear], center: .center),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: [lineWidth * 1.4, lineWidth * 1.6]))
                .padding(lineWidth / 2)
                .rotationEffect(.degrees(spin ? 360 : 0))
        } else if isSeen && !isLive {
            Circle()
                .strokeBorder(theme.colors.border, lineWidth: max(lineWidth * 0.55, 1.2))
        } else {
            Circle()
                .strokeBorder(
                    AngularGradient(colors: (isLive ? liveColors : ringColors) + [(isLive ? liveColors : ringColors).first ?? .clear],
                                    center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)),
                    lineWidth: lineWidth
                )
        }
    }

    private var ringColors: [Color] {
        if let colors, !colors.isEmpty { return colors }
        if let tint { return [tint, tint.opacity(0.55), theme.colors.secondary.opacity(0.7), tint] }
        return [
            Color(red: 1.00, green: 0.80, blue: 0.20),
            Color(red: 0.98, green: 0.45, blue: 0.20),
            Color(red: 0.90, green: 0.18, blue: 0.48),
            Color(red: 0.55, green: 0.22, blue: 0.85),
        ]
    }

    private var liveColors: [Color] {
        [Color(red: 0.98, green: 0.22, blue: 0.45), Color(red: 0.93, green: 0.10, blue: 0.25)]
    }

    private func startAnimations() {
        guard !reduceMotion else { return }
        spin = false
        pulse = false
        if isLoading {
            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) { spin = true }
        }
        if isLive {
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}
