//
//  KitoSwipeDecision.swift
//  KitoCarousel
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import CoreGraphics

/// Which way a card left the deck.
public enum KitoSwipeDirection: String, CaseIterable, Hashable, Sendable {
    /// Pass ("nope").
    case left
    /// Like.
    case right
    /// Super like.
    case up
}

/// How strongly a drag points each way, `0...1`, for fading in stamps and growing buttons.
public struct KitoSwipeProgress: Equatable, Sendable {
    public var left: Double
    public var right: Double
    public var up: Double

    public init(left: Double = 0, right: Double = 0, up: Double = 0) {
        self.left = left
        self.right = right
        self.up = up
    }

    /// The strongest direction and its strength, or `nil` when the card is at rest.
    public var dominant: (direction: KitoSwipeDirection, amount: Double)? {
        let pairs: [(KitoSwipeDirection, Double)] = [(.left, left), (.right, right), (.up, up)]
        guard let best = pairs.max(by: { $0.1 < $1.1 }), best.1 > 0 else { return nil }
        return best
    }
}

/// Decides whether a released drag throws the card off the deck, and which way.
///
/// A card goes when it's dragged past `distanceThreshold` of the card's width (height for up), or
/// flung faster than `velocityThreshold` points per second the way it's already moving. A fast
/// flick back towards the centre cancels a long drag.
public struct KitoSwipeDecision: Equatable, Sendable {
    /// Fraction of the card's size a drag must cover, `0...1`.
    public var distanceThreshold: CGFloat
    /// Release speed, in points per second, that throws the card regardless of distance.
    public var velocityThreshold: CGFloat
    /// Whether an upward throw counts (super like).
    public var allowsUp: Bool

    public init(distanceThreshold: CGFloat = 0.32, velocityThreshold: CGFloat = 650, allowsUp: Bool = true) {
        self.distanceThreshold = distanceThreshold
        self.velocityThreshold = velocityThreshold
        self.allowsUp = allowsUp
    }

    /// Where the card goes, or `nil` to spring it back.
    public func direction(translation: CGSize, velocity: CGSize, in size: CGSize) -> KitoSwipeDirection? {
        let width = max(size.width, 1)
        let height = max(size.height, 1)
        let dx = translation.width
        let dy = translation.height

        if allowsUp, dy < 0, -dy > abs(dx) {
            let far = -dy > height * distanceThreshold
            let flung = -velocity.height > velocityThreshold
            let flickedBack = velocity.height > velocityThreshold
            if (far && !flickedBack) || flung { return .up }
        }

        let horizontal: KitoSwipeDirection = dx >= 0 ? .right : .left
        let sign: CGFloat = dx >= 0 ? 1 : -1
        let alongVelocity = velocity.width * sign

        if abs(dx) > width * distanceThreshold {
            return alongVelocity < -velocityThreshold ? nil : horizontal
        }
        if abs(dx) > 16, alongVelocity > velocityThreshold {
            return horizontal
        }
        return nil
    }

    /// How close a drag is to each threshold, `0...1` per direction.
    public func progress(translation: CGSize, in size: CGSize) -> KitoSwipeProgress {
        let width = max(size.width * distanceThreshold, 1)
        let height = max(size.height * distanceThreshold, 1)
        let dx = Double(translation.width / width)
        let dy = Double(-translation.height / height)
        let horizontalDominates = abs(translation.width) >= -translation.height
        return KitoSwipeProgress(
            left: horizontalDominates ? min(max(-dx, 0), 1) : 0,
            right: horizontalDominates ? min(max(dx, 0), 1) : 0,
            up: allowsUp && !horizontalDominates ? min(max(dy, 0), 1) : 0
        )
    }

    /// Tilt, in degrees, for a card dragged `translation` across a card `width` wide.
    public static func rotation(for translation: CGSize, width: CGFloat, maxDegrees: Double = 14) -> Double {
        guard width > 0 else { return 0 }
        let fraction = Double(translation.width / width)
        return min(max(fraction * maxDegrees * 1.6, -maxDegrees * 1.6), maxDegrees * 1.6)
    }

    /// Where a thrown card ends up, off screen, continuing the throw.
    public static func exitOffset(for direction: KitoSwipeDirection, translation: CGSize, velocity: CGSize, in size: CGSize) -> CGSize {
        let throwX = max(size.width, 1) * 1.6
        let throwY = max(size.height, 1) * 1.5
        switch direction {
        case .left:
            return CGSize(width: -throwX, height: translation.height + velocity.height * 0.12)
        case .right:
            return CGSize(width: throwX, height: translation.height + velocity.height * 0.12)
        case .up:
            return CGSize(width: translation.width + velocity.width * 0.12, height: -throwY)
        }
    }
}
