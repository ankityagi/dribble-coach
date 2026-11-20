import XCTest
@testable import DribbleCore

final class ProgressTests: XCTestCase {
    func testTooFewBouncesIsNotADrill() {
        XCTAssertEqual(Progress.evaluate(bounces: 6, previous: [30], minBounces: 10),
                       ProgressResult(stars: 0, comparison: .tooFew))
    }

    func testFirstDrillGetsTwoStars() {
        XCTAssertEqual(Progress.evaluate(bounces: 25, previous: [], minBounces: 10),
                       ProgressResult(stars: 2, comparison: .first))
    }

    func testNewBestGetsThreeStars() {
        XCTAssertEqual(Progress.evaluate(bounces: 46, previous: [38, 42], minBounces: 10),
                       ProgressResult(stars: 3, comparison: .newBest(previousBest: 42)))
    }

    func testBeatingLastTimeButNotTheBestGetsTwoStars() {
        XCTAssertEqual(Progress.evaluate(bounces: 40, previous: [45, 35], minBounces: 10),
                       ProgressResult(stars: 2, comparison: .beatLast(by: 5)))
    }

    func testMatchingLastTime() {
        XCTAssertEqual(Progress.evaluate(bounces: 35, previous: [45, 35], minBounces: 10),
                       ProgressResult(stars: 2, comparison: .matchedLast))
    }

    func testFewerThanLastTimeStillGetsAStar() {
        XCTAssertEqual(Progress.evaluate(bounces: 30, previous: [45, 35], minBounces: 10),
                       ProgressResult(stars: 1, comparison: .belowLast(by: 5, best: 45)))
    }

    func testMatchingTheBestWithoutBeatingItIsNotANewBest() {
        XCTAssertEqual(Progress.evaluate(bounces: 45, previous: [45, 35], minBounces: 10),
                       ProgressResult(stars: 2, comparison: .beatLast(by: 10)))
    }

    func testHandSummaryCountsSwitchesAndSkipsUnknowns() {
        let hands: [Hand?] = [.right, .left, .right, nil, .left, .right, .right]
        let s = Hands.summarize(hands)
        XCTAssertEqual(s.known, 6)
        XCTAssertEqual(s.pairs, 4)     // R-L, L-R, L-R, R-R (the pairs touching nil are skipped)
        XCTAssertEqual(s.switches, 3)
        XCTAssertEqual(s.switchShare(minPairs: 5), nil)
        XCTAssertEqual(s.switchShare(minPairs: 4) ?? 0, 0.75, accuracy: 1e-9)
    }

    func testTargetHandShareForPoundDrills() {
        let hands: [Hand?] = [.right, .right, .right, .left, .right, nil]
        let s = Hands.summarize(hands, target: .right)
        XCTAssertEqual(s.known, 5)
        XCTAssertEqual(s.onTarget, 4)
        XCTAssertEqual(s.targetShare(minKnown: 5) ?? 0, 0.8, accuracy: 1e-9)
        XCTAssertNil(s.targetShare(minKnown: 6))
    }

    func testEmptyHandListIsSafe() {
        let s = Hands.summarize([])
        XCTAssertEqual(s, HandSummary(known: 0, switches: 0, pairs: 0, onTarget: 0))
    }

    func testTipOrder() {
        XCTAssertEqual(Tips.choose(lostBalls: 2, spread: 0.5, switchShare: 0.1, targetShare: nil),
                       "Keep the ball close so it doesn't get away.")
        XCTAssertEqual(Tips.choose(lostBalls: 0, spread: 0.5, switchShare: 0.4, targetShare: nil),
                       "Cross it over every bounce.")
        XCTAssertEqual(Tips.choose(lostBalls: 0, spread: 0.5, switchShare: nil, targetShare: 0.5),
                       "Stick to your target hand.")
        XCTAssertEqual(Tips.choose(lostBalls: 1, spread: 0.45, switchShare: 0.9, targetShare: nil),
                       "Keep an even beat, like a drum.")
        XCTAssertEqual(Tips.choose(lostBalls: 0, spread: 0.3, switchShare: 0.9, targetShare: nil),
                       "Smooth! Try for even more bounces.")
        XCTAssertEqual(Tips.choose(lostBalls: 0, spread: nil, switchShare: nil, targetShare: nil),
                       "Smooth! Try for even more bounces.")
    }
}
