import AVFoundation
import SwiftUI
import Observation
import DribbleCore

/// A Debug-mode screen with no camera, countdown or timer: bounce the ball and watch what the counter hears.
/// It is for checking the sound side on its own, before blaming the score.
@MainActor
@Observable
final class CountTestController {
    /// One sound as shown on screen: what the microphone decided and what the wrists said.
    struct Row: Identifiable {
        let id: Int
        let time: Double
        let audio: OnsetVerdict
        let fused: FusedOnset
    }

    var running = false
    var message: String?
    /// Sounds the counter accepted, the audio-only count.
    var count = 0
    /// Sounds the counter accepted AND a wrist push confirmed.
    var confirmedCount = 0
    var beat = 0
    var micLevel: Float = 0
    var lastOnsetInfo = "–"
    var rejectedVoice = 0
    var rejectedEcho = 0
    var gaps: [BounceGap] = []
    var confirmedGaps: [BounceGap] = []
    var spread: Double?
    var rhythm: Double?
    var perSecond = 0.0
    var rows: [Row] = []
    var pose: BodyPose?
    var poseFrameRate = 0.0
    var poseMilliseconds = 0.0
    var droppedFrames = 0
    /// The camera's frame rate as started, and whether the app dropped to 30 fps after that.
    var cameraFps = 0
    var fellBackTo30 = false
    var cameraOn = false

    var captureSession: AVCaptureSession { capture.session }

    @ObservationIgnored private var startedAt = Date()
    @ObservationIgnored private var fusedLog: [BounceLogger.FusedLogEntry] = []
    @ObservationIgnored private var wristLog: [WristSample] = []
    @ObservationIgnored private var confirmedTimes: [Double] = []
    @ObservationIgnored private var verdictByTime: [Double: OnsetVerdict] = [:]
    @ObservationIgnored private var nextRow = 0
    private let config: DribbleConfig
    private let audio = AudioService()
    private let capture = CaptureService()
    private let poseService: PoseService
    private let fusion: FusionEngine
    private let counter: BounceCounter
    private let confirmedCounter: BounceCounter
    @ObservationIgnored private var lastLevelUpdate = 0.0
    @ObservationIgnored private var lastPoseUpdate = 0.0

    init() {
        let config = DribbleConfig.load(overridesAt: Bundle.main.url(forResource: "DribbleConfig", withExtension: "json"))
        self.config = config
        counter = BounceCounter(config: config)
        confirmedCounter = BounceCounter(config: config)
        fusion = FusionEngine(config: config)
        poseService = PoseService(config: config)
        audio.onOnset = { [weak self] onset in Task { @MainActor in self?.handle(onset) } }
        audio.onLevel = { [weak self] level in Task { @MainActor in self?.updateLevel(level) } }
        let poseService = poseService
        capture.onFrame = { buffer, time in poseService.process(buffer, time: time) }
        poseService.onResult = { [weak self] result in Task { @MainActor in self?.handle(result) } }
        poseService.onFallback = { [weak self] rate in
            Task { @MainActor in
                self?.capture.setFrameRate(rate)
                self?.cameraFps = rate
                self?.fellBackTo30 = true
            }
        }
    }

    func start() async {
        guard !running else { return }
        guard await AudioService.requestPermission() else {
            message = AudioServiceError.permissionDenied.localizedDescription
            return
        }
        do {
            try audio.start(config: config)
        } catch {
            message = error.localizedDescription
            return
        }
        // The camera is what lets video correct the sound. If it can't start, keep going with sound only.
        if await CaptureService.requestPermission() {
            do {
                poseService.reset(frameRate: config.pose.highFrameRate)
                let rate = try await capture.start(preferredFrameRate: config.pose.highFrameRate)
                if rate < config.pose.highFrameRate { poseService.reset(frameRate: rate) }
                cameraFps = rate
                fellBackTo30 = false
                cameraOn = true
                message = nil
            } catch {
                message = "Camera off (\(error.localizedDescription)). Sound only."
            }
        } else {
            message = "Camera permission is off, so only sound is tested."
        }
        reset()
        running = true
    }

    func stop() {
        saveLog()
        audio.stop()
        capture.stop()
        cameraOn = false
        pose = nil
        running = false
    }

    private func saveLog() {
        BounceLogger.writeRaw(label: "counttest", startedAt: startedAt, gaps: gaps, onsets: counter.onsetLog,
                              fused: fusedLog, wrists: wristLog, minPushSpeed: config.minPushSpeed,
                              loudEnergy: config.loudEnergy, assistPushSpeed: config.assistPushSpeed,
                              cameraFps: cameraFps, trackingFps: poseFrameRate, visionMilliseconds: poseMilliseconds,
                              fellBackTo30: fellBackTo30)
    }

    func reset() {
        if running { saveLog() }
        startedAt = Date()
        let now = HostClock.now()
        counter.begin(at: now, duration: 3600)
        confirmedCounter.begin(at: now, duration: 3600)
        fusion.reset()
        fusedLog = []
        wristLog = []
        confirmedTimes = []
        rows = []
        nextRow = 0
        count = 0
        confirmedCount = 0
        gaps = []
        confirmedGaps = []
        spread = nil
        rhythm = nil
        perSecond = 0
        rejectedVoice = 0
        rejectedEcho = 0
        lastOnsetInfo = "–"
    }

    private func handle(_ onset: Onset) {
        guard running else { return }
        lastOnsetInfo = String(format: "energy %.1e, rise x%.0f, voice ratio %.2f", onset.lowEnergy, onset.riseRatio, onset.voiceRatio)
            + (onset.isLikelyVoice ? " (voice, ignored)" : "")
        if counter.ingest(onset) { beat += 1 }
        verdictByTime[onset.time] = counter.onsetLog.last?.verdict
        rejectedVoice = counter.rejectedVoice
        rejectedEcho = counter.rejectedEcho
        count = counter.bounceTimes.count
        gaps = BounceDiagnostics.gaps(times: counter.bounceTimes, start: counter.windowStart, config: config)
        let live = counter.liveStats(now: HostClock.now())
        spread = live.spread
        rhythm = live.rhythmScore
        perSecond = live.bouncesPerSecond
        if cameraOn {
            fusion.addOnset(onset)
        } else {
            // No camera: decide straight away as "no body".
            apply(fusion.resolveStale(now: onset.time + 10))
        }
    }

    private func handle(_ result: PoseResult) {
        guard running else { return }
        let time = result.frame.time
        wristLog.append(WristSample(t: time - counter.windowStart, leftY: result.pose?[.leftWrist]?.y,
                                    rightY: result.pose?[.rightWrist]?.y, torso: result.pose?.torsoLength))
        apply(fusion.addPose(result.pose, time: time))
        if time - lastPoseUpdate >= 1.0 / 30 {
            lastPoseUpdate = time
            pose = result.pose
            poseFrameRate = result.measuredFrameRate
            poseMilliseconds = result.processingSeconds * 1000
            droppedFrames = result.droppedFrames
        }
    }

    private func apply(_ fused: [FusedOnset]) {
        for item in fused {
            let verdict = verdictByTime[item.onset.time] ?? .accepted
            verdictByTime[item.onset.time] = nil
            fusedLog.append(BounceLogger.FusedLogEntry(
                time: item.onset.time - counter.windowStart, audioVerdict: verdict, energy: item.onset.lowEnergy,
                leftPush: item.leftPush, rightPush: item.rightPush, hand: item.hand?.rawValue,
                pushSpeed: item.pushSpeed, bodyVisible: item.bodyVisible, confirmed: item.confirmed,
                confirmedByLoudness: item.confirmedByLoudness))
            if verdict == .accepted && item.confirmed {
                confirmedTimes.append(item.onset.time)
            }
            rows.insert(Row(id: nextRow, time: item.onset.time - counter.windowStart, audio: verdict, fused: item), at: 0)
            nextRow += 1
        }
        if rows.count > 8 { rows.removeLast(rows.count - 8) }
        if !fused.isEmpty {
            confirmedCount = confirmedTimes.count
            confirmedGaps = BounceDiagnostics.gaps(times: confirmedTimes, start: counter.windowStart, config: config)
        }
    }

    private func updateLevel(_ level: Float) {
        let now = HostClock.now()
        guard now - lastLevelUpdate >= 0.05 else { return }
        lastLevelUpdate = now
        micLevel = level
        // Sounds the camera never caught up with still get decided.
        apply(fusion.resolveStale(now: now))
    }
}

struct CountTestView: View {
    @State private var test = CountTestController()
    @State private var flash = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Bounce the ball. Nothing is scored here. Stand 2.5 to 3 m from the phone.")
                    .foregroundStyle(.secondary)

                if test.cameraOn {
                    Text(String(format: "Camera %d fps%@, tracking %.0f fps, Vision %.1f ms, skipped %d",
                                test.cameraFps, test.fellBackTo30 ? " (fell back)" : "", test.poseFrameRate,
                                test.poseMilliseconds, test.droppedFrames))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    ZStack {
                        CameraPreview(session: test.captureSession)
                        SkeletonOverlay(pose: test.pose)
                    }
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                HStack(spacing: 12) {
                    countTile(title: "Sound only", value: test.count, tint: flash ? .orange : .gray.opacity(0.25))
                    countTile(title: "Sound + wrist", value: test.confirmedCount, tint: .green.opacity(0.35))
                }

                HStack(spacing: 12) {
                    StatTile(title: "Per second", value: String(format: "%.1f", test.perSecond))
                    StatTile(title: "Spread (last 5 s)", value: test.spread.map { String(format: "%.2f", $0) } ?? "–")
                    StatTile(title: "Rhythm", value: test.rhythm.map { "\(Int($0.rounded()))" } ?? "–")
                }

                Text("Gaps, sound only").font(.caption).foregroundStyle(.secondary)
                GapChart(gaps: Array(test.gaps.suffix(30)), median: BounceDiagnostics.report(gaps: test.gaps).median)
                if test.cameraOn {
                    Text("Gaps, sound + wrist").font(.caption).foregroundStyle(.secondary)
                    GapChart(gaps: Array(test.confirmedGaps.suffix(30)),
                             median: BounceDiagnostics.report(gaps: test.confirmedGaps).median)
                    soundList
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Last gap: \(test.gaps.last.map { "\(Int(($0.seconds * 1000).rounded())) ms" } ?? "–")")
                    Text("Last sound: \(test.lastOnsetInfo)")
                    Text("Ignored as voice: \(test.rejectedVoice), as echo: \(test.rejectedEcho)")
                    ProgressView(value: Double(min(test.micLevel, 1)))
                    Text("Mic level").font(.caption).foregroundStyle(.secondary)
                }
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)

                if let message = test.message {
                    Text(message).foregroundStyle(.red)
                }

                HStack(spacing: 16) {
                    Button("Reset") { test.reset() }.buttonStyle(.bordered)
                    Button(test.running ? "Stop" : "Start") {
                        if test.running { test.stop() } else { Task { await test.start() } }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
                .controlSize(.large)
            }
            .padding()
        }
        .navigationTitle("Count test")
        .task { await test.start() }
        .onDisappear { test.stop() }
        .onChange(of: test.beat) {
            flash = true
            Task {
                try? await Task.sleep(for: .milliseconds(120))
                flash = false
            }
        }
    }

    private func countTile(title: String, value: Int, tint: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(tint, in: RoundedRectangle(cornerRadius: 12))
    }

    /// The latest sounds, newest first: did a wrist push confirm it, and how hard each wrist moved.
    private var soundList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Latest sounds").font(.caption).foregroundStyle(.secondary)
            ForEach(test.rows) { row in
                HStack(spacing: 8) {
                    Image(systemName: row.fused.confirmed ? (row.fused.confirmedByLoudness ? "checkmark.circle" : "checkmark.circle.fill") : "xmark.circle")
                        .foregroundStyle(row.fused.confirmed ? Color.green : Color.red)
                    Text(String(format: "%5.1fs", row.time))
                    Text(row.audio == .accepted ? "heard" : "ignored: \(row.audio.rawValue)")
                    Spacer()
                    Text(row.fused.bodyVisible ? pushText(row.fused) : "no body")
                }
                .font(.caption.monospaced())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pushText(_ fused: FusedOnset) -> String {
        let l = fused.leftPush.map { String(format: "%.1f", $0) } ?? "–"
        let r = fused.rightPush.map { String(format: "%.1f", $0) } ?? "–"
        let hand = fused.hand.map { $0 == .left ? "L" : "R" } ?? "?"
        return "L \(l)  R \(r)  hand \(hand)"
    }
}
