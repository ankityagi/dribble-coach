import XCTest
@testable import DribbleCore

final class ScoringTests: XCTestCase {
    func testTooFewBouncesGivesNoScore() {
        let result = Scoring.score(parts: PartScores(rhythm: 90), bounceCount: 9, lostBalls: 0)
        XCTAssertTrue(result.tooLittleData)
        XCTAssertNil(result.total)
    }

    func testMissingPartsShareTheirWeight() {
        let result = Scoring.score(parts: PartScores(rhythm: 80), bounceCount: 40, lostBalls: 0)
        XCTAssertEqual(result.total, 80)
        XCTAssertEqual(result.stars, 2)
        XCTAssertEqual(result.weakest, .rhythm)
    }

    func testFullWeightedTotal() {
        let parts = PartScores(rhythm: 100, switching: 80, low: 60, eyesUp: 40)
        // 35 + 20 + 15 + 6 = 76
        let result = Scoring.score(parts: parts, bounceCount: 50, lostBalls: 0)
        XCTAssertEqual(result.total, 76)
        XCTAssertEqual(result.weakest, .eyesUp)
    }

    func testLostBallPenaltyIsCapped() {
        let parts = PartScores(rhythm: 50)
        XCTAssertEqual(Scoring.score(parts: parts, bounceCount: 40, lostBalls: 2).total, 44)
        XCTAssertEqual(Scoring.score(parts: parts, bounceCount: 40, lostBalls: 9).total, 35)
        XCTAssertEqual(Scoring.score(parts: PartScores(rhythm: 5), bounceCount: 40, lostBalls: 9).total, 0)
    }

    func testStars() {
        XCTAssertEqual(Scoring.stars(for: 85), 3)
        XCTAssertEqual(Scoring.stars(for: 84), 2)
        XCTAssertEqual(Scoring.stars(for: 40), 1)
        XCTAssertEqual(Scoring.stars(for: 39), 0)
    }

    func testLowCredit() {
        XCTAssertEqual(Scoring.lowCredit(heightRatio: 0.2), 1)
        XCTAssertEqual(Scoring.lowCredit(heightRatio: 0.75), 0.8, accuracy: 1e-9)
        XCTAssertEqual(Scoring.lowCredit(heightRatio: 1.0), 0.6, accuracy: 1e-9)
        XCTAssertEqual(Scoring.lowCredit(heightRatio: 1.2), 0.3, accuracy: 1e-9)
        XCTAssertEqual(Scoring.lowCredit(heightRatio: 1.5), 0)
        XCTAssertNil(Scoring.lowScore(heightRatios: []))
    }

    func testEyesUp() {
        XCTAssertEqual(Scoring.eyesUpScore(fraction: 0.95), 100)
        XCTAssertEqual(Scoring.eyesUpScore(fraction: 0.55), 50, accuracy: 1e-9)
        XCTAssertEqual(Scoring.eyesUpScore(fraction: 0.1), 0)
    }

    func testSwitching() {
        let alternating: [Hand?] = [.left, .right, .left, .right, .left, .right]
        XCTAssertEqual(Scoring.switchingScore(hands: alternating) ?? -1, 100, accuracy: 1e-9)

        let mixed: [Hand?] = [.left, .left, .right, nil, .right, .left, .right, .right]
        // Known pairs: L-L, L-R, R-L, L-R, R-R = 5 pairs, 3 changes.
        XCTAssertEqual(Scoring.switchingScore(hands: mixed) ?? -1, 60, accuracy: 1e-9)

        XCTAssertNil(Scoring.switchingScore(hands: [.left, .right, nil, .left]))
    }
}

final class StreakTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }()

    private func date(_ day: Int, hour: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }

    func testCountsBackFromToday() {
        let dates = [date(14), date(13, hour: 22), date(12), date(10)]
        XCTAssertEqual(Streak.days(sessionDates: dates, today: date(14, hour: 18), calendar: calendar), 3)
    }

    func testStillAliveBeforeTodaysDrill() {
        let dates = [date(13), date(12)]
        XCTAssertEqual(Streak.days(sessionDates: dates, today: date(14), calendar: calendar), 2)
    }

    func testBrokenStreak() {
        XCTAssertEqual(Streak.days(sessionDates: [date(11)], today: date(14), calendar: calendar), 0)
        XCTAssertEqual(Streak.days(sessionDates: [], today: date(14), calendar: calendar), 0)
    }
}

final class ConfigTests: XCTestCase {
    func testPartialOverridesKeepOtherDefaults() throws {
        let json = #"{"thresholdFactor": 7, "weights": {"rhythm": 0.5}}"#
        let config = try DribbleConfig.merged(overrides: Data(json.utf8))

        XCTAssertEqual(config.thresholdFactor, 7)
        XCTAssertEqual(config.weights.rhythm, 0.5)
        XCTAssertEqual(config.weights.low, 0.25)
        XCTAssertEqual(config.drillSeconds, 30)
    }

    func testMissingFileGivesDefaults() {
        XCTAssertEqual(DribbleConfig.load(overridesAt: nil), DribbleConfig())
    }
}
