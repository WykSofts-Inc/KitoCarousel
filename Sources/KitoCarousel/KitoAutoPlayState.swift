//
//  KitoAutoPlayState.swift
//  KitoCarousel
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import Foundation

/// The auto-play clock behind carousels and banners: how far through the current page it is, and
/// whether anything (a finger, a hidden screen, VoiceOver) is holding it.
///
/// ```swift
/// var clock = KitoAutoPlayState(interval: 4)
/// if clock.tick(1 / 30) { advance() }     // true once every 4 seconds of unpaused time
/// clock.pause(.touch)                     // a finger is down
/// clock.resume(.touch)                    // still paused if another reason holds it
/// ```
public struct KitoAutoPlayState: Equatable, Sendable {
    /// Why auto-play is holding. Several can hold at once; it runs only when none do.
    public struct PauseReason: OptionSet, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        /// The user is touching or scrolling.
        public static let touch = PauseReason(rawValue: 1 << 0)
        /// The app paused it (off screen, a sheet is up, …).
        public static let external = PauseReason(rawValue: 1 << 1)
        /// An assistive technology is running.
        public static let accessibility = PauseReason(rawValue: 1 << 2)
    }

    /// Seconds each page stays before advancing.
    public var interval: TimeInterval
    /// Seconds spent on the current page, while not paused.
    public private(set) var elapsed: TimeInterval = 0
    /// Everything currently holding auto-play.
    public private(set) var pauseReasons: PauseReason = []

    public init(interval: TimeInterval) {
        self.interval = interval
    }

    /// True while any reason holds auto-play.
    public var isPaused: Bool { !pauseReasons.isEmpty }

    /// How far through the current page, `0...1`. Drives `.progress` page indicators.
    public var progress: Double {
        guard interval > 0 else { return 0 }
        return min(max(elapsed / interval, 0), 1)
    }

    /// Advances the clock by `delta` seconds. Returns true when the page should advance, and starts
    /// the next page's clock from zero.
    @discardableResult
    public mutating func tick(_ delta: TimeInterval) -> Bool {
        guard !isPaused, interval > 0, delta > 0 else { return false }
        elapsed += delta
        guard elapsed >= interval else { return false }
        elapsed = 0
        return true
    }

    /// Holds auto-play for `reason`.
    public mutating func pause(_ reason: PauseReason = .external) {
        pauseReasons.insert(reason)
    }

    /// Releases `reason`. Auto-play resumes once nothing else holds it.
    public mutating func resume(_ reason: PauseReason = .external) {
        pauseReasons.remove(reason)
    }

    /// Starts the current page's clock again, e.g. after the user swiped to a new page.
    public mutating func restart() {
        elapsed = 0
    }
}
