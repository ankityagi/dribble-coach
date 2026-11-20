import XCTest
@testable import DribbleCore

final class BounceDiagnosticsTests: XCTestCase {
    func testGapsAreRelativeAndFlagLostBalls() {
        let gaps = BounceDiagnostics.gaps(times: [10.0, 10.4, 10.8, 13.0, 13.4], start: 10)
        XCTAssertEqual(gaps.count, 4)
        XCTAssertEqual(gaps[0].time, 0.4, accuracy: 1e-9)
        XCTAssertEqual(gaps[2].seconds, 2.2, accuracy: 1e-9)
        XCTAssertEqual(gaps.map(\.isLost), [false, false, true, false])
    }

    func testReportFindsDoubledAndMissedBounces() {
        // Median 0.4 s. One 0.1 s gap is a doubled thump; one 0.8 s gap is a missed bounce.
        let times = [0.0, 0.4, 0.8, 0.9, 1.3, 2.1, 2.5, 2.9]
        let report = BounceDiagnostics.report(gaps: BounceDiagnostics.gaps(times: times, start: 0))
        XCTAssertEqual(report.median ?? 0, 0.4, accuracy: 1e-9)
        XCTAssertEqual(report.tooShort, 1)
        XCTAssertEqual(report.tooLong, 1)
    }

    func testReportWithNoNormalGaps() {
        let report = BounceDiagnostics.report(gaps: BounceDiagnostics.gaps(times: [0, 5], start: 0))
        XCTAssertNil(report.median)
    }

    func testCounterLogsEveryVerdict() {
        let counter = BounceCounter()
        counter.begin(at: 100, duration: 30)
        counter.ingest(Onset(time: 101, lowEnergy: 1e-3, voiceRatio: 0.2, isLikelyVoice: false))
        counter.ingest(Onset(time: 102, lowEnergy: 1e-3, voiceRatio: 3, isLikelyVoice: true))
        counter.setSpeaking(true, at: 102.5)
        counter.ingest(Onset(time: 103, lowEnergy: 1e-3, voiceRatio: 0.2, isLikelyVoice: false))
        XCTAssertEqual(counter.onsetLog.map(\.verdict), [.accepted, .voice, .speech])
        XCTAssertEqual(counter.onsetLog[0].time, 1, accuracy: 1e-9)
    }

    func testQuietSoundSoonAfterLoudOneIsAnEcho() {
        let counter = BounceCounter()
        counter.begin(at: 0, duration: 30)
        counter.ingest(Onset(time: 1.0, lowEnergy: 1e-3, voiceRatio: 0.2, isLikelyVoice: false))
        counter.ingest(Onset(time: 1.21, lowEnergy: 4e-5, voiceRatio: 0.0, isLikelyVoice: false))
        counter.ingest(Onset(time: 1.6, lowEnergy: 8e-4, voiceRatio: 0.2, isLikelyVoice: false))
        XCTAssertEqual(counter.onsetLog.map(\.verdict), [.accepted, .echo, .accepted])
        XCTAssertEqual(counter.bounceTimes, [1.0, 1.6])
        XCTAssertEqual(counter.rejectedEcho, 1)
    }

    func testEchoRuleUsesVoiceRejectedSoundsAndKeepsComparableBounces() {
        let counter = BounceCounter()
        counter.begin(at: 0, duration: 30)
        // Loud thump tagged voice, then its quiet echo: the echo is still dropped.
        counter.ingest(Onset(time: 1.0, lowEnergy: 6e-4, voiceRatio: 3, isLikelyVoice: true))
        counter.ingest(Onset(time: 1.2, lowEnergy: 3e-5, voiceRatio: 0.1, isLikelyVoice: false))
        // A real bounce only 2x quieter, and one past the window, both count.
        counter.ingest(Onset(time: 1.45, lowEnergy: 4e-4, voiceRatio: 0.3, isLikelyVoice: false))
        counter.ingest(Onset(time: 2.0, lowEnergy: 2e-4, voiceRatio: 0.3, isLikelyVoice: false))
        XCTAssertEqual(counter.onsetLog.map(\.verdict), [.voice, .echo, .accepted, .accepted])
    }

    func testSlowRisingSoundIsIgnoredOnlyWhenTheCheckIsOn() {
        var config = DribbleConfig()
        config.minRiseRatio = 8
        let counter = BounceCounter(config: config)
        counter.begin(at: 0, duration: 30)
        counter.ingest(Onset(time: 1.0, lowEnergy: 4.2e-5, voiceRatio: 0.1, isLikelyVoice: false, riseRatio: 1.3, threshold: 4e-5))
        counter.ingest(Onset(time: 2.0, lowEnergy: 6e-4, voiceRatio: 0.1, isLikelyVoice: false, riseRatio: 90, threshold: 4e-5))
        XCTAssertEqual(counter.onsetLog.map(\.verdict), [.slowRise, .accepted])

        let off = BounceCounter()
        off.begin(at: 0, duration: 30)
        off.ingest(Onset(time: 1.0, lowEnergy: 4.2e-5, voiceRatio: 0.1, isLikelyVoice: false, riseRatio: 1.3, threshold: 4e-5))
        XCTAssertEqual(off.onsetLog.map(\.verdict), [.accepted])
    }

    func testDetectorReportsASharpRiseForAThumpAndASmallOneForAGradualBuildUp() {
        let rate = 48_000.0
        func run(_ build: (Int) -> Float) -> Onset? {
            let detector = OnsetDetector(sampleRate: rate)
            var samples = [Float](repeating: 0, count: Int(rate * 0.5))
            for i in 0..<Int(rate * 0.3) {
                samples[Int(rate * 0.2) + i] = build(i)
            }
            return detector.process(samples, startTime: 0).first
        }
        let thump = run { i in Float(0.6 * exp(-Double(i) / 800) * sin(2 * .pi * 150 * Double(i) / rate)) }
        let swell = run { i in Float(min(1, Double(i) / 6000) * 0.05 * sin(2 * .pi * 150 * Double(i) / rate)) }
        XCTAssertNotNil(thump)
        XCTAssertNotNil(swell)
        XCTAssertGreaterThan(thump?.riseRatio ?? 0, (swell?.riseRatio ?? 0) * 5)
    }
}
