import Foundation

/// A second-order IIR filter (RBJ audio cookbook), transposed direct form II.
struct Biquad {
    private var b0: Double
    private var b1: Double
    private var b2: Double
    private var a1: Double
    private var a2: Double
    private var z1 = 0.0
    private var z2 = 0.0

    private init(b0: Double, b1: Double, b2: Double, a0: Double, a1: Double, a2: Double) {
        self.b0 = b0 / a0
        self.b1 = b1 / a0
        self.b2 = b2 / a0
        self.a1 = a1 / a0
        self.a2 = a2 / a0
    }

    static func lowPass(cutoff: Double, sampleRate: Double, q: Double = 0.7071) -> Biquad {
        let w0 = 2 * Double.pi * cutoff / sampleRate
        let cosW = cos(w0)
        let alpha = sin(w0) / (2 * q)
        return Biquad(b0: (1 - cosW) / 2, b1: 1 - cosW, b2: (1 - cosW) / 2,
                      a0: 1 + alpha, a1: -2 * cosW, a2: 1 - alpha)
    }

    static func highPass(cutoff: Double, sampleRate: Double, q: Double = 0.7071) -> Biquad {
        let w0 = 2 * Double.pi * cutoff / sampleRate
        let cosW = cos(w0)
        let alpha = sin(w0) / (2 * q)
        return Biquad(b0: (1 + cosW) / 2, b1: -(1 + cosW), b2: (1 + cosW) / 2,
                      a0: 1 + alpha, a1: -2 * cosW, a2: 1 - alpha)
    }

    mutating func process(_ x: Double) -> Double {
        let y = b0 * x + z1
        z1 = b1 * x - a1 * y + z2
        z2 = b2 * x - a2 * y
        return y
    }
}
