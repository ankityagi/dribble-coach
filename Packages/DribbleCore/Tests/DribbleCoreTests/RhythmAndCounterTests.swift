import XCTest
@testable import DribbleCore

final class RhythmTests: XCTestCase {
    func testSteadyBeatScoresFull() {
        let times = stride(from: 0.0, to: 10, by: 0.4).map { $0 }
        let stats = Rhythm.stats(times: times, start: 0, end: 10)

        XCTAssertEqual(stats.count, 25)
        XCTAssertEqual(stats.spread ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(stats.rhythmScore ?? -1, 100, accuracy: 1e-9)
        XCTAssertEqual(stats.bouncesPerSecond, 2.5, accuracy: 1e-9)
        XCTAssertEqual(stats.lostBalls, 0)
    }

    func testUnevenBeatLosesPoints() {
        // Gaps alternate 0.3 and 0.5: mean 0.4, spread 0.25.
        var times: [Double] = [0]
        for i in 0..<10 { times.append(times.last! + (i.isMultiple(of: 2) ? 0.3 : 0.5)) }
        let stats = Rhythm.stats(times: times, start: 0, end: 5)

        XCTAssertEqual(stats.spread ?? -1, 0.25, accuracy: 1e-9)
        XCTAssertEqual(stats.rhythmScore ?? -1, 100 * (1 - 0.25 / 0.35), accuracy: 1e-6)
    }

    func testLostBallGapIsCountedAndLeftOut() {
        let times: [Double] = [0, 0.4, 0.8, 1.2, 3.2, 3.6, 4.0, 4.4]
        let stats = Rhythm.stats(times: times, start: 0, end: 5)

        XCTAssertEqual(stats.lostBalls, 1)
        XCTAssertEqual(stats.spread ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(stats.activeSeconds, 3, accuracy: 1e-9)
    }

    func testTooFewGapsHasNoRhythm() {
        let stats = Rhythm.stats(times: [0, 0.4, 0.8], start: 0, end: 1)
        XCTAssertNil(stats.spread)
        XCTAssertNil(stats.rhythmScore)
    }
}

final class BounceCounterTests: XCTestCase {
    private func onset(_ t: Double, voice: Bool = false) -> Onset {
        Onset(time: t, lowEnergy: 0.01, voiceRatio: voice ? 5 : 0.01, isLikelyVoice: voice)
    }

    func testCountsOnlyInsideTheDrill() {
        let counter = BounceCounter()
        counter.begin(at: 100, duration: 30)

        XCTAssertFalse(counter.ingest(onset(99.9)))
        XCTAssertTrue(counter.ingest(onset(100.5)))
        XCTAssertFalse(counter.ingest(onset(130.1)))
        XCTAssertEqual(counter.bounceTimes, [100.5])
    }

    func testRejectsVoiceAndCoachSpeech() {
        let counter = BounceCounter()
        counter.begin(at: 0, duration: 30)

        XCTAssertFalse(counter.ingest(onset(1, voice: true)))
        counter.setSpeaking(true, at: 2)
        XCTAssertFalse(counter.ingest(onset(2.5)))
        counter.setSpeaking(false, at: 3)
        XCTAssertFalse(counter.ingest(onset(3.1)))   // inside the 150 ms guard
        XCTAssertTrue(counter.ingest(onset(3.2)))

        XCTAssertEqual(counter.rejectedVoice, 1)
        XCTAssertEqual(counter.rejectedSpeech, 2)
    }

    func testLiveWindowLooksBackFiveSeconds() {
        let counter = BounceCounter()
        counter.begin(at: 0, duration: 30)
        stride(from: 0.5, through: 9.5, by: 0.5).forEach { counter.ingest(onset($0)) }

        let live = counter.liveStats(now: 10)
        XCTAssertEqual(live.count, 10)
        XCTAssertEqual(live.bouncesPerSecond, 2, accuracy: 1e-9)
        XCTAssertEqual(counter.secondsSinceLastBounce(now: 10), 0.5, accuracy: 1e-9)
    }
}
