//
//  KitoStoryTray.swift
//  KitoCarousel
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import KitoCore

/// The "Your story" tile at the start of a `KitoStoryTray`.
public struct KitoYourStory {
    /// Caption under the tile.
    public var title: String
    /// Your picture; initials on a gradient when `nil`.
    public var image: Image?
    /// Shown when there's no image.
    public var initials: String
    /// Whether you've posted something; shows a ring instead of the + badge.
    public var hasStory: Bool
    /// Called when the tile is tapped.
    public var onTap: () -> Void

    public init(title: String = "Your story", image: Image? = nil, initials: String = "", hasStory: Bool = false, onTap: @escaping () -> Void) {
        self.title = title
        self.image = image
        self.initials = initials
        self.hasStory = hasStory
        self.onTap = onTap
    }
}

/// A horizontal row of story rings, with an optional "Your story +" tile first. Tapping a ring
/// spins it briefly, then calls `onSelect`.
///
/// ```swift
/// KitoStoryTray(friends, title: \.name, isSeen: \.seen,
///               yourStory: KitoYourStory(initials: "WN") { compose() },
///               onSelect: { open($0) }) { friend in
///     Avatar(friend)
/// }
/// ```
public struct KitoStoryTray<Data: RandomAccessCollection, Avatar: View>: View where Data.Element: Identifiable {
    private let data: Data
    private let title: (Data.Element) -> String
    private let isSeen: (Data.Element) -> Bool
    private let isLive: (Data.Element) -> Bool
    private let yourStory: KitoYourStory?
    private let ringSize: CGFloat
    private let tint: Color?
    private let onSelect: (Data.Element) -> Void
    private let avatar: (Data.Element) -> Avatar

    @Environment(\.kitoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var loadingID: Data.Element.ID?
    @State private var tapTick = 0

    /// - Parameters:
    ///   - data: the people with stories.
    ///   - title: the caption under each ring.
    ///   - isSeen: whether everything they posted has been watched.
    ///   - isLive: whether they're live now.
    ///   - yourStory: the first tile, for posting your own.
    ///   - ringSize: diameter of each ring.
    ///   - tint: ring gradient colour; a sunset gradient by default.
    ///   - onSelect: a ring was tapped.
    ///   - avatar: the picture inside each ring.
    public init(
        _ data: Data,
        title: @escaping (Data.Element) -> String,
        isSeen: @escaping (Data.Element) -> Bool = { _ in false },
        isLive: @escaping (Data.Element) -> Bool = { _ in false },
        yourStory: KitoYourStory? = nil,
        ringSize: CGFloat = 68,
        tint: Color? = nil,
        onSelect: @escaping (Data.Element) -> Void,
        @ViewBuilder avatar: @escaping (Data.Element) -> Avatar
    ) {
        self.data = data
        self.title = title
        self.isSeen = isSeen
        self.isLive = isLive
        self.yourStory = yourStory
        self.ringSize = ringSize
        self.tint = tint
        self.onSelect = onSelect
        self.avatar = avatar
    }

    public var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: theme.spacing.lg) {
                if let yourStory {
                    yourStoryTile(yourStory)
                }
                ForEach(data) { element in
                    Button { select(element) } label: {
                        tile(title: title(element)) {
                            KitoStoryRing(isSeen: isSeen(element), isLive: isLive(element), isLoading: loadingID == element.id,
                                          size: ringSize, tint: tint) {
                                avatar(element)
                            }
                        }
                    }
                    .buttonStyle(KitoPressScaleStyle())
                    .accessibilityLabel(Text(title(element)))
                }
            }
            .padding(.horizontal, theme.spacing.lg)
            .padding(.vertical, theme.spacing.xs)
        }
        .scrollIndicators(.hidden)
        .sensoryFeedback(.selection, trigger: tapTick)
    }

    private func tile<Ring: View>(title: String, @ViewBuilder ring: () -> Ring) -> some View {
        VStack(spacing: theme.spacing.xs + 2) {
            ring()
            Text(title)
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.onBackground)
                .lineLimit(1)
                .frame(width: ringSize + 8)
        }
    }

    private func yourStoryTile(_ story: KitoYourStory) -> some View {
        Button {
            tapTick += 1
            story.onTap()
        } label: {
            tile(title: story.title) {
                KitoStoryRing(isSeen: !story.hasStory, size: ringSize, tint: tint) {
                    if let image = story.image {
                        image.resizable().scaledToFill()
                    } else {
                        ZStack {
                            LinearGradient(colors: [theme.colors.surfaceMuted, theme.colors.border], startPoint: .top, endPoint: .bottom)
                            Text(story.initials)
                                .font(.system(size: ringSize * 0.28, weight: .semibold, design: .rounded))
                                .foregroundStyle(theme.colors.onSurface)
                        }
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if !story.hasStory {
                        Image(systemName: "plus")
                            .font(.system(size: ringSize * 0.16, weight: .bold))
                            .foregroundStyle(theme.colors.onPrimary)
                            .frame(width: ringSize * 0.32, height: ringSize * 0.32)
                            .background(tint ?? theme.colors.primary, in: Circle())
                            .overlay(Circle().strokeBorder(theme.colors.background, lineWidth: 2.5))
                    }
                }
            }
        }
        .buttonStyle(KitoPressScaleStyle())
        .accessibilityLabel(Text(story.title))
        .accessibilityHint(Text(story.hasStory ? "Opens your story" : "Adds to your story"))
    }

    private func select(_ element: Data.Element) {
        tapTick += 1
        guard !reduceMotion else {
            onSelect(element)
            return
        }
        loadingID = element.id
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(420))
            loadingID = nil
            onSelect(element)
        }
    }
}
