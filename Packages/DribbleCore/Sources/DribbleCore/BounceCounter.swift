import Foundation

/// Turns sound onsets into accepted bounces for one drill.
///
/// M1 has no body tracking yet, so the accept rule is the spec's Home rule without the wrist match:
/// accept every onset that isn't likely voice, inside the drill window, and not while the coach speaks.
/// M3 adds the wrist match and the Gym rule.
public final class BounceCounter {
    private let config: DribbleConfig
    private var start: Double = .infinity
    private var end: Double = .infinity
    private var speaking = false
    private var mutedUntil = -Double.infinity

    public private(set) var bounceTimes: [Double] = []
    public private(set) var rejectedVoice = 0
    public private(set) var rejectedSpeech = 0
    public private(set) var rejectedEcho = 0
    public private(set) var rejectedSlow = 0
    /// Sounds heard fine but dropped because no wrist push backed them up.
    public private(set) var rejectedUnconfirmed = 0
    /// True when sounds only count after `confirm`, because the camera must back them up.
    public private(set) var requiresConfirmation = false
    /// Sounds the microphone accepted that are still waiting for the camera's decision.
    public private(set) var awaitingConfirmation: [Double] = []
    /// Recent onsets of any verdict, for the echo rule.
    private var recent: [(time: Double, energy: Double)] = []
    /// Every onset heard inside the drill window and what was done with it, for Debug mode.
    public private(set) var onsetLog: [OnsetRecord] = []

    public init(config: DribbleConfig = DribbleConfig()) {
        self.config = config
    }

    /// Starts a fresh drill at host time `start`, lasting `duration` seconds.
    /// With `requireConfirmation`, an accepted sound waits in `awaitingConfirmation` until `confirm` or `dismiss`.
    public func begin(at start: Double, duration: Double, requireConfirmation: Bool = false) {
        requiresConfirmation = requireConfirmation
        awaitingConfirmation = []
        rejectedUnconfirmed = 0
        self.start = start
        end = start + duration
        bounceTimes = []
        rejectedVoice = 0
        rejectedSpeech = 0
        rejectedEcho = 0
        rejectedSlow = 0
        recent = []
        onsetLog = []
    }

    /// Call when the coach starts or stops speaking, with the host time.
    public func setSpeaking(_ isSpeaking: Bool, at time: Double) {
        speaking = isSpeaking
        if !isSpeaking {
            mutedUntil = time + config.speechGuardSeconds
        }
    }

    /// Returns true when the onset was counted as a bounce.
    @discardableResult
    public func ingest(_ onset: Onset) -> Bool {
        guard onset.time >= start, onset.time <= end else { return false }
        func note(_ verdict: OnsetVerdict) {
            onsetLog.append(OnsetRecord(time: onset.time - start, verdict: verdict,
                                        lowEnergy: onset.lowEnergy, voiceRatio: onset.voiceRatio,
                                        riseRatio: onset.riseRatio,
                                        margin: onset.threshold > 0 ? onset.lowEnergy / onset.threshold : 0))
        }
        // The loudest sound just before this one, whatever was decided about it.
        recent.removeAll { onset.time - $0.time > config.echoWindowSeconds }
        let louderBefore = recent.map(\.energy).max() ?? 0
        recent.append((onset.time, onset.lowEnergy))

        if speaking || onset.time < mutedUntil {
            rejectedSpeech += 1
            note(.speech)
            return false
        }
        if config.minRiseRatio > 0, onset.riseRatio > 0, onset.riseRatio < config.minRiseRatio {
            rejectedSlow += 1
            note(.slowRise)
            return false
        }
        if onset.isLikelyVoice {
            rejectedVoice += 1
            note(.voice)
            return false
        }
        if louderBefore > onset.lowEnergy * config.echoEnergyRatio {
            rejectedEcho += 1
            note(.echo)
            return false
        }
        note(.accepted)
        if requiresConfirmation {
            awaitingConfirmation.append(onset.time)
        } else {
            bounceTimes.append(onset.time)
        }
        return true
    }

    /// Stats over the last `liveWindowSeconds` before `now`, for the live screen and the coach.
    public func liveStats(now: Double) -> RhythmStats {
        let windowStart = max(start, now - config.liveWindowSeconds)
        return Rhythm.stats(times: bounceTimes, start: windowStart, end: now, config: config)
    }

    /// Stats for the whole drill so far, or the full drill once it has ended.
    public func drillStats(now: Double) -> RhythmStats {
        Rhythm.stats(times: bounceTimes, start: start, end: min(now, end), config: config)
    }

    /// The camera backed this sound up: it becomes a bounce. Returns false if it wasn't waiting.
    @discardableResult
    public func confirm(_ time: Double) -> Bool {
        guard let index = awaitingConfirmation.firstIndex(of: time) else { return false }
        awaitingConfirmation.remove(at: index)
        bounceTimes.append(time)
        bounceTimes.sort()
        return true
    }

    /// The camera did not back this sound up: it is not a bounce. Returns false if it wasn't waiting.
    @discardableResult
    public func dismiss(_ time: Double) -> Bool {
        guard let index = awaitingConfirmation.firstIndex(of: time) else { return false }
        awaitingConfirmation.remove(at: index)
        rejectedUnconfirmed += 1
        let relative = time - start
        if let i = onsetLog.lastIndex(where: { abs($0.time - relative) < 1e-9 }) {
            let old = onsetLog[i]
            onsetLog[i] = OnsetRecord(time: old.time, verdict: .unconfirmed, lowEnergy: old.lowEnergy,
                                      voiceRatio: old.voiceRatio, riseRatio: old.riseRatio, margin: old.margin)
        }
        return true
    }

    /// Time the current drill window started, on the host clock.
    public var windowStart: Double { start }

    /// Seconds since the last accepted bounce, or since the drill started if none yet.
    public func secondsSinceLastBounce(now: Double) -> Double {
        now - (bounceTimes.last ?? start)
    }
}
