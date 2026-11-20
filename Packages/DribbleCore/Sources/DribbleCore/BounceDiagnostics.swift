import Foundation

/// Why the counter did or didn't count an onset. Kept for Debug mode.
public enum OnsetVerdict: String, Codable, Sendable {
    case accepted
    case voice
    case speech
    case echo
    case slowRise
}

/// One sound the detector found during a drill, with what the counter decided.
public struct OnsetRecord: Equatable, Codable, Sendable {
    /// Seconds since the drill started.
    public let time: Double
    public let verdict: OnsetVerdict
    public let lowEnergy: Double
    public let voiceRatio: Double
    /// Energy over the previous 5 ms hop's energy. Large for a sharp bounce, small for speech.
    public let riseRatio: Double
    /// Energy over the detection threshold.
    public let margin: Double

    public init(time: Double, verdict: OnsetVerdict, lowEnergy: Double, voiceRatio: Double,
                riseRatio: Double = 0, margin: Double = 0) {
        self.time = time
        self.verdict = verdict
        self.lowEnergy = lowEnergy
        self.voiceRatio = voiceRatio
        self.riseRatio = riseRatio
        self.margin = margin
    }
}

/// The gap between two counted bounces.
public struct BounceGap: Equatable, Codable, Sendable {
    /// Seconds since the drill started, at the later bounce.
    public let time: Double
    public let seconds: Double
    /// True when the gap is long enough to count as a lost ball and is left out of the rhythm spread.
    public let isLost: Bool
}

/// Summary of the gaps for Debug mode. All gap numbers are in seconds and leave out lost-ball gaps.
public struct GapReport: Equatable, Sendable {
    public let gaps: [BounceGap]
    public let shortest: Double?
    public let median: Double?
    public let longest: Double?
    /// Gaps under half the median, which usually mean one thump was counted twice.
    public let tooShort: Int
    /// Gaps over 1.6 times the median that aren't lost balls, which usually mean a bounce was missed.
    public let tooLong: Int
}

public enum BounceDiagnostics {
    /// Gaps between the sorted bounce times, with times made relative to `start`.
    public static func gaps(times: [Double], start: Double, config: DribbleConfig = DribbleConfig()) -> [BounceGap] {
        let sorted = times.sorted()
        guard sorted.count >= 2 else { return [] }
        return (1..<sorted.count).map { i in
            let seconds = sorted[i] - sorted[i - 1]
            return BounceGap(time: sorted[i] - start, seconds: seconds, isLost: seconds > config.lostBallGapSeconds)
        }
    }

    public static func report(gaps: [BounceGap]) -> GapReport {
        let normal = gaps.filter { !$0.isLost }.map(\.seconds).sorted()
        guard !normal.isEmpty else {
            return GapReport(gaps: gaps, shortest: nil, median: nil, longest: nil, tooShort: 0, tooLong: 0)
        }
        let mid = normal.count / 2
        let median = normal.count % 2 == 1 ? normal[mid] : (normal[mid - 1] + normal[mid]) / 2
        return GapReport(gaps: gaps, shortest: normal.first, median: median, longest: normal.last,
                         tooShort: normal.filter { $0 < median * 0.5 }.count,
                         tooLong: normal.filter { $0 > median * 1.6 }.count)
    }
}
