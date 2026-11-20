import SwiftUI
import Observation
import DribbleCore

/// A Debug-mode screen with no camera, countdown or timer: bounce the ball and watch what the counter hears.
/// It is for checking the sound side on its own, before blaming the score.
@MainActor
@Observable
final class CountTestController {
    var running = false
    var message: String?
    var count = 0
    var beat = 0
    var micLevel: Float = 0
    var lastOnsetInfo = "–"
    var rejectedVoice = 0
    var rejectedEcho = 0
    var gaps: [BounceGap] = []
    var spread: Double?
    var rhythm: Double?
    var perSecond = 0.0

    @ObservationIgnored private var startedAt = Date()
    private let config: DribbleConfig
    private let audio = AudioService()
    private let counter: BounceCounter
    @ObservationIgnored private var lastLevelUpdate = 0.0

    init() {
        let config = DribbleConfig.load(overridesAt: Bundle.main.url(forResource: "DribbleConfig", withExtension: "json"))
        self.config = config
        counter = BounceCounter(config: config)
        audio.onOnset = { [weak self] onset in Task { @MainActor in self?.handle(onset) } }
        audio.onLevel = { [weak self] level in Task { @MainActor in self?.updateLevel(level) } }
    }

    func start() async {
        guard !running else { return }
        guard await AudioService.requestPermission() else {
            message = AudioServiceError.permissionDenied.localizedDescription
            return
        }
        do {
            try audio.start(config: config)
            message = nil
            reset()
            running = true
        } catch {
            message = error.localizedDescription
        }
    }

    func stop() {
        saveLog()
        audio.stop()
        running = false
    }

    /// Writes what was heard since the last reset to Documents/BounceLogs, so it can be read off the phone.
    private func saveLog() {
        BounceLogger.writeRaw(label: "counttest", startedAt: startedAt, gaps: gaps, onsets: counter.onsetLog)
    }

    func reset() {
        if running { saveLog() }
        startedAt = Date()
        counter.begin(at: HostClock.now(), duration: 3600)
        count = 0
        gaps = []
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
        rejectedVoice = counter.rejectedVoice
        rejectedEcho = counter.rejectedEcho
        count = counter.bounceTimes.count
        gaps = BounceDiagnostics.gaps(times: counter.bounceTimes, start: counter.windowStart, config: config)
        let live = counter.liveStats(now: HostClock.now())
        spread = live.spread
        rhythm = live.rhythmScore
        perSecond = live.bouncesPerSecond
    }

    private func updateLevel(_ level: Float) {
        let now = HostClock.now()
        guard now - lastLevelUpdate >= 0.05 else { return }
        lastLevelUpdate = now
        micLevel = level
    }
}

struct CountTestView: View {
    @State private var test = CountTestController()
    @State private var flash = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Bounce the ball. Nothing is scored here.")
                    .foregroundStyle(.secondary)

                Circle()
                    .fill(flash ? Color.orange : Color.gray.opacity(0.25))
                    .frame(width: 90, height: 90)
                    .overlay(Text("\(test.count)").font(.system(size: 44, weight: .heavy, design: .rounded)).monospacedDigit())

                HStack(spacing: 12) {
                    StatTile(title: "Per second", value: String(format: "%.1f", test.perSecond))
                    StatTile(title: "Spread (last 5 s)", value: test.spread.map { String(format: "%.2f", $0) } ?? "–")
                    StatTile(title: "Rhythm", value: test.rhythm.map { "\(Int($0.rounded()))" } ?? "–")
                }

                GapChart(gaps: Array(test.gaps.suffix(30)), median: BounceDiagnostics.report(gaps: test.gaps).median)

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
}
