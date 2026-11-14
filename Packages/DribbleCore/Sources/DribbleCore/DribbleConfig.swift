import Foundation

/// Every tunable number from the v1 spec, in one place.
/// The app loads `DribbleConfig.json` from its bundle and overlays it on these defaults,
/// so a partial JSON file only needs the keys you want to change.
public struct DribbleConfig: Codable, Equatable, Sendable {
    public struct Weights: Codable, Equatable, Sendable {
        public var rhythm: Double = 0.35
        public var switching: Double = 0.25
        public var low: Double = 0.25
        public var eyesUp: Double = 0.15

        public init() {}

        public subscript(part: Part) -> Double {
            switch part {
            case .rhythm: return rhythm
            case .switching: return switching
            case .low: return low
            case .eyesUp: return eyesUp
            }
        }
    }

    /// Bump when defaults change, so saved sessions record which tuning produced them.
    public var version: Int = 1

    // Drill
    public var drillSeconds: Double = 30
    public var tenSecondCallAt: Double = 20

    // Sound: bounce onsets
    public var hopSeconds: Double = 0.005
    public var lowBandMinHz: Double = 60
    public var lowBandMaxHz: Double = 500
    public var highBandMinHz: Double = 1000
    public var medianWindowSeconds: Double = 1.0
    /// History needed before the rolling median is trusted; until then only the floor applies.
    public var medianWarmupSeconds: Double = 0.1
    public var thresholdFactor: Double = 5
    /// Mean-square energy of the low band (samples in -1...1) below which nothing counts.
    public var absoluteFloor: Double = 1e-5
    public var refractorySeconds: Double = 0.12
    /// High-band energy divided by low-band energy above which an onset is tagged likely voice.
    public var voiceRatio: Double = 1.0
    /// Onsets are ignored while the coach speaks and for this long after.
    public var speechGuardSeconds: Double = 0.15

    // Rhythm and score
    public var lostBallGapSeconds: Double = 1.5
    public var rhythmZeroSpread: Double = 0.35
    public var liveWindowSeconds: Double = 5
    public var minBouncesForScore: Int = 10
    public var minKnownHandPairs: Int = 5
    public var lostBallPenalty: Double = 3
    public var lostBallPenaltyMax: Double = 15
    public var threeStars: Int = 85
    public var twoStars: Int = 65
    public var oneStar: Int = 40
    public var weights = Weights()

    public init() {}

    /// Defaults with any keys from `overrides` (a JSON object) laid on top. Nested objects merge key by key.
    public static func merged(_ defaults: DribbleConfig = DribbleConfig(), overrides data: Data) throws -> DribbleConfig {
        let baseData = try JSONEncoder().encode(defaults)
        guard let base = try JSONSerialization.jsonObject(with: baseData) as? [String: Any] else {
            return defaults
        }
        let over = (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        let mergedObject = deepMerge(base, over)
        let mergedData = try JSONSerialization.data(withJSONObject: mergedObject)
        return try JSONDecoder().decode(DribbleConfig.self, from: mergedData)
    }

    /// Defaults overlaid with the file at `url`, or plain defaults if the file is missing or unreadable.
    public static func load(overridesAt url: URL?) -> DribbleConfig {
        guard let url, let data = try? Data(contentsOf: url) else { return DribbleConfig() }
        return (try? merged(overrides: data)) ?? DribbleConfig()
    }

    private static func deepMerge(_ base: [String: Any], _ over: [String: Any]) -> [String: Any] {
        var result = base
        for (key, value) in over {
            if let baseChild = base[key] as? [String: Any], let overChild = value as? [String: Any] {
                result[key] = deepMerge(baseChild, overChild)
            } else {
                result[key] = value
            }
        }
        return result
    }
}
