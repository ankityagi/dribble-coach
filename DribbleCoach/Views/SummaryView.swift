import SwiftUI
import SwiftData
import DribbleCore

struct SummaryView: View {
    @Environment(SessionController.self) private var session
    @Query(sort: \SessionRecord.startedAt, order: .reverse) private var records: [SessionRecord]
    let result: DrillResult

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if let total = result.score.total {
                    Text("\(total)")
                        .font(.system(size: 120, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                    StarsView(count: result.score.stars, size: 36)
                } else {
                    Text("Let's try that again")
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                    Text("I need at least \(session.config.minBouncesForScore) bounces to give a score.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 12) {
                    ForEach(Part.allCases, id: \.self) { part in
                        PartBar(part: part, value: result.parts[part])
                    }
                }

                HStack(spacing: 12) {
                    StatTile(title: "Bounces", value: "\(result.stats.count)")
                    StatTile(title: "Per second", value: String(format: "%.1f", result.stats.bouncesPerSecond))
                    StatTile(title: "Lost balls", value: "\(result.stats.lostBalls)")
                }

                if let weakest = result.score.weakest {
                    Label(weakest.tip, systemImage: "lightbulb.fill")
                        .font(.title3)
                        .multilineTextAlignment(.leading)
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
