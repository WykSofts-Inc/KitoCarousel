//
//  KitoStoryPlayback.swift
//  KitoCarousel
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import Foundation

/// The state machine behind `KitoStoryViewer`: which person and which of their stories is showing,
/// how far through it the timer is, and what happens on tap, hold and time-out.
///
/// People with no stories are skipped. Going back from someone's first story opens the previous
/// person's last one; going back from the very first story restarts it.
public struct KitoStoryPlayback: Equatable, Sendable {
    /// What a call did, so the viewer can animate the right thing.
    public enum Event: Equatable, Sendable {
        /// Nothing changed.
        case none
        /// The next story from the same person.
        case advancedSegment
        /// The next person's first story.
        case advancedUser
        /// The previous story from the same person.
        case wentBackSegment
        /// The previous person.
        case wentBackUser
        /// The first story started over.
        case restartedSegment
        /// The last story finished.
        case finished
    }

    /// Stories per person, in order.
    public private(set) var segmentCounts: [Int]
    /// The person showing.
    public private(set) var user: Int = 0
    /// Their story showing.
    public private(set) var segment: Int = 0
    /// How far through that story, `0...1`.
    public private(set) var progress: Double = 0
    /// True while held (finger down, typing a reply, …).
    public private(set) var isPaused = false
    /// True once the last story has played out.
    public private(set) var isFinished = false

    /// - Parameters:
    ///   - segmentCounts: how many stories each person has.
    ///   - startingUser: the person to open on; if they have no stories, the next one who does.
    public init(segmentCounts: [Int], startingUser: Int = 0) {
        self.segmentCounts = segmentCounts.map { max($0, 0) }
        let start = min(max(startingUser, 0), max(segmentCounts.count - 1, 0))
        if let first = firstPlayableUser(from: start) {
            user = first
        } else {
            user = start
            isFinished = true
        }
    }

    /// Stories the current person has.
    public var segmentCount: Int {
        segmentCounts.indices.contains(user) ? segmentCounts[user] : 0
    }

    /// Whether someone with stories comes after the current person.
    public var hasNextUser: Bool { nextPlayableUser(after: user) != nil }

    /// Whether someone with stories comes before the current person.
    public var hasPreviousUser: Bool { previousPlayableUser(before: user) != nil }

    /// How full the progress bar for `index` is: seen ones full, the current one partly, later ones empty.
    public func fill(forSegment index: Int) -> Double {
        if index < segment { return 1 }
        if index == segment { return progress }
        return 0
    }

    /// Advances the timer. A story that runs out moves on as `next()` would.
    public mutating func tick(_ delta: TimeInterval, duration: TimeInterval) -> Event {
        guard !isPaused, !isFinished, delta > 0 else { return .none }
        guard duration > 0 else { return next() }
        progress += delta / duration
        return progress >= 1 ? next() : .none
    }

    /// The next story, the next person's first, or finished.
    public mutating func next() -> Event {
        guard !isFinished else { return .none }
        if segment + 1 < segmentCount {
            segment += 1
            progress = 0
            return .advancedSegment
        }
        if let nextUser = nextPlayableUser(after: user) {
            user = nextUser
            segment = 0
            progress = 0
            return .advancedUser
        }
        progress = 1
        isFinished = true
        return .finished
    }

    /// The previous story, the previous person's last, or the first story again.
    public mutating func previous() -> Event {
        guard !isFinished else { return .none }
        if segment > 0 {
            segment -= 1
            progress = 0
            return .wentBackSegment
        }
        if let previousUser = previousPlayableUser(before: user) {
            user = previousUser
            segment = max(segmentCounts[previousUser] - 1, 0)
            progress = 0
            return .wentBackUser
        }
        progress = 0
        return .restartedSegment
    }

    /// Opens `index`'s first story (swiping between people). Returns `.none` if they have no stories.
    public mutating func jump(toUser index: Int) -> Event {
        guard segmentCounts.indices.contains(index), segmentCounts[index] > 0, index != user else { return .none }
        let forward = index > user
        user = index
        segment = 0
        progress = 0
        isFinished = false
        return forward ? .advancedUser : .wentBackUser
    }

    /// Holds the timer.
    public mutating func pause() { isPaused = true }

    /// Releases the timer.
    public mutating func resume() { isPaused = false }

    /// The next person with stories after `index`.
    public func nextPlayableUser(after index: Int) -> Int? {
        guard index + 1 < segmentCounts.count else { return nil }
        return segmentCounts[(index + 1)...].firstIndex { $0 > 0 }
    }

    /// The nearest person with stories before `index`.
    public func previousPlayableUser(before index: Int) -> Int? {
        guard index > 0, index <= segmentCounts.count else { return nil }
        return segmentCounts[..<index].lastIndex { $0 > 0 }
    }

    private func firstPlayableUser(from index: Int) -> Int? {
        guard segmentCounts.indices.contains(index) else { return nil }
        return segmentCounts[index...].firstIndex { $0 > 0 }
    }
}
