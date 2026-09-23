//
//  KitoSnapGrid.swift
//  KitoCarousel
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI
import KitoCore

/// A horizontally paging grid, App Store style: items fill `rows` rows, a column snaps to the edge
/// after each swipe, and the next column peeks in.
///
/// ```swift
/// KitoSnapGrid(dishes, rows: 3) { dish in
///     DishRow(dish)
/// }
/// ```
public struct KitoSnapGrid<Data: RandomAccessCollection, Content: View>: View where Data.Element: Identifiable {
    private let data: Data
    private let rows: Int
    private let columnsPerPage: Int
    private let rowHeight: CGFloat
    private let spacing: CGFloat
    private let peek: CGFloat
    private let tint: Color?
    private let content: (Data.Element) -> Content

    @Environment(\.kitoTheme) private var theme
    @State private var scrolledID: Data.Element.ID?

    /// - Parameters:
    ///   - data: the items, filled top to bottom, then left to right.
    ///   - rows: rows per column.
    ///   - columnsPerPage: columns visible at once.
    ///   - rowHeight: height of one row.
    ///   - spacing: gap between rows and columns.
    ///   - peek: how much of the next column shows.
    ///   - tint: colour of the hairline between rows.
    ///   - content: one item.
    public init(
        _ data: Data,
        rows: Int = 3,
        columnsPerPage: Int = 1,
        rowHeight: CGFloat = 64,
        spacing: CGFloat = 12,
        peek: CGFloat = 28,
        tint: Color? = nil,
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) {
        self.data = data
        self.rows = max(rows, 1)
        self.columnsPerPage = max(columnsPerPage, 1)
        self.rowHeight = rowHeight
        self.spacing = spacing
        self.peek = peek
        self.tint = tint
        self.content = content
    }

    public var body: some View {
        let gridRows = Array(repeating: GridItem(.fixed(rowHeight), spacing: spacing), count: rows)
        let rows = self.rows
        let divider = (tint ?? theme.colors.border).opacity(tint == nil ? 1 : 0.4)
        ScrollView(.horizontal) {
            LazyHGrid(rows: gridRows, spacing: spacing) {
                ForEach(Array(data.enumerated()), id: \.element.id) { offset, element in
                    content(element)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .overlay(alignment: .bottom) {
                            if (offset + 1) % rows != 0 && offset != data.count - 1 {
                                Rectangle().fill(divider).frame(height: 0.5).offset(y: spacing / 2)
                            }
                        }
                        .containerRelativeFrame(.horizontal, count: columnsPerPage, spacing: spacing)
                        .scrollTransition(.interactive, axis: .horizontal) { view, phase in
                            view.opacity(1 - abs(phase.value) * 0.4)
                        }
                        .id(element.id)
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.leading, theme.spacing.lg, for: .scrollContent)
        .contentMargins(.trailing, theme.spacing.lg + peek, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
        .scrollPosition(id: $scrolledID)
        .scrollIndicators(.hidden)
        .frame(height: CGFloat(rows) * rowHeight + CGFloat(rows - 1) * spacing)
        .sensoryFeedback(.selection, trigger: scrolledID)
    }
}
