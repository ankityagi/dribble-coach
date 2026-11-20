import Foundation
import DribbleCore

/// In Debug mode, writes what the counter heard in each drill to Documents/BounceLogs as one JSON file,
/// so a surprising score can be checked against the actual bounce times.
enum BounceLogger {
    static var directory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BounceLogs", isDirectory: true)
    }

    private struct Entry: Encodable {
        let drill: String
        let startedAt: Date
        let durationSeconds: Double
        let bounces: Int
        let bouncesPerSecond: Double
        let lostBalls: Int
        let spread: Double?
        let rhythmScore: Double?
        let totalScore: Int?
        let rejectedVoice: Int
        let rejectedSpeech: Int
        let gaps: [BounceGap]
        let onsets: [OnsetRecord]
    }

    static func write(_ result: DrillResult) {
        guard let diagnostics = result.diagnostics else { return }
        let entry = Entry(drill: result.drill.rawValue, startedAt: result.startedAt,
                          durationSeconds: result.duration, bounces: result.stats.count,
                          bouncesPerSecond: result.stats.bouncesPerSecond, lostBalls: result.stats.lostBalls,
                          spread: diagnostics.spread, rhythmScore: result.stats.rhythmScore,
                          totalScore: result.score.total, rejectedVoice: diagnostics.rejectedVoice,
                          rejectedSpeech: diagnostics.rejectedSpeech, gaps: diagnostics.gapReport.gaps,
                          onsets: diagnostics.onsets)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let url = directory.appendingPathComponent("\(formatter.string(from: result.startedAt))_\(result.drill.rawValue).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try encoder.encode(entry).write(to: url)
        } catch {
            // Debug aid only; a failed write must never affect the drill.
        }
    }

    /// A sound and what the wrists did before it, for the Count test log.
    struct FusedLogEntry: Encodable {
        let time: Double
        let audioVerdict: OnsetVerdict
        let energy: Double
        let leftPush: Double?
        let rightPush: Double?
        let hand: String?
        let pushSpeed: Double?
        let bodyVisible: Bool
        let confirmed: Bool
        let confirmedByLoudness: Bool
    }

    private struct RawEntry: Encodable {
        let label: String
        let startedAt: Date
        let bounces: Int
        let minPushSpeed: Double
        let loudEnergy: Double
        let assistPushSpeed: Double
        let cameraFps: Int
        let trackingFps: Double
        let visionMilliseconds: Double
        let fellBackTo30: Bool
        let gaps: [BounceGap]
        let onsets: [OnsetRecord]
        let fused: [FusedLogEntry]
        let wrists: [WristSample]
    }

    /// Writes a bare onset log, for the Count test, which has no drill result.
    static func writeRaw(label: String, startedAt: Date, gaps: [BounceGap], onsets: [OnsetRecord],
                         fused: [FusedLogEntry] = [], wrists: [WristSample] = [], minPushSpeed: Double = 0,
                         loudEnergy: Double = 0, assistPushSpeed: Double = 0, cameraFps: Int = 0,
                         trackingFps: Double = 0, visionMilliseconds: Double = 0, fellBackTo30: Bool = false) {
        guard !onsets.isEmpty else { return }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let url = directory.appendingPathComponent("\(formatter.string(from: startedAt))_\(label).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let entry = RawEntry(label: label, startedAt: startedAt, bounces: onsets.filter { $0.verdict == .accepted }.count,
                             minPushSpeed: minPushSpeed, loudEnergy: loudEnergy,
                             assistPushSpeed: assistPushSpeed, cameraFps: cameraFps, trackingFps: trackingFps,
                             visionMilliseconds: visionMilliseconds, fellBackTo30: fellBackTo30, gaps: gaps, onsets: onsets, fused: fused, wrists: wrists)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try encoder.encode(entry).write(to: url)
        } catch {
            // Debug aid only.
        }
    }

    static func deleteAll() {
        try? FileManager.default.removeItem(at: directory)
    }
}
