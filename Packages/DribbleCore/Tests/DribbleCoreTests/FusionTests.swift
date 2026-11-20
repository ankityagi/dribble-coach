import XCTest
@testable import DribbleCore

final class FusionTests: XCTestCase {
    private let torso = 0.2
    private let dt = 1.0 / 60

    private func pose(time: Double, left: Double?, right: Double?) -> BodyPose {
        var joints: [Joint: Point2] = [:]
        if let left { joints[.leftWrist] = Point2(x: 0.2, y: left) }
        if let right { joints[.rightWrist] = Point2(x: 0.3, y: right) }
        return BodyPose(time: time, aspect: 0.5625, joints: joints, torsoLength: torso)
    }

    private func onset(_ time: Double) -> Onset {
        Onset(time: time, lowEnergy: 1e-3, voiceRatio: 0.2, isLikelyVoice: false)
    }

    /// Frames from `from` to `to`; each wrist's height comes from the closure.
    private func feed(_ engine: FusionEngine, from: Double, to: Double,
                      left: (Double) -> Double?, right: (Double) -> Double?) -> [FusedOnset] {
        var out: [FusedOnset] = []
        var t = from
        while t <= to {
            out += engine.addPose(pose(time: t, left: left(t), right: right(t)), time: t)
            t += dt
        }
        return out
    }

    func testRightWristPushConfirmsTheSoundAndNamesTheHand() {
        let engine = FusionEngine()
        engine.addOnset(onset(1.0))
        // Right wrist drops 0.2 (one torso) in 0.1 s, ending at 0.9 s: 10 torso lengths per second.
        let out = feed(engine, from: 0.5, to: 1.05,
                       left: { _ in 0.5 },
                       right: { t in t < 0.8 ? 0.6 : t < 0.9 ? 0.6 - 2.0 * (t - 0.8) : 0.4 })
        XCTAssertEqual(out.count, 1)
        XCTAssertTrue(out[0].confirmed)
        XCTAssertEqual(out[0].hand, .right)
        XCTAssertGreaterThan(out[0].pushSpeed ?? 0, 5)
    }

    func testSoundWithNoWristMotionIsNotConfirmed() {
        let engine = FusionEngine()
        engine.addOnset(onset(1.0))
        let out = feed(engine, from: 0.5, to: 1.05, left: { _ in 0.5 }, right: { _ in 0.5 })
        XCTAssertEqual(out.count, 1)
        XCTAssertFalse(out[0].confirmed)
        XCTAssertNil(out[0].hand)
        XCTAssertTrue(out[0].bodyVisible)
    }

    func testBothWristsMovingSimilarlyLeavesTheHandUnknown() {
        let engine = FusionEngine()
        engine.addOnset(onset(1.0))
        let drop: (Double) -> Double = { t in t < 0.8 ? 0.6 : t < 0.9 ? 0.6 - 2.0 * (t - 0.8) : 0.4 }
        let out = feed(engine, from: 0.5, to: 1.05, left: drop, right: drop)
        XCTAssertTrue(out[0].confirmed)
        XCTAssertNil(out[0].hand)
    }

    func testWristMovingDownAfterTheSoundIsIgnored() {
        let engine = FusionEngine()
        engine.addOnset(onset(1.0))
        let out = feed(engine, from: 0.5, to: 1.3, left: { _ in 0.5 },
                       right: { t in t < 1.05 ? 0.6 : 0.6 - 2.0 * (t - 1.05) })
        XCTAssertFalse(out[0].confirmed)
    }

    func testUpwardWristMotionIsNotAPush() {
        let engine = FusionEngine()
        engine.addOnset(onset(1.0))
        let out = feed(engine, from: 0.5, to: 1.05, left: { _ in 0.5 },
                       right: { t in t < 0.8 ? 0.4 : t < 0.9 ? 0.4 + 2.0 * (t - 0.8) : 0.6 })
        XCTAssertFalse(out[0].confirmed)
    }

    func testSoundIsHeldUntilCameraFramesReachIt() {
        let engine = FusionEngine()
        engine.addOnset(onset(1.0))
        XCTAssertTrue(feed(engine, from: 0.5, to: 0.95, left: { _ in 0.5 }, right: { _ in 0.5 }).isEmpty)
        XCTAssertEqual(feed(engine, from: 0.96, to: 1.02, left: { _ in 0.5 }, right: { _ in 0.5 }).count, 1)
    }

    func testStaleSoundIsDecidedWithoutABody() {
        let engine = FusionEngine()
        engine.addOnset(onset(1.0))
        XCTAssertTrue(engine.resolveStale(now: 1.1).isEmpty)
        let out = engine.resolveStale(now: 1.3)
        XCTAssertEqual(out.count, 1)
        XCTAssertFalse(out[0].confirmed)
        XCTAssertFalse(out[0].bodyVisible)
        XCTAssertNil(out[0].pushSpeed)
    }

    func testNobodyInViewMeansNotConfirmed() {
        let engine = FusionEngine()
        engine.addOnset(onset(1.0))
        var out: [FusedOnset] = []
        var t = 0.5
        while t <= 1.05 { out += engine.addPose(nil, time: t); t += dt }
        XCTAssertEqual(out.count, 1)
        XCTAssertFalse(out[0].confirmed)
        XCTAssertFalse(out[0].bodyVisible)
    }

    /// A wrist drop whose speed is `scale` * 10 torso lengths per second (torso is 0.2): scale 0.09 is about 0.9.
    private func lightPush(scale: Double) -> (Double) -> Double {
        { t in t < 0.8 ? 0.6 : t < 0.9 ? 0.6 - 2.0 * scale * (t - 0.8) : 0.6 - 0.2 * scale }
    }

    private func loudOnset(_ time: Double, energy: Double) -> Onset {
        Onset(time: time, lowEnergy: energy, voiceRatio: 0.2, isLikelyVoice: false)
    }

    func testLoudSoundIsConfirmedByALightWristPush() {
        // About 0.9 torso lengths per second: lighter than minPushSpeed (1.5), above the assist speed (0.5).
        let engine = FusionEngine()
        engine.addOnset(loudOnset(1.0, energy: 5e-4))
        let out = feed(engine, from: 0.5, to: 1.05, left: { _ in 0.5 }, right: lightPush(scale: 0.09))
        XCTAssertEqual(out.count, 1)
        XCTAssertLessThan(out[0].pushSpeed ?? 9, 1.5)
        XCTAssertGreaterThanOrEqual(out[0].pushSpeed ?? 0, 0.5)
        XCTAssertTrue(out[0].confirmed)
        XCTAssertTrue(out[0].confirmedByLoudness)
    }

    func testQuietSoundWithTheSameLightPushIsNotConfirmed() {
        let engine = FusionEngine()
        engine.addOnset(loudOnset(1.0, energy: 6e-5))
        let out = feed(engine, from: 0.5, to: 1.05, left: { _ in 0.5 }, right: lightPush(scale: 0.09))
        XCTAssertFalse(out[0].confirmed)
    }

    func testLoudSoundWithNoWristMotionIsNotConfirmed() {
        let engine = FusionEngine()
        engine.addOnset(loudOnset(1.0, energy: 9e-4))
        let out = feed(engine, from: 0.5, to: 1.05, left: { _ in 0.5 }, right: { _ in 0.5 })
        XCTAssertFalse(out[0].confirmed)
    }

    func testStrongPushIsNotMarkedAsLoudnessConfirmed() {
        let engine = FusionEngine()
        engine.addOnset(loudOnset(1.0, energy: 9e-4))
        let out = feed(engine, from: 0.5, to: 1.05, left: { _ in 0.5 },
                       right: { t in t < 0.8 ? 0.6 : t < 0.9 ? 0.6 - 2.0 * (t - 0.8) : 0.4 })
        XCTAssertTrue(out[0].confirmed)
        XCTAssertFalse(out[0].confirmedByLoudness)
    }
}
