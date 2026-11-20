import Foundation

/// A sharp rise in low-band sound energy: a candidate ball bounce.
public struct Onset: Equatable, Sendable {
    /// Host time in seconds of the start of the hop where the energy crossed the threshold.
    public let time: Double
    /// Mean-square energy of the low band in that hop.
    public let lowEnergy: Double
    /// High-band energy divided by low-band energy in that hop.
    public let voiceRatio: Double
    /// True when the hop looks more like a voice than a ball thump.
    public let isLikelyVoice: Bool

    public init(time: Double, lowEnergy: Double, voiceRatio: Double, isLikelyVoice: Bool) {
        self.time = time
        self.lowEnergy = lowEnergy
        self.voiceRatio = voiceRatio
        self.isLikelyVoice = isLikelyVoice
    }
}

/// Finds bounce onsets in a mono sound stream, per the v1 spec:
/// low-band energy per 5 ms hop, a threshold of max(floor, rolling median × k),
/// rising edges only, and a refractory gap.
///
/// Feed it buffers in order with the host time of each buffer's first sample.
/// Not thread-safe: call it from one queue.
public final class OnsetDetector {
    private let config: DribbleConfig
    private let sampleRate: Double
    private let hopSize: Int
    private let medianCapacity: Int
    private let warmupHops: Int

    private var lowA: Biquad
    private var lowB: Biquad
    private var high: Biquad

    private var hopFill = 0
    private var hopStartTime = 0.0
    private var lowSum = 0.0
    private var highSum = 0.0

    private var history: [Double] = []
    private var historyIndex = 0
    private var wasAbove = false
    private var lastOnsetTime = -Double.infinity

    public init(sampleRate: Double, config: DribbleConfig = DribbleConfig()) {
        self.config = config
        self.sampleRate = sampleRate
        hopSize = max(1, Int((sampleRate * config.hopSeconds).rounded()))
        medianCapacity = max(1, Int((config.medianWindowSeconds / config.hopSeconds).rounded()))
        warmupHops = max(0, Int((config.medianWarmupSeconds / config.hopSeconds).rounded()))
        lowA = .highPass(cutoff: config.lowBandMinHz, sampleRate: sampleRate)
        lowB = .lowPass(cutoff: config.lowBandMaxHz, sampleRate: sampleRate)
        high = .highPass(cutoff: config.highBandMinHz, sampleRate: sampleRate)
    }

    /// Processes one buffer and returns any onsets that completed inside it.
    public func process(_ samples: [Float], startTime: Double) -> [Onset] {
        var onsets: [Onset] = []
        for (i, sample) in samples.enumerated() {
            if hopFill == 0 {
                hopStartTime = startTime + Double(i) / sampleRate
            }
            let x = Double(sample)
            let lowY = lowB.process(lowA.process(x))
            let highY = high.process(x)
            lowSum += lowY * lowY
            highSum += highY * highY
            hopFill += 1

            if hopFill == hopSize {
                if let onset = finishHop() {
                    onsets.append(onset)
                }
                hopFill = 0
                lowSum = 0
                highSum = 0
            }
        }
        return onsets
    }

    /// The threshold the next hop must beat. Exposed for the debug overlay and tests.
    public var currentThreshold: Double {
        let median = history.count >= max(1, warmupHops) ? Self.median(history) : 0
        return max(config.absoluteFloor, median * config.thresholdFactor)
    }

    private func finishHop() -> Onset? {
        let lowEnergy = lowSum / Double(hopSize)
        let highEnergy = highSum / Double(hopSize)
        let threshold = currentThreshold
        let isAbove = lowEnergy > threshold
        defer {
            wasAbove = isAbove
            push(lowEnergy)
        }

        guard isAbove, !wasAbove, hopStartTime - lastOnsetTime >= config.refractorySeconds else {
            return nil
        }
        lastOnsetTime = hopStartTime
        let ratio = highEnergy / max(lowEnergy, 1e-12)
        return Onset(time: hopStartTime,
                     lowEnergy: lowEnergy,
                     voiceRatio: ratio,
                     isLikelyVoice: ratio > config.voiceRatio)
    }

    private func push(_ value: Double) {
        if history.count < medianCapacity {
            history.append(value)
        } else {
            history[historyIndex] = value
            historyIndex = (historyIndex + 1) % medianCapacity
        }
    }

    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
}
