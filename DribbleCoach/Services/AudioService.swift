import AVFoundation
import DribbleCore

enum HostClock {
    /// Seconds on the host clock, the one clock every event in the app is timed on.
    static func now() -> Double {
        AVAudioTime.seconds(forHostTime: mach_absolute_time())
    }
}

enum AudioServiceError: LocalizedError {
    case permissionDenied
    case noInput

    var errorDescription: String? {
        switch self {
        case .permissionDenied: return "Dribble Coach needs the microphone to hear the ball. Turn it on in Settings."
        case .noInput: return "No microphone input is available right now."
        }
    }
}

/// Microphone in, bounce onsets out.
///
/// M1 uses the spec's plain measurement mode and ignores sound while the coach speaks.
/// M4 compares this with echo cancellation on and keeps whichever scores better on real clips.
final class AudioService {
    private let engine = AVAudioEngine()
    private let analysisQueue = DispatchQueue(label: "dribblecoach.audio.analysis", qos: .userInteractive)
    private var detector: OnsetDetector?
    private(set) var isRunning = false

    /// Called on the analysis queue for every onset.
    var onOnset: ((Onset) -> Void)?
    /// Called on the analysis queue with each buffer's peak level, 0 to 1.
    var onLevel: ((Float) -> Void)?

    static func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    func start(config: DribbleConfig) throws {
        guard !isRunning else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
        try? session.setPreferredSampleRate(48_000)
        try? session.setPreferredIOBufferDuration(0.005)
        try session.setActive(true)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw AudioServiceError.noInput }

        let detector = OnsetDetector(sampleRate: format.sampleRate, config: config)
        self.detector = detector
        let inputLatency = session.inputLatency
        let sampleRate = format.sampleRate

        input.installTap(onBus: 0, bufferSize: 512, format: format) { [weak self] buffer, when in
            guard let self, let channel = buffer.floatChannelData?[0] else { return }
            let count = Int(buffer.frameLength)
            let samples = Array(UnsafeBufferPointer(start: channel, count: count))
            // Time of the buffer's first sample as it reached the microphone.
            let startTime: Double
            if when.isHostTimeValid {
                startTime = AVAudioTime.seconds(forHostTime: when.hostTime) - inputLatency
            } else {
                startTime = HostClock.now() - Double(count) / sampleRate - inputLatency
            }
            self.analysisQueue.async {
                let onsets = detector.process(samples, startTime: startTime)
                var peak: Float = 0
                for sample in samples { peak = max(peak, abs(sample)) }
                self.onLevel?(peak)
                for onset in onsets { self.onOnset?(onset) }
            }
        }

        engine.prepare()
        try engine.start()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
