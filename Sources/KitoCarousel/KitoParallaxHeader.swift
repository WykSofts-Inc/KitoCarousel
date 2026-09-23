//
//  KitoParallaxHeader.swift
//  KitoCarousel
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import KitoCore

/// A scroll view with a stretchy hero header. Pull down and the header grows to fill the gap;
/// scroll up and it drifts at half speed and softens, the large title fades, and a compact title
/// bar settles in at the top.
///
/// ```swift
/// KitoParallaxHeader(title: "Zanzibar", subtitle: "Stone Town · Nungwi · Paje") {
///     BeachScene()
/// } content: {
///     ForEach(sections) { SectionView($0) }
/// }
/// ```
public struct KitoParallaxHeader<Header: View, Content: View>: View {
    private let title: String
    private let subtitle: String?
    private let height: CGFloat
    private let tint: Color?
    private let header: Header
    private let content: Content

    @Environment(\.kitoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var headerMinY: CGFloat = 0

    /// - Parameters:
    ///   - title: shown large over the header, then small in the title bar.
    ///   - subtitle: a line under the large title.
    ///   - height: header height at rest, status bar included.
    ///   - tint: colour of the compact title.
    ///   - header: the hero, usually an image; fills the header.
    ///   - content: everything below.
    public init(
        title: String,
        subtitle: String? = nil,
        height: CGFloat = 320,
        tint: Color? = nil,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.height = height
        self.tint = tint
        self.header = header()
        self.content = content()
    }

    public var body: some View {
        GeometryReader { outer in
            let topInset = outer.safeAreaInsets.top
            let barHeight = topInset + 44
            let collapseDistance = max(height - barHeight, 1)
            ScrollView {
                VStack(spacing: 0) {
                    hero(collapseDistance: collapseDistance)
                        .zIndex(1)
                    content
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(theme.colors.background)
                }
            }
            .background(theme.colors.background)
            .ignoresSafeArea(edges: .top)
            .overlay(alignment: .top) {
                titleBar(barHeight: barHeight, collapseDistance: collapseDistance)
                    .ignoresSafeArea(edges: .top)
            }
        }
    }

    private func hero(collapseDistance: CGFloat) -> some View {
        GeometryReader { proxy in
            let minY = proxy.frame(in: .scrollView(axis: .vertical)).minY
            let stretch = max(minY, 0)
            let collapse = max(-minY, 0)
            let progress = min(collapse / collapseDistance, 1)
            ZStack(alignment: .bottomLeading) {
                header
                    .frame(width: proxy.size.width, height: height + stretch)
                    .offset(y: reduceMotion ? 0 : collapse * 0.5)
                    .blur(radius: reduceMotion ? 0 : progress * 10)
                    .clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                    .allowsHitTesting(false)
                VStack(alignment: .leading, spacing: theme.spacing.xs) {
                    Text(title)
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.white)
                    if let subtitle {
                        Text(subtitle)
                            .font(theme.typography.bodyEmphasized)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                .shadow(color: .black.opacity(0.3), radius: 8, y: 2)
                .padding(theme.spacing.xl)
                .opacity(1 - Double(progress) * 1.6)
                .offset(y: reduceMotion ? 0 : -collapse * 0.15)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
            }
            .frame(width: proxy.size.width, height: height + stretch)
            .offset(y: -stretch)
            .onChange(of: minY, initial: true) { _, value in headerMinY = value }
        }
        .frame(height: height)
    }

    private func titleBar(barHeight: CGFloat, collapseDistance: CGFloat) -> some View {
        let progress = min(max(-headerMinY / collapseDistance, 0), 1)
        let reveal = Double(min(max((progress - 0.7) / 0.3, 0), 1))
        return ZStack(alignment: .bottom) {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(theme.colors.background.opacity(0.35))
                .overlay(alignment: .bottom) {
                    Rectangle().fill(theme.colors.border).frame(height: 0.5)
                }
                .opacity(reveal)
            Text(title)
                .font(theme.typography.bodyEmphasized)
                .foregroundStyle(tint ?? theme.colors.onBackground)
                .opacity(reveal)
                .offset(y: (1 - reveal) * 10)
                .padding(.bottom, 12)
                .accessibilityHidden(reveal < 0.5)
        }
        .frame(height: barHeight)
        .allowsHitTesting(false)
    }
}
