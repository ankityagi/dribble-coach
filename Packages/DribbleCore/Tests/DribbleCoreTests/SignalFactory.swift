import Foundation

/// Builds made-up microphone signals with known events for the detector tests.
struct SignalFactory {
    let sampleRate: Double
    private(set) var samples: [Float]
    private var rng: UInt64 = 0x9E3779B97F4A7C15

    init(seconds: Double, sampleRate: Double = 48_000, noiseAmplitude: Float = 0.001) {
        self.sampleRate = sampleRate
        samples = Array(repeating: 0, count: Int(seconds * sampleRate))
        for i in samples.indices {
            samples[i] = noiseAmplitude * nextNoise()
        }
    }

    /// A ball thump: a 150 Hz tone with a 4 ms attack and a 25 ms decay.
    mutating func addThump(at time: Double, amplitude: Double = 0.3) {
        let length = Int(0.08 * sampleRate)
        let first = Int(time * sampleRate)
        for i in 0..<length where first + i < samples.count {
            let t = Double(i) / sampleRate
            let envelope = min(1, t / 0.004) * exp(-t / 0.025)
            samples[first + i] += Float(amplitude * envelope * sin(2 * .pi * 150 * t))
        }
    }

    /// A shout-like burst: a 300 Hz tone with strong 1.5 kHz and 2.5 kHz partials.
    mutating func addVoice(at time: Double, duration: Double = 0.2) {
        let length = Int(duration * sampleRate)
        let first = Int(time * sampleRate)
        for i in 0..<length where first + i < samples.count {
            let t = Double(i) / sampleRate
            let envelope = min(1, t / 0.01)
            let value = 0.05 * sin(2 * .pi * 300 * t)
                + 0.15 * sin(2 * .pi * 1500 * t)
                + 0.15 * sin(2 * .pi * 2500 * t)
            samples[first + i] += Float(envelope * value)
        }
    }

    /// Splits the signal into buffers the way the microphone tap delivers them.
    func buffers(size: Int = 512, startTime: Double = 0) -> [(samples: [Float], startTime: Double)] {
        stride(from: 0, to: samples.count, by: size).map { offset in
            let chunk = Array(samples[offset..<min(offset + size, samples.count)])
            return (chunk, startTime + Double(offset) / sampleRate)
        }
    }

    private mutating func nextNoise() -> Float {
        rng = rng &* 6364136223846793005 &+ 1442695040888963407
        let unit = Double(rng >> 11) / Double(1 << 53)
        return Float(unit * 2 - 1)
    }
}
