import Foundation

/// The One Euro filter (Casiez, Roussel and Vogel, 2012): a low-pass whose cutoff rises with speed,
/// so a still joint stops jittering while a fast wrist stays sharp.
public struct OneEuroFilter: Sendable {
    public var minCutoff: Double
    public var beta: Double
    public var derivativeCutoff: Double

    private var lastTime: Double?
    private var lastValue = 0.0
    private var lastDerivative = 0.0

    public init(minCutoff: Double, beta: Double, derivativeCutoff: Double = 1.0) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.derivativeCutoff = derivativeCutoff
    }

    /// The filtered value for `value` measured at `time` (seconds).
    public mutating func filter(_ value: Double, at time: Double) -> Double {
        guard let previous = lastTime, time > previous else {
            if lastTime == nil {
                lastTime = time
                lastValue = value
                lastDerivative = 0
            }
            // A repeated or out-of-order time can't give a speed; keep the last output.
            return lastValue
        }
        let dt = time - previous
        let derivative = (value - lastValue) / dt
        lastDerivative += Self.alpha(cutoff: derivativeCutoff, dt: dt) * (derivative - lastDerivative)
        let cutoff = minCutoff + beta * abs(lastDerivative)
        lastValue += Self.alpha(cutoff: cutoff, dt: dt) * (value - lastValue)
        lastTime = time
        return lastValue
    }

    /// Forgets the history, so the next value passes straight through.
    public mutating func reset() {
        lastTime = nil
        lastDerivative = 0
    }

    static func alpha(cutoff: Double, dt: Double) -> Double {
        guard cutoff > 0 else { return 0 }
        let tau = 1 / (2 * Double.pi * cutoff)
        return 1 / (1 + tau / dt)
    }
}

/// A One Euro filter on each axis of a point.
public struct PointFilter: Sendable {
    private var x: OneEuroFilter
    private var y: OneEuroFilter

    public init(minCutoff: Double, beta: Double, derivativeCutoff: Double = 1.0) {
        x = OneEuroFilter(minCutoff: minCutoff, beta: beta, derivativeCutoff: derivativeCutoff)
        y = OneEuroFilter(minCutoff: minCutoff, beta: beta, derivativeCutoff: derivativeCutoff)
    }

    public mutating func filter(_ point: Point2, at time: Double) -> Point2 {
        Point2(x: x.filter(point.x, at: time), y: y.filter(point.y, at: time))
    }

    public mutating func reset() {
        x.reset()
        y.reset()
    }
}
