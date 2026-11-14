import Foundation

public enum Hand: String, Codable, Sendable {
    case left
    case right
}

/// The four scored parts of a drill.
public enum Part: String, CaseIterable, Codable, Sendable {
    case rhythm
    case switching
    case low
    case eyesUp

    /// The summary-screen tip when this part is the weakest.
    public var tip: String {
        switch self {
        case .rhythm: return "Keep an even beat, like a drum."
        case .switching: return "Cross it over every bounce."
        case .low: return "Stay low, below your waist."
        case .eyesUp: return "Look up, not at the ball."
        }
    }

    public var title: String {
        switch self {
        case .rhythm: return "Rhythm"
        case .switching: return "Switching"
        case .low: return "Low"
        case .eyesUp: return "Eyes up"
        }
    }
}

/// Part scores from 0 to 100. A nil part had too little data and is left out of the total.
public struct PartScores: Equatable, Sendable {
    public var rhythm: Double?
    public var switching: Double?
    public var low: Double?
    public var eyesUp: Double?

    public init(rhythm: Double? = nil, switching: Double? = nil, low: Double? = nil, eyesUp: Double? = nil) {
        self.rhythm = rhythm
        self.switching = switching
        self.low = low
        self.eyesUp = eyesUp
    }

    public subscript(part: Part) -> Double? {
        switch part {
        case .rhythm: return rhythm
        case .switching: return switching
        case .low: return low
        case .eyesUp: return eyesUp
        }
    }
}

public struct ScoreResult: Equatable, Sendable {
    /// 0 to 100, or nil when there was too little data.
    public let total: Int?
    public let stars: Int
    public let tooLittleData: Bool
    /// The lowest-scoring part that was measured, for the tip.
    public let weakest: Part?
}

public enum Scoring {
    /// Weighted total per the v1 spec: missing parts hand their weight to the others,
    /// lost balls take points off, and the result is kept between 0 and 100.
    public static func score(parts: PartScores, bounceCount: Int, lostBalls: Int,
                             config: DribbleConfig = DribbleConfig()) -> ScoreResult {
        let tooLittle = ScoreResult(total: nil, stars: 0, tooLittleData: true, weakest: nil)
        guard bounceCount >= config.minBouncesForScore else { return tooLittle }

        var weighted = 0.0
        var weightSum = 0.0
        var weakest: (part: Part, value: Double)?
        for part in Part.allCases {
            guard let value = parts[part] else { continue }
            let weight = config.weights[part]
            weighted += weight * value
            weightSum += weight
            if weakest == nil || value < weakest!.value {
                weakest = (part, value)
            }
        }
        guard weightSum > 0 else { return tooLittle }

        let penalty = min(Double(lostBalls) * config.lostBallPenalty, config.lostBallPenaltyMax)
        let raw = (weighted / weightSum - penalty).rounded()
        let total = Int(min(max(raw, 0), 100))
        return ScoreResult(total: total, stars: stars(for: total, config: config),
                           tooLittleData: false, weakest: weakest?.part)
    }

    public static func stars(for total: Int, config: DribbleConfig = DribbleConfig()) -> Int {
        if total >= config.threeStars { return 3 }
        if total >= config.twoStars { return 2 }
        if total >= config.oneStar { return 1 }
        return 0
    }

    /// 100 at a spread of 0, falling in a straight line to 0 at `zeroSpread`.
    public static func rhythmScore(spread: Double, zeroSpread: Double) -> Double {
        guard zeroSpread > 0 else { return 0 }
        return 100 * min(max(1 - spread / zeroSpread, 0), 1)
    }

    /// Credit for one bounce from its height ratio (0 at the knee, 1 at the hip):
    /// 1 at 0.5 or below, 0.6 at 1.0, 0 at 1.4 or above, straight lines between.
    public static func lowCredit(heightRatio r: Double) -> Double {
        if r <= 0.5 { return 1 }
        if r <= 1.0 { return 1 - 0.4 * (r - 0.5) / 0.5 }
        if r < 1.4 { return 0.6 - 0.6 * (r - 1.0) / 0.4 }
        return 0
    }

    /// Low part score: the average credit times 100, or nil with no bounces.
    public static func lowScore(heightRatios: [Double]) -> Double? {
        guard !heightRatios.isEmpty else { return nil }
        return 100 * heightRatios.map(lowCredit(heightRatio:)).reduce(0, +) / Double(heightRatios.count)
    }

    /// Eyes-up part score from the share of frames with the head up:
    /// 100 at 0.9 or more, 0 at 0.2 or less, a straight line between.
    public static func eyesUpScore(fraction f: Double) -> Double {
        if f >= 0.9 { return 100 }
        if f <= 0.2 { return 0 }
        return 100 * (f - 0.2) / 0.7
    }

    /// Crossover switching: the share of back-to-back bounces with known hands where the hand changed.
    /// Nil with fewer than `minKnownHandPairs` such pairs.
    public static func switchingScore(hands: [Hand?], config: DribbleConfig = DribbleConfig()) -> Double? {
        guard hands.count >= 2 else { return nil }
        var pairs = 0
        var changes = 0
        for i in 1..<hands.count {
            if let a = hands[i - 1], let b = hands[i] {
                pairs += 1
                if a != b { changes += 1 }
            }
        }
        guard pairs >= config.minKnownHandPairs else { return nil }
        return 100 * Double(changes) / Double(pairs)
    }
}
