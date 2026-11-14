import AVFoundation
import Foundation
import Observation
import SwiftData
import DribbleCore

/// The drill state machine from the v1 spec, for M1: sound check, countdown, a timed drill
/// counted from bounce sounds, and a summary. Placement and body tracking arrive in M2.
@MainActor
@Observable
final class SessionController {
    enum Phase: Equatable {
        case idle
        case soundCheck
        case countdown(String)
        case running
        case summary
        case endedEarly(String)
    }

    var phase: Phase = .idle
    var drill: Drill = .crossover
    var soundCheckHeard = 0
    var liveCount = 0
    var liveBouncesPerSecond = 0.0
    var liveRhythm: Double?
    var secondsLeft: Double = 30
    /// Goes up by one on every accepted bounce, to flash the beat light.
    var beat = 0
    var micLevel: Float = 0
    var lastResult: DrillResult?
    var lastOnsetInfo = ""
    var rejectedVoice = 0
    var rejectedSpeech = 0

    @ObservationIgnored var modelContext: ModelContext?

    let config: DribbleConfig
    private let audio = AudioService()
    private let speech = SpeechService()
    private let counter: BounceCounter

    @ObservationIgnored private var flowTask: Task<Void, Never>?
    @ObservationIgnored private var drillStartHost = 0.0
    @ObservationIgnored private var drillStartDate = Date()
    @ObservationIgnored private var lastLevelUpdate = 0.0
    @ObservationIgnored private var interruptionObserver: NSObjectProtocol?

    var isInDrillFlow: Bool {
        switch phase {
        case .soundCheck, .countdown, .running: return true
        case .idle, .summary, .endedEarly: return false
        }
    }

    init() {
        let config = DribbleConfig.load(
            overridesAt: Bundle.main.url(forResource: "DribbleConfig", withExtension: "json"))
        self.config = config
        counter = BounceCounter(config: config)
        secondsLeft = config.drillSeconds

        audio.onOnset = { [weak self] onset in
            Task { @MainActor in self?.handle(onset) }
        }
        audio.onLevel = { [weak self] level in
            Task { @MainActor in self?.updateLevel(level) }
        }
        speech.onSpeakingChanged = { [weak self] speaking, time in
            MainActor.assumeIsolated {
                self?.counter.setSpeaking(speaking, at: time)
            }
        }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            let typeValue = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let began = typeValue == AVAudioSession.InterruptionType.began.rawValue
            MainActor.assumeIsolated {
                if began { self?.endEarly("The drill stopped because something else used the sound.") }
            }
        }
    }

    // MARK: - Flow

    func begin(drill: Drill) async {
        self.drill = drill
        lastResult = nil
        speech.isEnabled = UserDefaults.standard.object(forKey: SettingsKey.voiceOn) as? Bool ?? true

        guard await AudioService.requestPermission() else {
            phase = .endedEarly(AudioServiceError.permissionDenied.localizedDescription)
            return
        }
        do {
            try audio.start(config: config)
        } catch {
            phase = .endedEarly(error.localizedDescription)
            return
        }

        soundCheckHeard = 0
        counter.begin(at: HostClock.now(), duration: 3600)
        phase = .soundCheck
        speech.say("Bounce the ball 3 times")
    }

    func startCountdown() {
        flowTask?.cancel()
        flowTask = Task { [weak self] in
            await self?.runCountdownAndDrill()
        }
    }

    func again() {
        lastResult = nil
        startCountdown()
    }

    /// Stops everything and goes back to the app. Used by Stop, Done and dismissing the drill.
    func cancel() {
        flowTask?.cancel()
        flowTask = nil
        speech.stopSpeaking()
        audio.stop()
        phase = .idle
    }

    /// Ends a drill in progress without a score.
    func endEarly(_ reason: String) {
        guard isInDrillFlow else { return }
        flowTask?.cancel()
        flowTask = nil
        speech.stopSpeaking()
        audio.stop()
        phase = .endedEarly(reason)
    }

    private func runCountdownAndDrill() async {
        phase = .countdown("Look at me")
        speech.say("Look at me")
        guard await pause(1.5) else { return }
        for n in [3, 2, 1] {
            phase = .countdown("\(n)")
            speech.say("\(n)")
            guard await pause(1) else { return }
        }
        speech.say("Go!")

        drillStartHost = HostClock.now()
        drillStartDate = Date()
        counter.begin(at: drillStartHost, duration: config.drillSeconds)
        resetLive()
        phase = .running

        var tenCalled = false
        var keepDribblingCalled = false
        while true {
            guard await pause(0.1) else { return }
            let now = HostClock.now()
            let elapsed = now - drillStartHost
            secondsLeft = max(0, config.drillSeconds - elapsed)
            refreshLive(now: now)

            let thermal = ProcessInfo.processInfo.thermalState
            if thermal == .serious || thermal == .critical {
                endEarly("The phone got hot, so the drill stopped. Let it cool down and try again.")
                return
            }
            if !tenCalled, elapsed >= config.tenSecondCallAt {
                tenCalled = true
                speech.say("Ten seconds!")
            }
            if !keepDribblingCalled, elapsed > 3, counter.secondsSinceLastBounce(now: now) > 3 {
                keepDribblingCalled = true
                speech.say("Keep dribbling!")
            }
            if elapsed >= config.drillSeconds { break }
        }
        finish()
    }

    private func finish() {
        let end = drillStartHost + config.drillSeconds
        let stats = counter.drillStats(now: end)
        // M1 measures rhythm only. Switching, low and eyes up arrive with body tracking in M3.
        let parts = PartScores(rhythm: stats.rhythmScore)
        let score = Scoring.score(parts: parts, bounceCount: stats.count,
                                  lostBalls: stats.lostBalls, config: config)
        let result = DrillResult(drill: drill, startedAt: drillStartDate, duration: config.drillSeconds,
                                 stats: stats, parts: parts, score: score)
        lastResult = result
        secondsLeft = 0
        phase = .summary

        if let total = score.total {
            save(result, total: total)
            let starWord = score.stars == 1 ? "star" : "stars"
            speech.say("Stop! \(total)! \(score.stars) \(starWord).")
        } else {
            speech.say("Stop! Let's try that again.")
        }
    }

    // MARK: - Events

    private func handle(_ onset: Onset) {
        lastOnsetInfo = String(format: "energy %.1e, voice ratio %.2f", onset.lowEnergy, onset.voiceRatio)
            + (onset.isLikelyVoice ? " (voice)" : "")
        switch phase {
        case .soundCheck:
            if counter.ingest(onset) {
                soundCheckHeard += 1
                beat += 1
                if soundCheckHeard == 3 { startCountdown() }
            }
        case .running:
            if counter.ingest(onset) {
                beat += 1
                refreshLive(now: HostClock.now())
            }
            rejectedVoice = counter.rejectedVoice
            rejectedSpeech = counter.rejectedSpeech
        default:
            break
        }
    }

    private func updateLevel(_ level: Float) {
        let now = HostClock.now()
        guard now - lastLevelUpdate >= 0.05 else { return }
        lastLevelUpdate = now
        micLevel = level
    }

    private func resetLive() {
        liveCount = 0
        liveBouncesPerSecond = 0
        liveRhythm = nil
        rejectedVoice = 0
        rejectedSpeech = 0
        secondsLeft = config.drillSeconds
    }

    private func refreshLive(now: Double) {
        let live = counter.liveStats(now: now)
        liveCount = counter.bounceTimes.count
        liveBouncesPerSecond = live.bouncesPerSecond
        liveRhythm = live.rhythmScore
    }

    private func pause(_ seconds: Double) async -> Bool {
        try? await Task.sleep(for: .seconds(seconds))
        return !Task.isCancelled
    }

    // MARK: - Saving

    private func save(_ result: DrillResult, total: Int) {
        guard let modelContext else { return }
        let place = Place(rawValue: UserDefaults.standard.string(forKey: SettingsKey.place) ?? "") ?? .home
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let record = SessionRecord(result: result, total: total, place: place, frameRate: 0,
                                   deviceModel: Self.deviceModel(), appVersion: version,
                                   configVersion: config.version)
        modelContext.insert(record)
        try? modelContext.save()
    }

    private static func deviceModel() -> String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}
