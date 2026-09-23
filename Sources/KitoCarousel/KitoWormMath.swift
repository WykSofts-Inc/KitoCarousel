//
//  KitoWormMath.swift
//  KitoCarousel
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import CoreGraphics

/// Interpolation for the liquid "worm" page indicator.
///
/// Between two pages the leading edge races ahead in the first half of the move while the trailing
/// edge waits, then the trailing edge catches up in the second half, so the dot stretches across
/// both pages and snaps back to a dot. Works in either direction.
public enum KitoWormMath {
    /// The worm's extent in page units: `lower` and `upper` are page positions.
    public struct Span: Equatable, Sendable {
        public var lower: Double
        public var upper: Double

        public init(lower: Double, upper: Double) {
            self.lower = lower
            self.upper = upper
        }

        /// How many pages it covers beyond one dot.
        public var length: Double { upper - lower }
    }

    /// The worm's span at a fractional page `position` (2.25 is a quarter of the way from page 2 to 3).
    public static func span(at position: Double) -> Span {
        let base = position.rounded(.down)
        let t = position - base
        let head = base + min(1, t * 2)
        let tail = base + max(0, t * 2 - 1)
        return Span(lower: min(head, tail), upper: max(head, tail))
    }

    /// The worm's horizontal frame, in points, for dots `dotSize` wide set `spacing` apart.
    public static func frame(at position: Double, dotSize: CGFloat, spacing: CGFloat) -> (minX: CGFloat, width: CGFloat) {
        let step = Double(dotSize + spacing)
        let span = span(at: position)
        return (CGFloat(span.lower * step), CGFloat(span.length * step) + dotSize)
    }
}
