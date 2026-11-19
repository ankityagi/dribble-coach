import SwiftUI
import SwiftData
import DribbleCore

struct HistoryView: View {
    @Query(sort: \SessionRecord.startedAt, order: .reverse) private var records: [SessionRecord]

    var body: some View {
        List {
            if records.isEmpty {
                ContentUnavailableView("No drills yet", systemImage: "basketball",
                                       description: Text("Finish a drill to see it here."))
            }
            ForEach(records) { record in
                NavigationLink {
                    RecordDetailView(record: record)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.drill.title).font(.headline)
                            Text(record.startedAt, format: .dateTime.month().day().hour().minute())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(record.totalScore)")
                            .font(.title2.bold())
                            .monospacedDigit()
                        StarsView(count: record.stars, size: 12)
                    }
                }
            }
        }
        .navigationTitle("History")
    }
}

struct RecordDetailView: View {
    let record: SessionRecord

    var body: some View {
        Form {
            Section {
                LabeledContent("Score", value: "\(record.totalScore)")
                LabeledContent("Stars", value: "\(record.stars)")
                LabeledContent("Bounces", value: "\(record.bounceCount)")
                LabeledContent("Per second", value: String(format: "%.1f", record.bouncesPerSecond))
                LabeledContent("Lost balls", value: "\(record.lostBalls)")
            }
            Section("Parts") {
                LabeledContent("Rhythm", value: format(record.rhythmScore))
                LabeledContent("Switching", value: format(record.switchingScore))
                LabeledContent("Low", value: format(record.lowScore))
                LabeledContent("Eyes up", value: format(record.eyesUpScore))
            }
            Section("Details") {
                LabeledContent("Place", value: Place(rawValue: record.placeRaw)?.title ?? record.placeRaw)
                LabeledContent("Phone", value: record.deviceModel)
                LabeledContent("App version", value: record.appVersion)
                LabeledContent("Tuning version", value: "\(record.configVersion)")
            }
        }
        .navigationTitle(record.drill.title)
    }

    private func format(_ value: Double?) -> String {
        value.map { "\(Int($0.rounded()))" } ?? "–"
    }
}

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(SettingsKey.playerName) private var playerName = ""
    @AppStorage(SettingsKey.place) private var placeRaw = Place.home.rawValue
    @AppStorage(SettingsKey.voiceOn) private var voiceOn = true
    @AppStorage(SettingsKey.debugMode) private var debugMode = false
    @State private var confirmDelete = false
    @State private var versionTaps = 0

    var body: some View {
        Form {
            Section("Player") {
                TextField("First name (optional)", text: $playerName)
                    .textInputAutocapitalization(.words)
            }
            Section {
                Picker("Place", selection: $placeRaw) {
                    ForEach(Place.allCases) { place in
                        Text(place.title).tag(place.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Where you practice")
            } footer: {
                Text("Gym mode will ignore other balls once body tracking is in. For now both work the same.")
            }
            Section {
                Toggle("Coach voice", isOn: $voiceOn)
            }
            Section {
                Button("Delete all data", role: .destructive) { confirmDelete = true }
            }
            Section {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(version).foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    versionTaps += 1
                    if versionTaps >= 5 {
                        versionTaps = 0
                        debugMode.toggle()
                    }
                }
                if debugMode {
                    Text("Debug mode is on").foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog("Delete every saved drill and debug log?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete all", role: .destructive) {
                try? modelContext.delete(model: SessionRecord.self)
                try? modelContext.save()
                PoseLogger.deleteAll()
            }
        }
    }

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(short) (\(build))"
    }
}
