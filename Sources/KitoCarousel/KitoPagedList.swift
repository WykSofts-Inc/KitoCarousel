//
//  KitoPagedList.swift
//  KitoCarousel
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import KitoCore

/// Full-screen vertical paging, Reels-style: one item per screen, a haptic on each snap, and the
/// leaving page easing back as the next slides up. Your content learns whether it's the active
/// page, so a video can play only while it's on screen.
///
/// ```swift
/// KitoPagedList(clips, selection: $index) { clip, isActive in
///     ClipView(clip, isPlaying: isActive)
/// }
/// ```
public struct KitoPagedList<Data: RandomAccessCollection, Content: View>: View where Data.Element: Identifiable {
    private let data: Data
    private let selection: Binding<Int>?
    private let tint: Color?
    private let content: (Data.Element, Bool) -> Content

    @Environment(\.kitoTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrolledID: Int?
    @State private var ownSelection = 0

    /// - Parameters:
    ///   - data: the pages.
    ///   - selection: the page on screen. Set it to scroll there.
    ///   - tint: colour behind pages while they load.
    ///   - content: one page, and whether it's the active one.
    public init(
        _ data: Data,
        selection: Binding<Int>? = nil,
        tint: Color? = nil,
        @ViewBuilder content: @escaping (Data.Element, Bool) -> Content
    ) {
        self.data = data
        self.selection = selection
        self.tint = tint
        self.content = content
        let start = min(max(selection?.wrappedValue ?? 0, 0), max(data.count - 1, 0))
        _scrolledID = State(initialValue: data.isEmpty ? nil : start)
        _ownSelection = State(initialValue: start)
    }

    public var body: some View {
        let reduceMotion = reduceMotion
        ScrollViewReader { reader in
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(0..<data.count, id: \.self) { index in
                        if let element = data.kitoElement(at: index) {
                            content(element, index == current)
                                .containerRelativeFrame([.horizontal, .vertical])
                                .clipped()
                                .scrollTransition(.interactive, axis: .vertical) { view, phase in
                                    view
                                        .scaleEffect(reduceMotion ? 1 : 1 - abs(phase.value) * 0.08)
                                        .opacity(1 - abs(phase.value) * 0.35)
                                        .blur(radius: reduceMotion ? 0 : abs(phase.value) * 4)
                                }
                                .accessibilityElement(children: .contain)
                                .accessibilityValue(Text("\(index + 1) of \(data.count)"))
                        }
                    }
                }
                .scrollTargetLayout()
            }
            .onAppear {
                if let scrolledID, scrolledID > 0 { reader.scrollTo(scrolledID, anchor: .top) }
            }
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $scrolledID)
        .scrollIndicators(.hidden)
        .background(tint ?? theme.colors.onBackground)
        .sensoryFeedback(.selection, trigger: current)
        .onChange(of: scrolledID) { _, newValue in
            guard let newValue, newValue != current else { return }
            ownSelection = newValue
            selection?.wrappedValue = newValue
        }
        .onChange(of: selection?.wrappedValue) { _, newValue in
            guard let newValue, newValue != scrolledID else { return }
            ownSelection = newValue
            withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) { scrolledID = newValue }
        }
    }

    private var current: Int { selection?.wrappedValue ?? ownSelection }
}
