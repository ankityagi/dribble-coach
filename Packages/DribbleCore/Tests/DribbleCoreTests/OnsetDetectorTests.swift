import XCTest
@testable import DribbleCore

final class OnsetDetectorTests: XCTestCase {
    private func run(_ signal: SignalFactory, startTime: Double = 0,
                     config: DribbleConfig = DribbleConfig()) -> [Onset] {
        let detector = OnsetDetector(sampleRate: signal.sampleRate, config: config)
        return signal.buffers(startTime: startTime).flatMap { detector.process($0.samples, startTime: $0.startTime) }
    }

    func testFindsEveryThumpOnTime() {
        var signal = SignalFactory(seconds: 4)
        let times = stride(from: 0.5, through: 3.2, by: 0.3).map { $0 }
        times.forEach { signal.addThump(at: $0) }

        let onsets = run(signal)

        XCTAssertEqual(onsets.count, times.count)
        for (onset, truth) in zip(onsets, times) {
            XCTAssertEqual(onset.time, truth, accuracy: 0.015)
            XCTAssertFalse(onset.isLikelyVoice)
        }
    }

    func testTimesFollowTheBufferClock() {
        var signal = SignalFactory(seconds: 2)
        signal.addThump(at: 1.0)

        let onsets = run(signal, startTime: 1000)

        XCTAssertEqual(onsets.count, 1)
        XCTAssertEqual(onsets.first?.time ?? 0, 1001.0, accuracy: 0.015)
    }

    func testRefractoryGapMergesCloseThumps() {
        var signal = SignalFactory(seconds: 2)
        signal.addThump(at: 0.5)
        signal.addThump(at: 0.56)

        XCTAssertEqual(run(signal).count, 1)
    }

    func testFastDribblingStillCounts() {
        var signal = SignalFactory(seconds: 3)
        let times = stride(from: 0.5, through: 2.5, by: 0.2).map { $0 }
        times.forEach { signal.addThump(at: $0) }

        XCTAssertEqual(run(signal).count, times.count)
    }

    func testShoutIsTaggedAsVoice() {
        var signal = SignalFactory(seconds: 2)
        signal.addVoice(at: 1.0)

        let onsets = run(signal)

        XCTAssertFalse(onsets.isEmpty)
        XCTAssertTrue(onsets.allSatisfy(\.isLikelyVoice))
    }

    func testQuietRoomGivesNothing() {
        XCTAssertTrue(run(SignalFactory(seconds: 3)).isEmpty)
    }

    func testQuietThumpBelowFloorIsIgnored() {
        var signal = SignalFactory(seconds: 2)
        signal.addThump(at: 1.0, amplitude: 0.002)

        XCTAssertTrue(run(signal).isEmpty)
    }

    func testMedian() {
        XCTAssertEqual(OnsetDetector.median([3, 1, 2]), 2)
        XCTAssertEqual(OnsetDetector.median([4, 1, 3, 2]), 2.5)
        XCTAssertEqual(OnsetDetector.median([]), 0)
    }
}
