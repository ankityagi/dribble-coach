import XCTest
@testable import DribbleCore

final class OneEuroFilterTests: XCTestCase {
    func testFirstValuePassesThroughAndConstantStaysPut() {
        var filter = OneEuroFilter(minCutoff: 1, beta: 0)
        XCTAssertEqual(filter.filter(3, at: 0), 3)
        for i in 1...60 {
            XCTAssertEqual(filter.filter(3, at: Double(i) / 60), 3, accuracy: 1e-12)
        }
    }

    func testCutsJitterOnAStillJoint() {
        var filter = OneEuroFilter(minCutoff: 1.7, beta: 3)
        var outputs: [Double] = []
        for i in 0..<240 {
            let jitter = i % 2 == 0 ? 0.01 : -0.01
            outputs.append(filter.filter(0.5 + jitter, at: Double(i) / 60))
        }
        let settled = outputs.suffix(120)
        let spread = settled.max()! - settled.min()!
        XCTAssertLessThan(spread, 0.004, "raw jitter is 0.02 peak to peak")
    }

    func testFastMoveLagsLessWithBeta() {
        // A wrist moving down at 3 image heights a second.
        func lag(beta: Double) -> Double {
            var filter = OneEuroFilter(minCutoff: 1.7, beta: beta)
            var last = 0.0
            for i in 0..<30 {
                let t = Double(i) / 60
                last = filter.filter(1 - 3 * t, at: t)
            }
            return abs(last - (1 - 3 * 29.0 / 60))
        }
        XCTAssertLessThan(lag(beta: 3), lag(beta: 0) / 3)
    }

    func testResetAndRepeatedTime() {
        var filter = OneEuroFilter(minCutoff: 1, beta: 0)
        _ = filter.filter(0, at: 0)
        let next = filter.filter(1, at: 0.1)
        XCTAssertEqual(filter.filter(5, at: 0.1), next, "same time again keeps the last output")
        filter.reset()
        XCTAssertEqual(filter.filter(7, at: 0.2), 7)
    }
}

final class BodyTrackerTests: XCTestCase {
    func testDropsLowConfidenceJoints() {
        var body = PoseFactory.standing()
        body[.leftWrist]?.confidence = 0.2
        let pose = BodyTracker().update(PoseFactory.frame(0, body))
        XCTAssertNil(pose?[.leftWrist])
        XCTAssertNotNil(pose?[.rightWrist])
    }

    func testPerJointConfidenceOverride() throws {
        let config = try DribbleConfig.merged(overrides: Data(#"{"pose": {"jointMinConfidence": {"leftWrist": 0.1}}}"#.utf8))
        var body = PoseFactory.standing()
        body[.leftWrist]?.confidence = 0.2
        let pose = BodyTracker(config: config).update(PoseFactory.frame(0, body))
        XCTAssertNotNil(pose?[.leftWrist])
    }

    func testPointsAndTorsoAreInImageHeightUnits() throws {
        let pose = try XCTUnwrap(BodyTracker().update(PoseFactory.frame(0, PoseFactory.standing(height: 0.6))))
        XCTAssertEqual(try XCTUnwrap(pose.torsoLength), 0.3 * 0.6, accuracy: 1e-9)
        // Shoulders sit 0.2 body heights apart across, whatever the frame's aspect.
        let width = try XCTUnwrap(pose[.rightShoulder]).x - XCTUnwrap(pose[.leftShoulder]).x
        XCTAssertEqual(width, 0.2 * 0.6, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(pose.frameFraction(.root)).x, 0.5, accuracy: 1e-9)
        XCTAssertEqual(pose.looksUprightAndMirrored, true)
        XCTAssertEqual(try XCTUnwrap(pose.inTorsos(0.36)), 2, accuracy: 1e-9)
    }

    func testPicksTheLargestBodyThenFollowsIt() throws {
        let tracker = BodyTracker()
        let kid = PoseFactory.standing(centerX: 0.5, height: 0.6)
        let small = PoseFactory.standing(centerX: 0.15, height: 0.3)
        let first = try XCTUnwrap(tracker.update(PoseFactory.frame(0, small, kid)))
        XCTAssertEqual(try XCTUnwrap(first.frameFraction(.root)).x, 0.5, accuracy: 0.01)

        // Someone bigger walks into view on the right; the tracker stays on the kid.
        let big = PoseFactory.standing(centerX: 0.85, footY: 0.02, height: 0.9)
        for i in 1...30 {
            let pose = try XCTUnwrap(tracker.update(PoseFactory.frame(Double(i) / 60, big, kid)))
            XCTAssertEqual(try XCTUnwrap(pose.frameFraction(.root)).x, 0.5, accuracy: 0.01)
        }
        XCTAssertEqual(tracker.subjectChanges, 1)
    }

    func testDoesNotJumpToSomeoneElseUntilThePlayerIsLost() throws {
        let tracker = BodyTracker()
        _ = tracker.update(PoseFactory.frame(0, PoseFactory.standing(centerX: 0.5)))
        let other = PoseFactory.standing(centerX: 0.9)
        XCTAssertNil(tracker.update(PoseFactory.frame(0.1, other)), "the player left; someone else is not them")
        XCTAssertNil(tracker.update(PoseFactory.frame(0.4, other)))
        let later = try XCTUnwrap(tracker.update(PoseFactory.frame(0.7, other)))
        XCTAssertEqual(try XCTUnwrap(later.frameFraction(.root)).x, 0.9, accuracy: 0.01)
        XCTAssertEqual(tracker.subjectChanges, 2)
    }

    func testFollowsAPlayerWalkingAcross() throws {
        let tracker = BodyTracker()
        var last: BodyPose?
        for i in 0...120 {
            let x = 0.3 + 0.4 * Double(i) / 120
            last = tracker.update(PoseFactory.frame(Double(i) / 60, PoseFactory.standing(centerX: x)))
            XCTAssertNotNil(last)
        }
        XCTAssertEqual(try XCTUnwrap(last?.frameFraction(.root)).x, 0.7, accuracy: 0.02)
        XCTAssertEqual(tracker.subjectChanges, 1)
    }

    func testEmptyFrameGivesNothing() {
        XCTAssertNil(BodyTracker().update(PoseFactory.frame(0)))
    }
}

final class FrameRateGovernorTests: XCTestCase {
    private func run(_ governor: FrameRateGovernor, seconds: Double, fps: Double, processing: Double,
                     from start: Double = 0) -> [Int] {
        var changes: [Int] = []
        let frames = Int(seconds * fps)
        for i in 0..<frames {
            if let rate = governor.record(frameTime: start + Double(i) / fps, processingSeconds: processing) {
                changes.append(rate)
            }
        }
        return changes
    }

    func testFastPhoneStaysAt60() {
        let governor = FrameRateGovernor()
        XCTAssertEqual(run(governor, seconds: 10, fps: 60, processing: 0.011), [])
        XCTAssertEqual(governor.targetFrameRate, 60)
        XCTAssertEqual(governor.measuredFrameRate, 60, accuracy: 0.5)
    }

    func testSlowPhoneFallsBackOnceAfterTheWindow() {
        let governor = FrameRateGovernor()
        XCTAssertEqual(run(governor, seconds: 1.5, fps: 40, processing: 0.022), [], "too early to judge")
        XCTAssertEqual(run(governor, seconds: 5, fps: 40, processing: 0.022, from: 1.5), [30])
        XCTAssertEqual(governor.targetFrameRate, 30)
        XCTAssertEqual(run(governor, seconds: 5, fps: 30, processing: 0.03, from: 6.5), [], "never drops twice")
    }

    func testShortSpikeDoesNotTrigger() {
        let governor = FrameRateGovernor()
        _ = run(governor, seconds: 3, fps: 60, processing: 0.010)
        XCTAssertEqual(run(governor, seconds: 0.3, fps: 60, processing: 0.030, from: 3), [])
        XCTAssertEqual(run(governor, seconds: 3, fps: 60, processing: 0.010, from: 3.3), [])
    }

    func testResetStartsOver() {
        let governor = FrameRateGovernor()
        _ = run(governor, seconds: 4, fps: 40, processing: 0.03)
        governor.reset(to: 60)
        XCTAssertEqual(governor.targetFrameRate, 60)
        XCTAssertNil(governor.averageProcessingSeconds)
    }
}

final class PoseFrameCodingTests: XCTestCase {
    func testRoundTripsWithJointNamesAsKeys() throws {
        let frame = PoseFactory.frame(12.5, PoseFactory.standing())
        let data = try JSONEncoder().encode(frame)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("\"leftWrist\""), text)
        XCTAssertEqual(try JSONDecoder().decode(PoseFrame.self, from: data), frame)
    }
}
