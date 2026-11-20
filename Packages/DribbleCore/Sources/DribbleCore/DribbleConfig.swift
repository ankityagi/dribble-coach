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

    /// Body tracking: joint confidence, smoothing, subject choice and the frame-rate fallback.
    public struct Pose: Codable, Equatable, Sendable {
        /// A joint below this confidence counts as missing.
        public var minConfidence: Double = 0.3
        /// Per-joint overrides of `minConfidence`, keyed by `Joint` raw value. Wrists may need lower.
        public var jointMinConfidence: [String: Double] = [:]
        /// One Euro filter, in image-height units: the cutoff at rest (Hz), how fast the cutoff
        /// rises with speed, and the cutoff for the speed estimate itself.
        public var smoothingMinCutoff: Double = 1.7
        public var smoothingBeta: Double = 3.0
        public var smoothingDerivativeCutoff: Double = 1.0
        /// A joint missing for longer than this restarts its filter, so it doesn't glide in from an old spot.
        public var jointResetSeconds: Double = 0.3
        /// Cutoff (Hz) of the plain low-pass on torso length, the body scale.
        public var scaleCutoff: Double = 0.5
        /// The subject is followed frame to frame by its root; a root that moved more than this many
        /// torso lengths since the last frame belongs to someone else.
        public var maxRootJumpTorsos: Double = 1.0
        /// With no match for this long, the subject is chosen again as the largest body.
        public var subjectLostSeconds: Double = 0.5
        /// Frame rates tried first and fallen back to.
        public var highFrameRate: Int = 60
        public var lowFrameRate: Int = 30
        /// Fall back when the average Vision time per frame stays above this over the window.
        /// 60 fps leaves about 16.7 ms a frame, so the spec's 25 ms would never trigger in time.
        public var fallbackAverageSeconds: Double = 0.016
        public var fallbackWindowSeconds: Double = 2.0

        public init() {}

        public func minConfidence(for joint: Joint) -> Double {
            jointMinConfidence[joint.rawValue] ?? minConfidence
        }
    }

    /// The placement check before the drill. Fractions are of the camera frame, in the portrait view.
    public struct Placement: Codable, Equatable, Sendable {
        /// Head (highest of nose, eyes, ears) to lowest ankle, as a share of the frame height.
        public var minBodyHeightFraction: Double = 0.45
        public var maxBodyHeightFraction: Double = 0.85
        /// Body height in torso lengths, for judging distance when the ankles can't be seen.
        public var bodyHeightPerTorso: Double = 3.2
        /// A joint closer than this to the top or bottom edge means the kid is too close.
        public var edgeMargin: Double = 0.03
        /// The root may sit this far from the middle, as a share of the frame width.
        public var centerTolerance: Double = 0.15
        /// Every check must hold this long before placement passes.
        public var holdSeconds: Double = 1.0
        /// A failure shorter than this (a dropped frame, a blink of low confidence) doesn't restart the hold.
        public var failureGraceSeconds: Double = 0.2
        /// A fix has to be the current one this long before it's spoken.
        public var fixSettleSeconds: Double = 0.6
        /// At least this long between any two spoken fixes.
        public var fixGapSeconds: Double = 3.0
        /// The same fix is repeated only after this long.
        public var fixRepeatSeconds: Double = 6.0

        public init() {}
    }

    /// Bump when defaults change, so saved sessions record which tuning produced them.
    public var version: Int = 2

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
    /// A sound within this long after a much louder one is the first sound's echo or rattle, not a new bounce.
    public var echoWindowSeconds: Double = 0.3
    /// How many times louder the earlier sound must be for the later one to count as its echo.
    public var echoEnergyRatio: Double = 4
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

    public var pose = Pose()
    public var placement = Placement()

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
