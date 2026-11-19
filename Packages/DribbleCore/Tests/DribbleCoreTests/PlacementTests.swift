import XCTest
@testable import DribbleCore

final class PlacementEvaluateTests: XCTestCase {
    private let checker = PlacementChecker()

    func testGoodSpotPassesEverything() {
        let result = checker.evaluate(PoseFactory.pose())
        XCTAssertTrue(result.checks.allPassed, "\(result)")
        XCTAssertNil(result.fix)
        XCTAssertEqual(result.bodyHeightFraction ?? 0, 0.65, accuracy: 1e-9)
    }

    func testNobodyMeansStepIn() {
        XCTAssertEqual(checker.evaluate(nil).fix, .stepIn)
        XCTAssertFalse(checker.evaluate(nil).checks.bodyVisible)
    }

    func testTooBigMeansStepBack() {
        XCTAssertEqual(checker.evaluate(PoseFactory.pose(footY: 0.05, height: 0.88)).fix, .stepBack)
    }

    func testHeadAtTheTopEdgeMeansStepBack() {
        XCTAssertEqual(checker.evaluate(PoseFactory.pose(footY: 0.2, height: 0.79)).fix, .stepBack)
    }

    func testOnlyTheUpperBodyMeansStepBack() {
        let pose = PoseFactory.pose(footY: -0.4, height: 1.2,
                                    dropping: [.root, .leftHip, .rightHip, .leftKnee, .rightKnee,
                                               .leftAnkle, .rightAnkle, .leftWrist, .rightWrist])
        XCTAssertEqual(checker.evaluate(pose).fix, .stepBack)
    }

    func testTooSmallMeansComeCloser() {
        let result = checker.evaluate(PoseFactory.pose(footY: 0.3, height: 0.35))
        XCTAssertEqual(result.fix, .comeCloser)
        XCTAssertFalse(result.checks.rightDistance)
    }

    func testOffToTheirRightMeansMoveLeft() {
        // Mirrored view: x above the middle is the player's right.
        let result = checker.evaluate(PoseFactory.pose(centerX: 0.75))
        XCTAssertEqual(result.fix, .moveLeft)
        XCTAssertFalse(result.checks.centered)
        XCTAssertGreaterThan(result.centerOffset ?? 0, 0)
    }

    func testOffToTheirLeftMeansMoveRight() {
        XCTAssertEqual(checker.evaluate(PoseFactory.pose(centerX: 0.25)).fix, .moveRight)
    }

    func testSlightlyOffCenterIsFine() {
        XCTAssertNil(checker.evaluate(PoseFactory.pose(centerX: 0.6)).fix)
    }

    func testMissingFeetIsLast() {
        let pose = PoseFactory.pose(dropping: [.leftAnkle, .rightAnkle])
        let result = checker.evaluate(pose)
        XCTAssertEqual(result.fix, .showFeet)
        XCTAssertTrue(result.checks.rightDistance, "distance falls back to torso length")
        XCTAssertFalse(result.checks.feetVisible)
    }

    func testDistanceComesBeforeCentering() {
        XCTAssertEqual(checker.evaluate(PoseFactory.pose(centerX: 0.8, footY: 0.3, height: 0.35)).fix, .comeCloser)
    }

    func testPhrasesFollowTheSpec() {
        XCTAssertEqual(PlacementFix.stepBack.phrase, "Step back")
        XCTAssertEqual(PlacementFix.comeCloser.phrase, "Come closer")
        XCTAssertEqual(PlacementFix.moveLeft.phrase, "Move left")
        XCTAssertEqual(PlacementFix.moveRight.phrase, "Move right")
        XCTAssertEqual(PlacementFix.showFeet.phrase, "I can't see your feet")
    }
}

final class PlacementTimingTests: XCTestCase {
    private let good = PoseFactory.pose()
    private let far = PoseFactory.pose(footY: 0.3, height: 0.35)

    func testSettlesAfterHoldingForASecond() {
        let checker = PlacementChecker()
        XCTAssertFalse(checker.update(pose: good, time: 0).settled)
        XCTAssertFalse(checker.update(pose: good, time: 0.9).settled)
        XCTAssertTrue(checker.update(pose: good, time: 1.0).settled)
    }

    func testABriefDropoutDoesNotRestartTheHold() {
        let checker = PlacementChecker()
        _ = checker.update(pose: good, time: 0)
        _ = checker.update(pose: nil, time: 0.5)
        _ = checker.update(pose: nil, time: 0.6)
        XCTAssertTrue(checker.update(pose: good, time: 1.0).settled)
    }

    func testALongerFailureRestartsTheHold() {
        let checker = PlacementChecker()
        _ = checker.update(pose: good, time: 0)
        _ = checker.update(pose: far, time: 0.5)
        _ = checker.update(pose: far, time: 0.8)
        XCTAssertFalse(checker.update(pose: good, time: 1.0).settled)
        XCTAssertFalse(checker.update(pose: good, time: 1.9).settled)
        XCTAssertTrue(checker.update(pose: good, time: 2.0).settled)
    }

    func testSpeaksAFixOnceItSettlesThenSpacesThemOut() {
        let checker = PlacementChecker()
        var spoken: [(Double, PlacementFix)] = []
        // Far for 8 seconds at 30 fps.
        for i in 0..<240 {
            let t = Double(i) / 30
            if let fix = checker.update(pose: far, time: t).speak { spoken.append((t, fix)) }
        }
        XCTAssertEqual(spoken.map(\.1), [.comeCloser, .comeCloser])
        XCTAssertEqual(spoken[0].0, 0.6, accuracy: 0.04)
        XCTAssertEqual(spoken[1].0, 6.6, accuracy: 0.04, "the same fix waits for the repeat gap")
    }

    func testANewFixWaitsForTheGapNotTheRepeat() {
        let checker = PlacementChecker()
        var spoken: [(Double, PlacementFix)] = []
        let right = PoseFactory.pose(centerX: 0.8)
        for i in 0..<180 {
            let t = Double(i) / 30
            let pose = t < 1 ? far : right
            if let fix = checker.update(pose: pose, time: t).speak { spoken.append((t, fix)) }
        }
        XCTAssertEqual(spoken.map(\.1), [.comeCloser, .moveLeft])
        XCTAssertEqual(spoken[1].0, 3.6, accuracy: 0.04)
    }

    func testNothingIsSpokenWhenPlaced() {
        let checker = PlacementChecker()
        for i in 0..<90 {
            XCTAssertNil(checker.update(pose: good, time: Double(i) / 30).speak)
        }
    }
}
