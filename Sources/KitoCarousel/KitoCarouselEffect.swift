//
//  KitoCarouselEffect.swift
//  KitoCarousel
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import SwiftUI

/// How items move as they scroll away from the centre of a `KitoCarousel`.
public enum KitoCarouselEffect: String, CaseIterable, Hashable, Sendable {
    /// Flat, no effect.
    case none
    /// Neighbours shrink and dim a little.
    case scale
    /// Neighbours tilt on their bottom edge and drop, like cards in a hand.
    case rotate
    /// Each item's content drifts against the scroll, like a window onto a wider scene.
    case parallax
    /// Neighbours swing round in 3D to face the centre.
    case coverFlow
    /// Neighbours fade and soften.
    case fade
    /// Upcoming items wait stacked behind the current one and slide out as you swipe.
    case stack
}

/// The transform for one item `position` pages from the centre (negative is to the left).
struct KitoCarouselTransform: Equatable {
    var scale: CGFloat = 1
    var rotation: Double = 0
    var rotation3D: Double = 0
    var offsetX: CGFloat = 0
    var offsetY: CGFloat = 0
    var opacity: Double = 1
    var blur: CGFloat = 0

    static let identity = KitoCarouselTransform()

    init() {}

    init(effect: KitoCarouselEffect, position: CGFloat, pageWidth: CGFloat) {
        let clamped = min(max(position, -2), 2)
        let distance = min(abs(position), 1)
        switch effect {
        case .none:
            break
        case .parallax:
            scale = 1 - 0.05 * distance
        case .scale:
            scale = 1 - 0.12 * distance
            opacity = 1 - 0.25 * Double(distance)
        case .rotate:
            rotation = Double(min(max(position, -1.5), 1.5)) * 9
            offsetY = 22 * distance
            scale = 1 - 0.05 * distance
        case .coverFlow:
            rotation3D = Double(-min(max(position, -1), 1)) * 52
            scale = 1 - 0.16 * distance
            offsetX = -min(max(position, -1.2), 1.2) * pageWidth * 0.14
            opacity = 1 - 0.15 * Double(distance)
        case .fade:
            opacity = 1 - 0.7 * Double(distance)
            scale = 1 - 0.06 * distance
            blur = 3 * distance
        case .stack:
            if position > 0 {
                let depth = min(position, 3)
                offsetX = -depth * pageWidth + depth * 22
                scale = 1 - 0.07 * depth
                opacity = position > 2.6 ? max(0, Double(3.4 - position) / 0.8) : 1
            } else {
                scale = 1 - 0.08 * distance
                rotation = Double(clamped) * 6
                opacity = 1 - 0.35 * Double(distance)
            }
        }
    }
}

/// Where an item sits, in pages, relative to the viewport centre.
func kitoCarouselPosition(frame: CGRect, viewportWidth: CGFloat, pageWidth: CGFloat) -> CGFloat {
    guard pageWidth > 0 else { return 0 }
    return (frame.midX - viewportWidth / 2) / pageWidth
}

/// Parallax offset for an item's content: drifts against the scroll, never past `overflow`.
func kitoParallaxOffset(frame: CGRect, viewportWidth: CGFloat, overflow: CGFloat) -> CGFloat {
    let drift = -(frame.midX - viewportWidth / 2) * 0.28
    return min(max(drift, -overflow), overflow)
}

extension RandomAccessCollection {
    /// The element `offset` places from the start, or `nil` when out of range.
    func kitoElement(at offset: Int) -> Element? {
        guard offset >= 0, offset < count else { return nil }
        return self[index(startIndex, offsetBy: offset)]
    }
}
