import SwiftUI
import UIKit
import DribbleCore

/// Full-screen container for one drill: sound check, countdown, drill, summary.
struct DrillFlowView: View {
    @Environment(SessionController.self) private var session

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            switch session.phase {
            case .idle:
                EmptyView()
            case .soundCheck:
                SoundCheckView()
            case .countdown(let text):
                Text(text)
                    .font(.system(size: 120, weight: .heavy, design: .rounded))
                    .minimumScaleFactor(0.3)
                    .lineLimit(1)
                    .padding()
            case .running:
                DrillView()
            case .summary:
                if let result = session.lastResult {
                    SummaryView(result: result)
                }
            case .endedEarly(let reason):
                EndedEarlyView(reason: reason)
            }
        }
        .overlay(alignment: .topTrailing) {
            if session.isInDrillFlow {
                Button {
                    session.cancel()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .accessibilityLabel("Stop")
            }
        }
        // Nobody touches the phone during a drill, so keep the screen from locking.
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }
}

/// Stand-in for the spec's placement check until body tracking lands in M2:
/// only the sound part runs, by asking for three bounces.
struct SoundCheckView: View {
    @Environment(SessionController.self) private var session

    var body: some View {
        VStack(spacing: 28) {
            Image(systemName: "figure.basketball")
                .font(.system(size: 90))
                .foregroundStyle(.orange)
            Text("Bounce the ball 3 times")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            HStack(spacing: 20) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(index < session.soundCheckHeard ? Color.green : Color.gray.opacity(0.3))
                        .frame(width: 36, height: 36)
                }
            }
            Text("Stand back so your whole body fits on the screen. The camera check comes with body tracking.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Skip the sound check") { session.startCountdown() }
                .font(.callout)
        }
        .padding()
    }
}

struct DrillView: View {
    @Environment(SessionController.self) private var session
    @AppStorage(SettingsKey.debugMode) private var debugMode = false
    @State private var lit = false

    var body: some View {
        VStack(spacing: 24) {
            Text(session.drill.title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.secondary)

            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 18)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 18, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.1), value: progress)
                VStack(spacing: 0) {
                    Text("\(session.liveCount)")
                        .font(.system(size: 110, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("bounces")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 280, height: 280)

            Circle()
                .fill(lit ? Color.orange : Color.gray.opacity(0.2))
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)

            Text("\(Int(session.secondsLeft.rounded(.up)))s left")
                .font(.title3.monospacedDigit())

            if debugMode {
                DebugPanel()
            }
        }
        .padding()
        .onChange(of: session.beat) {
            lit = true
            Task {
                try? await Task.sleep(for: .milliseconds(90))
                withAnimation(.easeOut(duration: 0.2)) { lit = false }
            }
        }
    }

    private var progress: Double {
        let total = session.config.drillSeconds
        return total > 0 ? 1 - session.secondsLeft / total : 0
    }
}

/// Debug numbers under the drill, shown when Debug mode is on.
struct DebugPanel: View {
    @Environment(SessionController.self) private var session

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: Double(min(session.micLevel, 1))) {
                Text("Mic level")
            }
            Text(String(format: "Speed (5 s): %.1f per second", session.liveBouncesPerSecond))
            Text("Rhythm (5 s): \(session.liveRhythm.map { String(Int($0.rounded())) } ?? "–")")
            Text("Ignored: \(session.rejectedVoice) voice, \(session.rejectedSpeech) while coach spoke")
            Text("Last onset: \(session.lastOnsetInfo)")
        }
        .font(.caption.monospaced())
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

struct EndedEarlyView: View {
    @Environment(SessionController.self) private var session
    let reason: String

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "pause.circle")
                .font(.system(size: 72))
                .foregroundStyle(.secondary)
            Text(reason)
                .font(.title3)
                .multilineTextAlignment(.center)
            Button("Done") { session.cancel() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding()
    }
}
