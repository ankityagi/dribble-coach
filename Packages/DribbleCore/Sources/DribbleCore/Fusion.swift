import Foundation

/// A sound, checked against the wrists: did a hand push down just before it?
public struct FusedOnset: Equatable, Sendable {
    public let onset: Onset
    /// Fastest downward wrist speed in the window before the sound, in torso lengths per second.
    /// Nil when that wrist was never seen in the window.
    public let leftPush: Double?
    public let rightPush: Double?
    /// The wrist that pushed harder, when it beat the other by `handRatio`.
    public let hand: Hand?
    /// The winning wrist's speed, nil when neither wrist was seen.
    public let pushSpeed: Double?
    /// True when a body was in view around the sound.
    public let bodyVisible: Bool
    /// True when the camera backs the sound up: a wrist pushed down at least `minPushSpeed`, or the sound was
    /// loud and a wrist pushed at least `assistPushSpeed`.
    public let confirmed: Bool
    /// True when only the loud-sound rule confirmed it (the push alone was too light).
    public let confirmedByLoudness: Bool
}

/// One wrist reading for the debug log. Positions are in image-height units, y up.
public struct WristSample: Equatable, Codable, Sendable {
    /// Seconds since the log started.
    public let t: Double
    public let leftY: Double?
    public let rightY: Double?
    public let torso: Double?

    public init(t: Double, leftY: Double?, rightY: Double?, torso: Double?) {
        self.t = t
        self.leftY = leftY
        self.rightY = rightY
        self.torso = torso
    }
}

/// Joins sounds and wrist motion on one clock, per the spec's fusion step.
///
/// Feed it every camera frame with `addPose` (a nil pose means nobody was in view) and every sound with
/// `addOnset`. A sound is decided once a camera frame at or after its time arrives, or once
/// `fusionWaitSeconds` have passed (`resolveStale`), so late frames don't make it miss the push.
/// Not thread-safe: use one queue.
public final class FusionEngine {
    private struct Sample {
        let time: Double
        let leftY: Double?
        let rightY: Double?
        let torso: Double?
        let hasBody: Bool
    }

    private let config: DribbleConfig
    private var samples: [Sample] = []
    private var pending: [Onset] = []

    public init(config: DribbleConfig = DribbleConfig()) {
        self.config = config
    }

    public func reset() {
        samples = []
        pending = []
    }

    public func addOnset(_ onset: Onset) {
        pending.append(onset)
    }

    /// Adds one camera frame and returns any sounds it lets us decide.
    @discardableResult
    public func addPose(_ pose: BodyPose?, time: Double) -> [FusedOnset] {
        samples.append(Sample(time: time, leftY: pose?[.leftWrist]?.y, rightY: pose?[.rightWrist]?.y,
                              torso: pose?.torsoLength, hasBody: pose != nil))
        let cutoff = time - 3
        samples.removeAll { $0.time < cutoff }

        let ready = pending.filter { $0.time <= time }
        pending.removeAll { $0.time <= time }
        return ready.map(decide)
    }

    /// Decides sounds that have waited too long for the camera, using what we have. Call it now and then.
    @discardableResult
    public func resolveStale(now: Double) -> [FusedOnset] {
        let stale = pending.filter { now - $0.time > config.fusionWaitSeconds }
        pending.removeAll { now - $0.time > config.fusionWaitSeconds }
        return stale.map(decide)
    }

    private func decide(_ onset: Onset) -> FusedOnset {
        let start = onset.time - config.fusionWindowSeconds
        let window = samples.filter { $0.time >= start - config.pushSpanSeconds && $0.time <= onset.time }
        let left = push(window, start: start) { $0.leftY }
        let right = push(window, start: start) { $0.rightY }

        let l = left ?? 0
        let r = right ?? 0
        var hand: Hand?
        var speed: Double?
        if left != nil || right != nil {
            speed = max(l, r)
            if r > 0, r >= l * config.handRatio { hand = .right }
            else if l > 0, l >= r * config.handRatio { hand = .left }
        }
        let visible = window.contains { $0.hasBody }
        let push = speed ?? 0
        let strong = push >= config.minPushSpeed
        let loud = onset.lowEnergy >= config.loudEnergy && push >= config.assistPushSpeed
        return FusedOnset(onset: onset, leftPush: left, rightPush: right, hand: hand, pushSpeed: speed,
                          bodyVisible: visible, confirmed: strong || loud,
                          confirmedByLoudness: !strong && loud)
    }

    /// The fastest downward speed of one wrist in the window, measured across at least `pushSpanSeconds`.
    private func push(_ window: [Sample], start: Double, y: (Sample) -> Double?) -> Double? {
        let readings = window.compactMap { s -> (time: Double, y: Double, torso: Double)? in
            guard let value = y(s), let torso = s.torso, torso > 0 else { return nil }
            return (s.time, value, torso)
        }
        guard !readings.isEmpty else { return nil }
        var best = 0.0
        for (i, now) in readings.enumerated() where now.time >= start {
            // The latest earlier reading at least one span back.
            guard let before = readings[..<i].last(where: { now.time - $0.time >= config.pushSpanSeconds }) else { continue }
            let speed = (before.y - now.y) / now.torso / (now.time - before.time)
            best = max(best, speed)
        }
        return best
    }
}
