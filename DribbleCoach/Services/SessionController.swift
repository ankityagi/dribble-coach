import AVFoundation
import Foundation
import Observation
import SwiftData
import DribbleCore

/// The drill state machine from the v1 spec, as of M2: placement check (body, then sound),
/// countdown, a timed drill counted from bounce sounds, and a summary.
/// The camera runs from placement to the end; fusion with the bounces arrives in M3.
@MainActor
@Observable
final class SessionController {
    enum Phase: Equatable {
        case idle
        case placement
        case countdown(String)
        case running
        case summary
        case endedEarly(String)
    }

    /// The placement check stands the kid in the right spot first, then asks for three bounces.
    enum PlacementStep: Equatable {
        case body
        case sound
    }

    var phase: Phase = .idle
    var drill: Drill = .crossover
    var placementStep: PlacementStep = .body
    var placementChecks = PlacementChecks()
    var placementFix: PlacementFix?
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
    /// Sounds the microphone accepted, and how many of those no wrist push backed up (so they didn't count).
    var heardCount = 0
    var unconfirmedCount = 0

    // Body tracking, refreshed at most 30 times a second for the screen.
    var pose: BodyPose?
    var poseFrameRate = 0.0
    var poseMilliseconds = 0.0
    var droppedFrames = 0
    var bodyHeightFraction: Double?
    var centerOffset: Double?
    /// The camera's frame rate: 60, or 30 after the fallback or on phones without 60 fps at 1080p.
    var frameRate = 0

    @ObservationIgnored var modelContext: ModelContext?

    let config: DribbleConfig
    /// The camera session, for the preview on screen.
    var captureSession: AVCaptureSession { capture.session }

    private let audio = AudioService()
    private let speech = SpeechService()
    private let capture = CaptureService()
    private let poseService: PoseService
    private let poseLogger = PoseLogger()
    private let counter: BounceCounter
    private let fusion: FusionEngine
    private let placement: PlacementChecker

    @ObservationIgnored private var flowTask: Task<Void, Never>?
    @ObservationIgnored private var fusedLog: [BounceLogger.FusedLogEntry] = []
    @ObservationIgnored private var confirmedByLoudness = 0
    @ObservationIgnored private var drillStartHost = 0.0
    @ObservationIgnored private var drillStartDate = Date()
    @ObservationIgnored private var lastLevelUpdate = 0.0
    @ObservationIgnored private var lastPoseUpdate = 0.0
    @ObservationIgnored private var soundStepFailingSince: Double?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    var isInDrillFlow: Bool {
        switch phase {
        case .placement, .countdown, .running: return true
        case .idle, .summary, .endedEarly: return false
        }
    }

    private var debugMode: Bool { UserDefaults.standard.bool(forKey: SettingsKey.debugMode) }

    init() {
        let config = DribbleConfig.load(
            overridesAt: Bundle.main.url(forResource: "DribbleConfig", withExtension: "json"))
        self.config = config
        counter = BounceCounter(config: config)
        fusion = FusionEngine(config: config)
        placement = PlacementChecker(config: config)
        poseService = PoseService(config: config)
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

        let poseService = poseService
        let poseLogger = poseLogger
        capture.onFrame = { buffer, time in
            poseService.process(buffer, time: time)
        }
        poseService.onResult = { [weak self] result in
            // Logged here on the pose queue so every frame is kept, not just the ones the screen shows.
            if UserDefaults.standard.bool(forKey: SettingsKey.debugMode) {
                poseLogger.log(result.frame)
            }
            Task { @MainActor in self?.handle(result) }
        }
        poseService.onFallback = { [weak self] rate in
            Task { @MainActor in self?.fallBack(to: rate) }
        }

        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            let typeValue = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let began = typeValue == AVAudioSession.InterruptionType.began.rawValue
            MainActor.assumeIsolated {
                if began { self?.endEarly("The drill stopped because something else used the sound.") }
            }
        })
        observers.append(center.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification, object: capture.session, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.endEarly("The drill stopped because the camera stopped.")
            }
        })
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
        guard await CaptureService.requestPermission() else {
            phase = .endedEarly(CaptureServiceError.permissionDenied.localizedDescription)
            return
        }
        do {
            try audio.start(config: config)
            poseService.reset(frameRate: config.pose.highFrameRate)
            frameRate = try await capture.start(preferredFrameRate: config.pose.highFrameRate)
            if frameRate < config.pose.highFrameRate {
                // No 60 fps format at 1080p on this phone: start the governor at 30 too.
                poseService.reset(frameRate: frameRate)
            }
        } catch {
            stopDevices()
            phase = .endedEarly(error.localizedDescription)
            return
        }
        if debugMode { poseLogger.start(label: drill.rawValue) }

        fusion.reset()
        placement.reset()
        placementStep = .body
        placementChecks = PlacementChecks()
        placementFix = nil
        soundCheckHeard = 0
        soundStepFailingSince = nil
        phase = .placement
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

    /// Skips the body part of placement. Debug mode only, for trying the app at a desk.
    func skipBodyCheck() {
        guard phase == .placement, placementStep == .body else { return }
        startSoundCheck()
    }

    /// Stops everything and goes back to the app. Used by Stop, Done and dismissing the drill.
    func cancel() {
        flowTask?.cancel()
        flowTask = nil
        speech.stopSpeaking()
        stopDevices()
        phase = .idle
    }

    /// Ends a drill in progress without a score.
    func endEarly(_ reason: String) {
        guard isInDrillFlow else { return }
        flowTask?.cancel()
        flowTask = nil
        speech.stopSpeaking()
        stopDevices()
        phase = .endedEarly(reason)
    }

    private func stopDevices() {
        audio.stop()
        capture.stop()
        poseLogger.stop()
        pose = nil
    }

    private func startSoundCheck() {
        placementStep = .sound
        soundCheckHeard = 0
        soundStepFailingSince = nil
        placementFix = nil
        capture.lockExposureAndWhiteBalance()
        counter.begin(at: HostClock.now(), duration: 3600)
        speech.say("Bounce the ball 3 times")
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
        // The camera has been running since placement, so every sound must be backed by a wrist push.
        counter.begin(at: drillStartHost, duration: config.drillSeconds, requireConfirmation: true)
        // The fusion buffer keeps running from placement, so the wrist motion just before "Go!" is not lost.
        fusedLog = []
        confirmedByLoudness = 0
        resetLive()
        phase = .running

        var tenCalled = false
        var keepDribblingCalled = false
        while true {
            guard await pause(0.1) else { return }
            let now = HostClock.now()
            let elapsed = now - drillStartHost
            secondsLeft = max(0, config.drillSeconds - elapsed)
            applyFusion(fusion.resolveStale(now: now))
            refreshLive(now: now)

            if checkThermal() { return }
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
        // Decide any sounds still waiting for the camera, so the last bounces are not lost.
        applyFusion(fusion.resolveStale(now: end + 10))
        let stats = counter.drillStats(now: end)
        // Rhythm only for now. Switching, low and eyes up arrive with fusion and head tracking in M3.
        let parts = PartScores(rhythm: stats.rhythmScore)
        let score = Scoring.score(parts: parts, bounceCount: stats.count,
                                  lostBalls: stats.lostBalls, config: config)
        let gaps = BounceDiagnostics.gaps(times: counter.bounceTimes, start: counter.windowStart, config: config)
        let diagnostics = DrillDiagnostics(gapReport: BounceDiagnostics.report(gaps: gaps),
                                           onsets: counter.onsetLog,
                                           rejectedVoice: counter.rejectedVoice,
                                           rejectedSpeech: counter.rejectedSpeech,
                                           spread: stats.spread,
                                           heard: heardCount,
                                           unconfirmed: counter.rejectedUnconfirmed,
                                           confirmedByLoudness: confirmedByLoudness,
                                           fused: fusedLog)
        let result = DrillResult(drill: drill, startedAt: drillStartDate, duration: config.drillSeconds,
                                 stats: stats, parts: parts, score: score, diagnostics: diagnostics)
        if debugMode { BounceLogger.write(result) }
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

    /// Ends the drill when the phone gets hot. Returns true if it did.
    private func checkThermal() -> Bool {
        let thermal = ProcessInfo.processInfo.thermalState
        guard thermal == .serious || thermal == .critical else { return false }
        endEarly("The phone got hot, so the drill stopped. Let it cool down and try again.")
        return true
    }

    // MARK: - Events

    private func handle(_ onset: Onset) {
        lastOnsetInfo = String(format: "energy %.1e, voice ratio %.2f", onset.lowEnergy, onset.voiceRatio)
            + (onset.isLikelyVoice ? " (voice)" : "")
        switch phase {
        case .placement where placementStep == .sound:
            if counter.ingest(onset) {
                soundCheckHeard += 1
                beat += 1
                if soundCheckHeard == 3 { startCountdown() }
            }
        case .running:
            if counter.ingest(onset) {
                heardCount += 1
                // The microphone liked it; now it waits for a wrist push before it counts.
                fusion.addOnset(onset)
            }
            rejectedVoice = counter.rejectedVoice
            rejectedSpeech = counter.rejectedSpeech
        default:
            break
        }
    }

    private func handle(_ result: PoseResult) {
        guard isInDrillFlow || phase == .summary else { return }
        if phase == .placement {
            updatePlacement(result)
        }
        var inCountdown = false
        if case .countdown = phase { inCountdown = true }
        if phase == .running || inCountdown {
            applyFusion(fusion.addPose(result.pose, time: result.frame.time))
        }

        // The screen needs no more than 30 updates a second.
        let now = HostClock.now()
        guard now - lastPoseUpdate >= 1.0 / 30 else { return }
        lastPoseUpdate = now
        pose = result.pose
        poseFrameRate = result.measuredFrameRate
        poseMilliseconds = result.processingSeconds * 1000
        droppedFrames = result.droppedFrames
    }

    private func updatePlacement(_ result: PoseResult) {
        let update = placement.update(pose: result.pose, time: result.frame.time)
        placementChecks = update.checks
        bodyHeightFraction = update.bodyHeightFraction
        centerOffset = update.centerOffset

        switch placementStep {
        case .body:
            placementFix = update.fix
            if update.settled {
                startSoundCheck()
            } else if let fix = update.speak {
                speech.say(fix.phrase)
            }
        case .sound:
            // If the kid wanders off during the sound check, go back to placing them.
            if update.checks.allPassed {
                soundStepFailingSince = nil
            } else {
                let start = soundStepFailingSince ?? result.frame.time
                soundStepFailingSince = start
                if result.frame.time - start > config.placement.holdSeconds {
                    placementStep = .body
                    placement.reset()
                    capture.unlockExposureAndWhiteBalance()
                }
            }
        }
        _ = checkThermal()
    }

    private func fallBack(to rate: Int) {
        guard isInDrillFlow || phase == .summary else { return }
        capture.setFrameRate(rate)
        frameRate = rate
    }

    private func updateLevel(_ level: Float) {
        let now = HostClock.now()
        guard now - lastLevelUpdate >= 0.05 else { return }
        lastLevelUpdate = now
        micLevel = level
    }

    /// Counts the sounds the wrists backed up and drops the rest.
    private func applyFusion(_ decided: [FusedOnset]) {
        guard phase == .running || phase == .summary else { return }
        var changed = false
        for item in decided {
            fusedLog.append(BounceLogger.FusedLogEntry(
                time: item.onset.time - counter.windowStart, audioVerdict: .accepted, energy: item.onset.lowEnergy,
                leftPush: item.leftPush, rightPush: item.rightPush, hand: item.hand?.rawValue,
                pushSpeed: item.pushSpeed, bodyVisible: item.bodyVisible, confirmed: item.confirmed,
                confirmedByLoudness: item.confirmedByLoudness))
            if item.confirmed {
                if counter.confirm(item.onset.time) {
                    beat += 1
                    if item.confirmedByLoudness { confirmedByLoudness += 1 }
                    changed = true
                }
            } else if counter.dismiss(item.onset.time) {
                unconfirmedCount += 1
            }
        }
        if changed { refreshLive(now: HostClock.now()) }
    }

    private func resetLive() {
        heardCount = 0
        unconfirmedCount = 0
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
        let record = SessionRecord(result: result, total: total, place: place, frameRate: frameRate,
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
