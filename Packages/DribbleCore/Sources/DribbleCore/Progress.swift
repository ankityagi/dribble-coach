import Foundation

/// How a drill compares with the player's own earlier drills of the same kind.
public enum Comparison: Equatable, Sendable {
    /// Too few bounces to count as a drill.
    case tooFew
    /// The first drill of this kind.
    case first
    /// More bounces than ever before.
    case newBest(previousBest: Int)
    /// More than last time, but not a new best.
    case beatLast(by: Int)
    case matchedLast
    case belowLast(by: Int, best: Int)
}

public struct ProgressResult: Equatable, Sendable {
    /// 0 to 3. One for finishing, two for matching or beating last time (or a first drill), three for a new best.
    public let stars: Int
    public let comparison: Comparison
}

public enum Progress {
    /// `previous` holds the bounce counts of earlier drills of the same kind, oldest first.
    public static func evaluate(bounces: Int, previous: [Int], minBounces: Int) -> ProgressResult {
        guard bounces >= minBounces else { return ProgressResult(stars: 0, comparison: .tooFew) }
        guard let last = previous.last, let best = previous.max() else {
            return ProgressResult(stars: 2, comparison: .first)
        }
        if bounces > best {
            return ProgressResult(stars: 3, comparison: .newBest(previousBest: best))
        }
        if bounces > last {
            return ProgressResult(stars: 2, comparison: .beatLast(by: bounces - last))
        }
        if bounces == last {
            return ProgressResult(stars: 2, comparison: .matchedLast)
        }
        return ProgressResult(stars: 1, comparison: .belowLast(by: last - bounces, best: best))
    }
}

/// Which hand did each bounce, in numbers a kid can read.
public struct HandSummary: Equatable, Sendable {
    /// Bounces where the hand was known.
    public let known: Int
    /// Times the hand changed between two back-to-back bounces whose hands were both known.
    public let switches: Int
    /// Back-to-back pairs where both hands were known.
    public let pairs: Int
    /// Known bounces made with the target hand, for the pound drills.
    public let onTarget: Int

    /// Share of back-to-back pairs where the hand changed, or nil with too few pairs to say.
    public func switchShare(minPairs: Int) -> Double? {
        pairs >= minPairs ? Double(switches) / Double(pairs) : nil
    }

    /// Share of known bounces with the target hand, or nil with too few to say.
    public func targetShare(minKnown: Int) -> Double? {
        known >= minKnown ? Double(onTarget) / Double(known) : nil
    }
}

public enum Hands {
    /// Counts switches and target-hand bounces. Where the camera couldn't tell the hand (nil), the pair is skipped,
    /// so switches can be a little low rather than too high.
    public static func summarize(_ hands: [Hand?], target: Hand? = nil) -> HandSummary {
        var pairs = 0
        var switches = 0
        for i in 1..<max(hands.count, 1) {
            if let a = hands[i - 1], let b = hands[i] {
                pairs += 1
                if a != b { switches += 1 }
            }
        }
        let known = hands.compactMap { $0 }
        let onTarget = target.map { t in known.filter { $0 == t }.count } ?? 0
        return HandSummary(known: known.count, switches: switches, pairs: pairs, onTarget: onTarget)
    }
}

public enum Tips {
    /// One short, doable tip for the end of a drill, the first that applies in this order:
    /// lost balls, the drill's own skill (switching or the target hand), an uneven beat, then praise.
    /// Spreads and shares come from real phone data: crossover drills ran at spread 0.2 to 0.32.
    public static func choose(lostBalls: Int, spread: Double?, switchShare: Double?, targetShare: Double?) -> String {
        if lostBalls >= 2 { return "Keep the ball close so it doesn't get away." }
        if let switchShare, switchShare < 0.6 { return "Cross it over every bounce." }
        if let targetShare, targetShare < 0.8 { return "Stick to your target hand." }
        if let spread, spread >= 0.4 { return "Keep an even beat, like a drum." }
        return "Smooth! Try for even more bounces."
    }
}
