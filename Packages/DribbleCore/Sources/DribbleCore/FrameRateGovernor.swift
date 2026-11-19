import Foundation

/// Watches how long Vision takes per frame and decides when to drop from 60 to 30 fps.
///
/// Per the spec, the drop lasts for the rest of the session. The threshold is in the config;
/// see `DribbleConfig.Pose.fallbackAverageSeconds` for why it's lower than the spec's 25 ms.
/// Not thread-safe: call it from the Vision queue only.
public final class FrameRateGovernor {
    private let config: DribbleConfig.Pose
    private var samples: [(time: Double, seconds: Double)] = []
    private var frameTimes: [Double] = []

    public private(set) var targetFrameRate: Int

    public init(config: DribbleConfig = DribbleConfig(), startAt frameRate: Int? = nil) {
        self.config = config.pose
        targetFrameRate = frameRate ?? config.pose.highFrameRate
    }

    /// Starts a new session at `frameRate`, forgetting any earlier fallback.
    public func reset(to frameRate: Int) {
        targetFrameRate = frameRate
        samples = []
        frameTimes = []
    }

    /// Records one frame: its host time and how long Vision took on it.
    /// Returns the new frame rate when this frame triggered the fallback, otherwise nil.
    @discardableResult
    public func record(frameTime: Double, processingSeconds: Double) -> Int? {
        samples.append((frameTime, processingSeconds))
        frameTimes.append(frameTime)
        let windowStart = frameTime - config.fallbackWindowSeconds
        samples.removeAll { $0.time < windowStart }
        frameTimes.removeAll { $0 < frameTime - 1 }

        guard targetFrameRate > config.lowFrameRate,
              let first = samples.first,
              // A full window of history, allowing for one frame's spacing at the start.
              frameTime - first.time >= config.fallbackWindowSeconds * 0.9,
              let average = averageProcessingSeconds,
              average > config.fallbackAverageSeconds else { return nil }
        targetFrameRate = config.lowFrameRate
        samples = []
        return targetFrameRate
    }

    /// Mean Vision time per frame over the window, or nil with no frames yet.
    public var averageProcessingSeconds: Double? {
        guard !samples.isEmpty else { return nil }
        return samples.map(\.seconds).reduce(0, +) / Double(samples.count)
    }

    /// Frames processed in the last second, for the debug overlay.
    public var measuredFrameRate: Double {
        guard let first = frameTimes.first, let last = frameTimes.last, last > first else { return 0 }
        return Double(frameTimes.count - 1) / (last - first)
    }
}
