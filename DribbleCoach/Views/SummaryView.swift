import SwiftUI
import SwiftData
import DribbleCore

struct SummaryView: View {
    @Environment(SessionController.self) private var session
    @Query(sort: \SessionRecord.startedAt, order: .reverse) private var records: [SessionRecord]
    @AppStorage(SettingsKey.debugMode) private var debugMode = false
    let result: DrillResult

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if result.progress.comparison == .tooFew {
                    Text("Let's try that again")
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                    Text("I need at least \(session.config.minBouncesForScore) bounces to count a drill. I counted \(result.stats.count).")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("\(result.stats.count)")
                        .font(.system(size: 120, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                    Text("bounces")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    StarsView(count: result.progress.stars, size: 36)
                    Text(comparisonText)
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 12) {
                    StatTile(title: "Per second", value: String(format: "%.1f", result.stats.bouncesPerSecond))
                    handTile
                    StatTile(title: "Lost balls", value: "\(result.stats.lostBalls)")
                }

                if result.progress.comparison != .tooFew {
                    Label(result.tip, systemImage: "lightbulb.fill")
                        .font(.title3)
                        .multilineTextAlignment(.leading)
                }

                if debugMode {
                    internalScore
                    if let diagnostics = result.diagnostics {
                        BounceDebugSection(diagnostics: diagnostics, stats: result.stats)
                    }
                }

                Text("Streak: \(streak) \(streak == 1 ? "day" : "days")")
                    .font(.headline)

                HStack(spacing: 16) {
                    Button("Again") { session.again() }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    Button("Done") { session.cancel() }
                        .buttonStyle(.bordered)
                }
                .controlSize(.large)
            }
            .padding()
        }
    }

    /// Hand switches for the crossover, bounces with the target hand for the pound drills.
    @ViewBuilder
    private var handTile: some View {
        switch result.drill {
        case .crossover:
            StatTile(title: "Hand switches", value: "\(result.hands.switches)")
        case .rightPound:
            StatTile(title: "Right hand", value: handShare)
        case .leftPound:
            StatTile(title: "Left hand", value: handShare)
        }
    }

    private var handShare: String {
        result.hands.known > 0 ? "\(result.hands.onTarget) of \(result.hands.known)" : "–"
    }

    private var comparisonText: String {
        switch result.progress.comparison {
        case .tooFew: return ""
        case .first: return "Your first time. Nice start!"
        case .newBest(let previous): return "New best! Your old best was \(previous)."
        case .beatLast(let by): return "\(by) more than last time!"
        case .matchedLast: return "Same as last time. Can you beat it?"
        case .belowLast(let by, let best): return "\(by) fewer than last time. Your best is \(best)."
        }
    }

    /// The old 0 to 100 score, kept for development until all four parts exist.
    private var internalScore: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Internal score (not shown to kids)").font(.headline)
            Text("Total \(result.score.total.map(String.init) ?? "–"), rhythm \(result.parts.rhythm.map { String(Int($0.rounded())) } ?? "–"), lost balls \(result.stats.lostBalls)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private var streak: Int {
        Streak.days(sessionDates: records.map(\.startedAt), today: .now)
    }
}

struct PartBar: View {
    let part: Part
    let value: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(part.title).font(.headline)
                Spacer()
                Text(value.map { "\(Int($0.rounded()))" } ?? (part == .rhythm ? "Not enough bounces" : "Coming with body tracking"))
                    .font(value == nil ? Font.caption : Font.headline)
                    .foregroundStyle(value == nil ? Color.secondary : Color.primary)
                    .monospacedDigit()
            }
            ProgressView(value: (value ?? 0) / 100)
                .tint(.orange)
                .opacity(value == nil ? 0.3 : 1)
        }
    }
}

struct StarsView: View {
    let count: Int
    var size: CGFloat = 20

    var body: some View {
        HStack(spacing: size * 0.2) {
            ForEach(0..<3, id: \.self) { index in
                Image(systemName: index < count ? "star.fill" : "star")
                    .font(.system(size: size))
                    .foregroundStyle(index < count ? Color.yellow : Color.gray.opacity(0.4))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) of 3 stars")
    }
}

struct StatTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.bold())
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}
