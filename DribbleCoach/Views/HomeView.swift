import SwiftUI
import SwiftData
import DribbleCore

struct HomeView: View {
    @Query(sort: \SessionRecord.startedAt, order: .reverse) private var records: [SessionRecord]

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            Image(systemName: "figure.basketball")
                .font(.system(size: 80))
                .foregroundStyle(.orange)
            Text("Dribble Coach")
                .font(.largeTitle.bold())

            HStack(spacing: 16) {
                StatTile(title: "Streak", value: "\(streak) \(streak == 1 ? "day" : "days")")
                StatTile(title: "Last score", value: records.first.map { "\($0.totalScore)" } ?? "–")
            }
            .padding(.horizontal)

            NavigationLink {
                DrillPickerView()
            } label: {
                Text("Start")
                    .font(.title.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .padding(.horizontal, 32)

            Spacer()
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink { HistoryView() } label: { Label("History", systemImage: "clock") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { SettingsView() } label: { Label("Settings", systemImage: "gearshape") }
            }
        }
    }

    private var streak: Int {
        Streak.days(sessionDates: records.map(\.startedAt), today: .now)
    }
}

struct DrillPickerView: View {
    @Environment(SessionController.self) private var session

    var body: some View {
        List(Drill.allCases) { drill in
            Button {
                Task { await session.begin(drill: drill) }
            } label: {
                HStack(spacing: 16) {
                    Image(systemName: "figure.basketball")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(drill.title).font(.title3.bold())
                        Text(drill.blurb).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }
            .foregroundStyle(.primary)
        }
        .navigationTitle("Pick a drill")
    }
}
