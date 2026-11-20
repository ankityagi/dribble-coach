import Charts
import SwiftUI
import DribbleCore

/// One bar per gap between bounces. Orange bars are lost balls, red are suspicious, blue are normal.
struct GapChart: View {
    let gaps: [BounceGap]
    let median: Double?

    private func color(for gap: BounceGap) -> Color {
        if gap.isLost { return .orange }
        if let median, gap.seconds < median * 0.5 || gap.seconds > median * 1.6 { return .red }
        return .blue
    }

    var body: some View {
        Chart {
            ForEach(Array(gaps.enumerated()), id: \.offset) { index, gap in
                BarMark(x: .value("Bounce", index + 1), y: .value("Gap (s)", min(gap.seconds, 2.0)))
                    .foregroundStyle(color(for: gap))
            }
            if let median {
                RuleMark(y: .value("Median", median))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4]))
            }
        }
        .chartYAxisLabel("seconds, capped at 2")
        .frame(height: 140)
    }
}

/// Debug-mode numbers under the summary: what the gaps between bounces looked like and why the rhythm score is what it is.
struct BounceDebugSection: View {
    let diagnostics: DrillDiagnostics
    let stats: RhythmStats

    private func ms(_ value: Double?) -> String {
        value.map { "\(Int(($0 * 1000).rounded())) ms" } ?? "–"
    }

    var body: some View {
        let report = diagnostics.gapReport
        VStack(alignment: .leading, spacing: 8) {
            Text("Bounce details (Debug)").font(.headline)
            GapChart(gaps: report.gaps, median: report.median)
            Group {
                Text("Spread \(diagnostics.spread.map { String(format: "%.2f", $0) } ?? "–") (0 at 0.35 or more gives rhythm 0)")
                Text("Gaps: shortest \(ms(report.shortest)), median \(ms(report.median)), longest \(ms(report.longest))")
                Text("Under half the median: \(report.tooShort) (likely one thump counted twice)")
                Text("Over 1.6x the median: \(report.tooLong) (likely a missed bounce)")
                Text("Lost-ball gaps: \(stats.lostBalls), \(report.gaps.filter(\.isLost).map { String(format: "%.1fs at %.1fs", $0.seconds, $0.time - $0.seconds) }.joined(separator: ", "))")
                Text("Heard \(diagnostics.heard), counted \(stats.count); \(diagnostics.unconfirmed) had no wrist push behind them (talking, other noise or a missed push)")
                Text("Counted only because the sound was loud: \(diagnostics.confirmedByLoudness)")
                Text("Heard while the coach spoke (the camera decided): \(diagnostics.duringSpeech)")
                Text("Ignored sounds: \(diagnostics.rejectedVoice) as voice, \(diagnostics.rejectedSpeech) while the coach spoke")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            Text("Full log: Documents/BounceLogs in the Files app.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}
