//
//  KitoCarouselTests.swift
//  KitoCarousel
//
//  Created by Wycliff on 9/23/26.
//  Copyright © 2026 wyksoftsinc.com. All rights reserved.
//

import XCTest
@testable import KitoCarousel

final class KitoLoopMathTests: XCTestCase {
    func testWrapHandlesNegativesAndOverflow() {
        XCTAssertEqual(KitoLoopMath.wrap(0, count: 5), 0)
        XCTAssertEqual(KitoLoopMath.wrap(7, count: 5), 2)
        XCTAssertEqual(KitoLoopMath.wrap(-1, count: 5), 4)
        XCTAssertEqual(KitoLoopMath.wrap(-11, count: 5), 4)
        XCTAssertEqual(KitoLoopMath.wrap(3, count: 0), 0)
    }

    func testVirtualToRealIndex() {
        XCTAssertEqual(KitoLoopMath.realIndex(forVirtual: 252, count: 5), 2)
        XCTAssertEqual(KitoLoopMath.realIndex(forVirtual: 5, count: 5), 0)
    }

    func testVirtualCountOnlyMultipliesWhenLooping() {
        XCTAssertEqual(KitoLoopMath.virtualCount(for: 4, loops: true, copies: 101), 404)
        XCTAssertEqual(KitoLoopMath.virtualCount(for: 4, loops: false, copies: 101), 4)
        XCTAssertEqual(KitoLoopMath.virtualCount(for: 1, loops: true, copies: 101), 1)
        XCTAssertEqual(KitoLoopMath.virtualCount(for: 0, loops: true, copies: 101), 0)
    }

    func testMiddleVirtualIndexSitsInTheCentreCopy() {
        let middle = KitoLoopMath.middleVirtualIndex(for: 3, count: 5, copies: 101)
        XCTAssertEqual(middle, 50 * 5 + 3)
        XCTAssertEqual(KitoLoopMath.realIndex(forVirtual: middle, count: 5), 3)
    }

    func testNearestVirtualIndexTakesTheShortWayRound() {
        // From the last item to the first is one step forward.
        XCTAssertEqual(KitoLoopMath.nearestVirtualIndex(to: 0, from: 254, count: 5), 255)
        // From the first to the last is one step back.
        XCTAssertEqual(KitoLoopMath.nearestVirtualIndex(to: 4, from: 250, count: 5), 249)
        // Nearby moves go straight there.
        XCTAssertEqual(KitoLoopMath.nearestVirtualIndex(to: 2, from: 250, count: 5), 252)
        XCTAssertEqual(KitoLoopMath.nearestVirtualIndex(to: 2, from: 252, count: 5), 252)
    }

    func testRecentersOnlyNearTheEnds() {
        XCTAssertNil(KitoLoopMath.recenteredIndex(250, count: 5, copies: 101, margin: 2))
        let fromStart = KitoLoopMath.recenteredIndex(3, count: 5, copies: 101, margin: 2)
        XCTAssertEqual(fromStart, 253)
        let fromEnd = KitoLoopMath.recenteredIndex(503, count: 5, copies: 101, margin: 2)
        XCTAssertEqual(fromEnd, 253)
        XCTAssertNil(KitoLoopMath.recenteredIndex(3, count: 5, copies: 1, margin: 2))
    }

    func testStepWrapsOrClamps() {
        XCTAssertEqual(KitoLoopMath.step(4, by: 1, count: 5, wraps: true), 0)
        XCTAssertEqual(KitoLoopMath.step(0, by: -1, count: 5, wraps: true), 4)
        XCTAssertEqual(KitoLoopMath.step(4, by: 1, count: 5, wraps: false), 4)
        XCTAssertEqual(KitoLoopMath.step(0, by: -1, count: 5, wraps: false), 0)
    }
}

final class KitoAutoPlayStateTests: XCTestCase {
    func testAdvancesOncePerInterval() {
        var clock = KitoAutoPlayState(interval: 1)
        XCTAssertFalse(clock.tick(0.4))
        XCTAssertEqual(clock.progress, 0.4, accuracy: 0.0001)
        XCTAssertFalse(clock.tick(0.4))
        XCTAssertTrue(clock.tick(0.3))
        XCTAssertEqual(clock.progress, 0)
    }

    func testPauseReasonsStack() {
        var clock = KitoAutoPlayState(interval: 1)
        clock.pause(.touch)
        clock.pause(.external)
        XCTAssertFalse(clock.tick(5))
        clock.resume(.touch)
        XCTAssertTrue(clock.isPaused)
        XCTAssertFalse(clock.tick(5))
        clock.resume(.external)
        XCTAssertFalse(clock.isPaused)
        XCTAssertTrue(clock.tick(1))
    }

    func testRestartAndZeroInterval() {
        var clock = KitoAutoPlayState(interval: 2)
        clock.tick(1)
        clock.restart()
        XCTAssertEqual(clock.elapsed, 0)
        var never = KitoAutoPlayState(interval: 0)
        XCTAssertFalse(never.tick(10))
        XCTAssertEqual(never.progress, 0)
        XCTAssertFalse(clock.tick(-1))
    }
}

final class KitoStoryPlaybackTests: XCTestCase {
    func testTimerAdvancesThroughSegmentsAndUsers() {
        var playback = KitoStoryPlayback(segmentCounts: [2, 1])
        XCTAssertEqual(playback.tick(2.5, duration: 5), .none)
        XCTAssertEqual(playback.progress, 0.5, accuracy: 0.0001)
        XCTAssertEqual(playback.tick(2.5, duration: 5), .advancedSegment)
        XCTAssertEqual(playback.segment, 1)
        XCTAssertEqual(playback.tick(5, duration: 5), .advancedUser)
        XCTAssertEqual(playback.user, 1)
        XCTAssertEqual(playback.segment, 0)
        XCTAssertEqual(playback.tick(5, duration: 5), .finished)
        XCTAssertTrue(playback.isFinished)
        XCTAssertEqual(playback.next(), .none)
    }

    func testBackGoesToPreviousSegmentThenUserThenRestarts() {
        var playback = KitoStoryPlayback(segmentCounts: [3, 2], startingUser: 1)
        _ = playback.next()
        XCTAssertEqual(playback.previous(), .wentBackSegment)
        XCTAssertEqual(playback.segment, 0)
        XCTAssertEqual(playback.previous(), .wentBackUser)
        XCTAssertEqual(playback.user, 0)
        XCTAssertEqual(playback.segment, 2)
        _ = playback.previous()
        _ = playback.previous()
        _ = playback.tick(1, duration: 5)
        XCTAssertEqual(playback.previous(), .restartedSegment)
        XCTAssertEqual(playback.progress, 0)
    }

    func testPauseHoldsTheTimer() {
        var playback = KitoStoryPlayback(segmentCounts: [1])
        playback.pause()
        XCTAssertEqual(playback.tick(10, duration: 5), .none)
        XCTAssertEqual(playback.progress, 0)
        playback.resume()
        XCTAssertEqual(playback.tick(1, duration: 5), .none)
        XCTAssertEqual(playback.progress, 0.2, accuracy: 0.0001)
    }

    func testSkipsPeopleWithoutStories() {
        var playback = KitoStoryPlayback(segmentCounts: [0, 1, 0, 2])
        XCTAssertEqual(playback.user, 1)
        XCTAssertEqual(playback.next(), .advancedUser)
        XCTAssertEqual(playback.user, 3)
        XCTAssertEqual(playback.previous(), .wentBackUser)
        XCTAssertEqual(playback.user, 1)
        XCTAssertFalse(playback.hasPreviousUser)
        XCTAssertTrue(playback.hasNextUser)
    }

    func testEmptyPlaybackIsFinished() {
        let playback = KitoStoryPlayback(segmentCounts: [0, 0])
        XCTAssertTrue(playback.isFinished)
        XCTAssertTrue(KitoStoryPlayback(segmentCounts: []).isFinished)
    }

    func testJumpAndFill() {
        var playback = KitoStoryPlayback(segmentCounts: [3, 2, 1])
        _ = playback.next()
        _ = playback.tick(2.5, duration: 5)
        XCTAssertEqual(playback.fill(forSegment: 0), 1)
        XCTAssertEqual(playback.fill(forSegment: 1), 0.5, accuracy: 0.0001)
        XCTAssertEqual(playback.fill(forSegment: 2), 0)
        XCTAssertEqual(playback.jump(toUser: 2), .advancedUser)
        XCTAssertEqual(playback.segment, 0)
        XCTAssertEqual(playback.jump(toUser: 0), .wentBackUser)
        XCTAssertEqual(playback.jump(toUser: 0), .none)
        XCTAssertEqual(playback.jump(toUser: 9), .none)
    }
}

final class KitoSwipeDecisionTests: XCTestCase {
    private let size = CGSize(width: 300, height: 450)
    private let decision = KitoSwipeDecision()

    func testShortSlowDragSpringsBack() {
        XCTAssertNil(decision.direction(translation: CGSize(width: 40, height: 0), velocity: .zero, in: size))
    }

    func testLongDragPastThresholdSwipes() {
        XCTAssertEqual(decision.direction(translation: CGSize(width: 120, height: 10), velocity: .zero, in: size), .right)
        XCTAssertEqual(decision.direction(translation: CGSize(width: -120, height: 10), velocity: .zero, in: size), .left)
    }

    func testFastFlickSwipesEvenWhenShort() {
        XCTAssertEqual(decision.direction(translation: CGSize(width: 30, height: 0), velocity: CGSize(width: 900, height: 0), in: size), .right)
        XCTAssertNil(decision.direction(translation: CGSize(width: 30, height: 0), velocity: CGSize(width: -900, height: 0), in: size))
    }

    func testFlickBackCancelsLongDrag() {
        XCTAssertNil(decision.direction(translation: CGSize(width: 140, height: 0), velocity: CGSize(width: -1200, height: 0), in: size))
    }

    func testUpwardThrowIsSuperLikeOnlyWhenAllowed() {
        let up = CGSize(width: 10, height: -200)
        XCTAssertEqual(decision.direction(translation: up, velocity: .zero, in: size), .up)
        let noUp = KitoSwipeDecision(allowsUp: false)
        XCTAssertNil(noUp.direction(translation: up, velocity: .zero, in: size))
    }

    func testProgressAndRotation() {
        let halfway = decision.progress(translation: CGSize(width: 48, height: 0), in: size)
        XCTAssertEqual(halfway.right, 0.5, accuracy: 0.001)
        XCTAssertEqual(halfway.left, 0)
        XCTAssertEqual(halfway.dominant?.direction, .right)
        XCTAssertNil(decision.progress(translation: .zero, in: size).dominant)
        XCTAssertEqual(decision.progress(translation: CGSize(width: -500, height: 0), in: size).left, 1)
        XCTAssertGreaterThan(KitoSwipeDecision.rotation(for: CGSize(width: 100, height: 0), width: 300), 0)
        XCTAssertLessThan(KitoSwipeDecision.rotation(for: CGSize(width: -100, height: 0), width: 300), 0)
        XCTAssertEqual(KitoSwipeDecision.rotation(for: CGSize(width: 100, height: 0), width: 0), 0)
    }

    func testExitOffsetLeavesTheScreen() {
        let right = KitoSwipeDecision.exitOffset(for: .right, translation: .zero, velocity: .zero, in: size)
        XCTAssertGreaterThan(right.width, size.width)
        let up = KitoSwipeDecision.exitOffset(for: .up, translation: .zero, velocity: .zero, in: size)
        XCTAssertLessThan(up.height, -size.height)
    }
}

final class KitoWormMathTests: XCTestCase {
    func testRestsAsASingleDot() {
        XCTAssertEqual(KitoWormMath.span(at: 2), .init(lower: 2, upper: 2))
        let frame = KitoWormMath.frame(at: 2, dotSize: 8, spacing: 8)
        XCTAssertEqual(frame.minX, 32)
        XCTAssertEqual(frame.width, 8)
    }

    func testStretchesAcrossBothPagesHalfway() {
        XCTAssertEqual(KitoWormMath.span(at: 2.5), .init(lower: 2, upper: 3))
        let frame = KitoWormMath.frame(at: 2.5, dotSize: 8, spacing: 8)
        XCTAssertEqual(frame.minX, 32)
        XCTAssertEqual(frame.width, 24)
    }

    func testLeadingEdgeMovesFirst() {
        // Early in a forward move the head has moved, the tail hasn't.
        XCTAssertEqual(KitoWormMath.span(at: 2.25), .init(lower: 2, upper: 2.5))
        // Late in the move the head has arrived and the tail follows.
        XCTAssertEqual(KitoWormMath.span(at: 2.75), .init(lower: 2.5, upper: 3))
    }
}

final class KitoCarouselTransformTests: XCTestCase {
    func testCentredItemIsUntouched() {
        for effect in KitoCarouselEffect.allCases {
            XCTAssertEqual(KitoCarouselTransform(effect: effect, position: 0, pageWidth: 300), .identity, "\(effect)")
        }
    }

    func testNeighboursChangeForEachEffect() {
        for effect in KitoCarouselEffect.allCases where effect != .none {
            XCTAssertNotEqual(KitoCarouselTransform(effect: effect, position: 1, pageWidth: 300), .identity, "\(effect)")
        }
    }

    func testCoverFlowFacesTheCentre() {
        let right = KitoCarouselTransform(effect: .coverFlow, position: 1, pageWidth: 300)
        let left = KitoCarouselTransform(effect: .coverFlow, position: -1, pageWidth: 300)
        XCTAssertEqual(right.rotation3D, -left.rotation3D)
        XCTAssertLessThan(right.offsetX, 0)
    }

    func testStackTucksUpcomingItemsBehind() {
        let next = KitoCarouselTransform(effect: .stack, position: 1, pageWidth: 300)
        XCTAssertEqual(next.offsetX, -278, accuracy: 0.001)
        XCTAssertLessThan(next.scale, 1)
    }

    func testPositionAndParallax() {
        let frame = CGRect(x: 400, y: 0, width: 300, height: 200)
        XCTAssertEqual(kitoCarouselPosition(frame: frame, viewportWidth: 400, pageWidth: 350), 1, accuracy: 0.001)
        XCTAssertEqual(kitoCarouselPosition(frame: frame, viewportWidth: 400, pageWidth: 0), 0)
        XCTAssertEqual(kitoParallaxOffset(frame: frame, viewportWidth: 400, overflow: 30), -30)
    }

    func testElementLookup() {
        let items = [10, 20, 30]
        XCTAssertEqual(items.kitoElement(at: 1), 20)
        XCTAssertNil(items.kitoElement(at: 3))
        XCTAssertNil(items.kitoElement(at: -1))
    }
}
