import SwiftUI
import UIKit
import DribbleCore

/// Full-screen container for one drill: placement check, countdown, drill, summary.
struct DrillFlowView: View {
    @Environment(SessionController.self) private var session

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            switch session.phase {
            case .idle:
                EmptyView()
            case .placement:
                PlacementView()
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

/// The spec's placement check: live camera with an outline to stand in and a checklist.
/// It moves on by itself: body checks first, then three bounces for the sound check.
struct PlacementView: View {
    @Environment(SessionController.self) private var session
    @AppStorage(SettingsKey.debugMode) private var debugMode = false

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                CameraPreview(session: session.captureSession)
                Image(systemName: "figure.stand")
                    .resizable()
                    .scaledToFit()
                    .padding(.vertical, 60)
                    .foregroundStyle(.white.opacity(session.placementChecks.allPassed ? 0.15 : 0.35))
                    .allowsHitTesting(false)
                if debugMode {
                    SkeletonOverlay(pose: session.pose)
                }
                VStack {
                    Spacer()
                    Text(headline)
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 14))
                        .padding(.bottom, 16)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))

            checklist

            if debugMode {
                VStack(alignment: .leading, spacing: 4) {
                    PoseDebugText()
                    Text(String(format: "Body height %@, off center %@",
                                session.bodyHeightFraction.map { String(format: "%.2f", $0) } ?? "–",
                                session.centerOffset.map { String(format: "%+.2f", $0) } ?? "–"))
                        .font(.caption.monospaced())
                    HStack {
                        if session.placementStep == .body {
                            Button("Skip body check") { session.skipBodyCheck() }
                        }
                        Button("Skip sound check") { session.startCountdown() }
                    }
                    .font(.caption)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
    }

    private var headline: String {
        switch session.placementStep {
        case .body: return session.placementFix?.phrase ?? "Stay there!"
        case .sound: return "Bounce the ball 3 times"
        }
    }

    private var checklist: some View {
        let checks = session.placementChecks
        return HStack(spacing: 14) {
            CheckItem(title: "Body", passed: checks.bodyVisible)
            CheckItem(title: "Distance", passed: checks.rightDistance)
            CheckItem(title: "Center", passed: checks.centered)
            CheckItem(title: "Feet", passed: checks.feetVisible)
            CheckItem(title: "Sound", passed: session.soundCheckHeard >= 3,
                      progress: session.placementStep == .sound ? session.soundCheckHeard : nil)
        }
    }
}

private struct CheckItem: View {
    let title: String
    let passed: Bool
    /// Bounces heard so far, for the sound check.
    var progress: Int?

    var body: some View {
        VStack(spacing: 4) {
            if let progress, !passed {
                Text("\(progress)/3")
                    .font(.title3.bold().monospacedDigit())
                    .frame(height: 28)
            } else {
                Image(systemName: passed ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(passed ? .green : .secondary)
                    .frame(height: 28)
            }
            Text(title).font(.caption)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(passed ? "done" : "not yet")
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
                ZStack {
                    CameraPreview(session: session.captureSession)
                    SkeletonOverlay(pose: session.pose)
                }
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 10))
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
            PoseDebugText()
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
