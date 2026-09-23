//
//  KitoLoopMath.swift
//  KitoCarousel
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import Foundation

/// Index maths for looping carousels.
///
/// A looping carousel lays its items out many times over ("virtual" indices) and starts in the
/// middle copy, so the user can swipe either way for a long time. These helpers map between the
/// virtual index being shown and the real index into your data.
public enum KitoLoopMath {
    /// Wraps any integer, negative included, into `0..<count`. Returns 0 when `count` is 0.
    public static func wrap(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let remainder = index % count
        return remainder < 0 ? remainder + count : remainder
    }

    /// The real data index a virtual index shows.
    public static func realIndex(forVirtual virtual: Int, count: Int) -> Int {
        wrap(virtual, count: count)
    }

    /// How many virtual slots to lay out: `count × copies` when looping (and there's more than one
    /// item), otherwise just `count`.
    public static func virtualCount(for count: Int, loops: Bool, copies: Int) -> Int {
        guard count > 0 else { return 0 }
        guard loops, count > 1 else { return count }
        return count * max(copies, 1)
    }

    /// The virtual index in the middle copy that shows `real`.
    public static func middleVirtualIndex(for real: Int, count: Int, copies: Int) -> Int {
        guard count > 0 else { return 0 }
        return (max(copies, 1) / 2) * count + wrap(real, count: count)
    }

    /// The virtual index showing `real` that is closest to `current`, so a jump takes the shortest
    /// way round (from the last item to the first is one step forward, not `count - 1` back).
    public static func nearestVirtualIndex(to real: Int, from current: Int, count: Int) -> Int {
        guard count > 0 else { return current }
        var delta = wrap(real, count: count) - wrap(current, count: count)
        let half = count / 2
        if delta > half {
            delta -= count
        } else if delta < -half {
            delta += count
        }
        return current + delta
    }

    /// If `virtual` has drifted within `margin` copies of either end, the equivalent index in the
    /// middle copy to jump to (invisibly, since it shows the same item). `nil` when no jump is needed.
    public static func recenteredIndex(_ virtual: Int, count: Int, copies: Int, margin: Int) -> Int? {
        guard count > 0, copies > 2 else { return nil }
        let total = count * copies
        let edge = max(margin, 1) * count
        guard virtual < edge || virtual >= total - edge else { return nil }
        let middle = middleVirtualIndex(for: virtual, count: count, copies: copies)
        return middle == virtual ? nil : middle
    }

    /// Moves `index` by `delta`, wrapping when `wraps` is true and clamping otherwise.
    public static func step(_ index: Int, by delta: Int, count: Int, wraps: Bool) -> Int {
        guard count > 0 else { return 0 }
        let target = index + delta
        return wraps ? wrap(target, count: count) : min(max(target, 0), count - 1)
    }
}
