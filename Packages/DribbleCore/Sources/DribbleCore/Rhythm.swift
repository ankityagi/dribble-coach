import Foundation

/// Count, speed and evenness of a run of bounces.
public struct RhythmStats: Equatable, Sendable {
    public let count: Int
    /// Seconds of the window minus the lost-ball gaps.
    public let activeSeconds: Double
    public let bouncesPerSecond: Double
    /// Standard deviation of the gaps between bounces divided by their mean, lost-ball gaps left out.
    /// Nil until there are at least three gaps.
    public let spread: Double?
    /// 0 to 100, or nil when `spread` is nil.
    public let rhythmScore: Double?
    public let lostBalls: Int
}

public enum Rhythm {
    /// Stats for the bounce times (seconds, any order) that fall inside `start...end`.
    public static func stats(times: [Double], start: Double, end: Double,
                             config: DribbleConfig = DribbleConfig()) -> RhythmStats {
        let inWindow = times.filter { $0 >= start && $0 <= end }.sorted()
        var gaps: [Double] = []
        var lostBalls = 0
        var lostSeconds = 0.0
        if inWindow.count >= 2 {
            for i in 1..<inWindow.count {
                let gap = inWindow[i] - inWindow[i - 1]
                if gap > config.lostBallGapSeconds {
                    lostBalls += 1
                    lostSeconds += gap
                } else {
                    gaps.append(gap)
                }
            }
        }

        let active = max(0, (end - start) - lostSeconds)
        let bps = active > 0 ? Double(inWindow.count) / active : 0

        var spread: Double?
        if gaps.count >= 3 {
            let mean = gaps.reduce(0, +) / Double(gaps.count)
            let variance = gaps.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(gaps.count)
            spread = mean > 0 ? variance.squareRoot() / mean : nil
        }
        let score = spread.map { Scoring.rhythmScore(spread: $0, zeroSpread: config.rhythmZeroSpread) }

        return RhythmStats(count: inWindow.count, activeSeconds: active, bouncesPerSecond: bps,
                           spread: spread, rhythmScore: score, lostBalls: lostBalls)
    }
}
