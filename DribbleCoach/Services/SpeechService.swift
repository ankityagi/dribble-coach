import AVFoundation

/// Speaks the coach's lines and reports when speech starts and stops,
/// so the bounce counter can ignore the speaker's own sound.
final class SpeechService: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()

    var isEnabled = true
    /// Called on the main thread with the host time when speech starts (true) or ends (false).
    var onSpeakingChanged: ((Bool, Double) -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func say(_ text: String) {
        guard isEnabled else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.speak(utterance)
    }

    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        report(true)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        report(false)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        report(false)
    }

    private func report(_ speaking: Bool) {
        let time = HostClock.now()
        DispatchQueue.main.async { [weak self] in
            self?.onSpeakingChanged?(speaking, time)
        }
    }
}
