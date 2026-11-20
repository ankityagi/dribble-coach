import Foundation
import SwiftData
import DribbleCore

enum Drill: String, CaseIterable, Identifiable, Codable {
    case crossover
    case rightPound
    case leftPound

    var id: String { rawValue }

    var title: String {
        switch self {
        case .crossover: return "Crossover"
        case .rightPound: return "Right-hand pound"
        case .leftPound: return "Left-hand pound"
        }
    }

    var blurb: String {
        switch self {
        case .crossover: return "Bounce it across your body, hand to hand."
        case .rightPound: return "Hard, low dribbles with your right hand."
        case .leftPound: return "Hard, low dribbles with your left hand."
        }
    }
}

enum Place: String, CaseIterable, Identifiable {
    case home
    case gym

    var id: String { rawValue }
    var title: String { self == .home ? "Home" : "Gym" }
}

/// Keys for the few settings kept in UserDefaults.
enum SettingsKey {
    static let playerName = "playerName"
    static let place = "place"
    static let voiceOn = "voiceOn"
    static let debugMode = "debugMode"
}

/// What the counter heard during a drill, for the Debug-mode summary and the bounce log.
struct DrillDiagnostics: Equatable {
    let gapReport: GapReport
    let onsets: [OnsetRecord]
    let rejectedVoice: Int
    let rejectedSpeech: Int
    let spread: Double?
    /// Sounds the microphone accepted.
    let heard: Int
    /// Of those, how many no wrist push backed up, so they were not counted.
    let unconfirmed: Int
    /// Counted bounces that were confirmed only because the sound was loud, not by a strong push.
    let confirmedByLoudness: Int
    let fused: [BounceLogger.FusedLogEntry]
}

/// The outcome of one finished drill, shown on the summary screen.
struct DrillResult: Equatable {
    let drill: Drill
    let startedAt: Date
    let duration: Double
    let stats: RhythmStats
    let parts: PartScores
    let score: ScoreResult
    var diagnostics: DrillDiagnostics? = nil
}

/// A saved drill, per the spec's Session record.
@Model
final class SessionRecord {
    var id: UUID
    var startedAt: Date
    var drillRaw: String
    var placeRaw: String
    var durationSeconds: Double
    var totalScore: Int
    var stars: Int
    var rhythmScore: Double?
    var switchingScore: Double?
    var lowScore: Double?
    var eyesUpScore: Double?
    var bounceCount: Int
    var bouncesPerSecond: Double
    var lostBalls: Int
    var frameRate: Int
    var deviceModel: String
    var appVersion: String
    var configVersion: Int

    var drill: Drill { Drill(rawValue: drillRaw) ?? .crossover }

    init(result: DrillResult, total: Int, place: Place, frameRate: Int,
         deviceModel: String, appVersion: String, configVersion: Int) {
        id = UUID()
        startedAt = result.startedAt
        drillRaw = result.drill.rawValue
        placeRaw = place.rawValue
        durationSeconds = result.duration
        totalScore = total
        stars = result.score.stars
        rhythmScore = result.parts.rhythm
        switchingScore = result.parts.switching
        lowScore = result.parts.low
        eyesUpScore = result.parts.eyesUp
        bounceCount = result.stats.count
        bouncesPerSecond = result.stats.bouncesPerSecond
        lostBalls = result.stats.lostBalls
        self.frameRate = frameRate
        self.deviceModel = deviceModel
        self.appVersion = appVersion
        self.configVersion = configVersion
    }
}
