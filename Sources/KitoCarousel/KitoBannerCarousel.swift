//
//  KitoBannerCarousel.swift
//  KitoCarousel
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import KitoCore

/// Full-width promo banners that advance on their own, with a page indicator that fills as each
/// banner's time runs out. Loops forever; touching a banner holds it.
///
/// ```swift
/// KitoBannerCarousel(deals, interval: 5) { deal in
///     DealBanner(deal)
/// }
/// ```
public struct KitoBannerCarousel<Data: RandomAccessCollection, Content: View>: View where Data.Element: Identifiable {
    private let data: Data
    private let selection: Binding<Int>?
    private let interval: TimeInterval
    private let height: CGFloat
    private let indicatorStyle: KitoPageIndicatorStyle
    private let effect: KitoCarouselEffect
    private let tint: Color?
    private let content: (Data.Element) -> Content

    @Environment(\.kitoTheme) private var theme
    @State private var ownSelection = 0
    @State private var progress: Double = 0

    /// - Parameters:
    ///   - data: the banners.
    ///   - selection: the banner showing.
    ///   - interval: seconds each banner stays.
    ///   - height: banner height.
    ///   - indicatorStyle: the indicator under the banners; `.progress` shows the countdown.
    ///   - effect: how banners move as they scroll; `.parallax` by default.
    ///   - tint: indicator colour.
    ///   - content: one banner.
    public init(
        _ data: Data,
        selection: Binding<Int>? = nil,
        interval: TimeInterval = 5,
        height: CGFloat = 180,
        indicatorStyle: KitoPageIndicatorStyle = .progress,
        effect: KitoCarouselEffect = .parallax,
        tint: Color? = nil,
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) {
        self.data = data
        self.selection = selection
        self.interval = interval
        self.height = height
        self.indicatorStyle = indicatorStyle
        self.effect = effect
        self.tint = tint
        self.content = content
    }

    public var body: some View {
        let binding = Binding<Int>(
            get: { selection?.wrappedValue ?? ownSelection },
            set: { newValue in
                ownSelection = newValue
                selection?.wrappedValue = newValue
            }
        )
        VStack(spacing: theme.spacing.sm) {
            KitoCarousel(
                data,
                selection: binding,
                effect: effect,
                spacing: theme.spacing.lg,
                peek: 0,
                loops: true,
                autoPlay: interval,
                autoPlayProgress: $progress,
                cornerRadius: theme.radii.xl,
                tint: nil
            ) { element in
                content(element)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
            }
            .frame(height: height)

            if data.count > 1 {
                KitoPageIndicator(count: data.count, selection: binding, style: indicatorStyle, progress: progress, dotSize: 7, tint: tint)
            }
        }
    }
}
