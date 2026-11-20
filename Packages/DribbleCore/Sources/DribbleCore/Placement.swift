import Foundation

/// What the kid should do to be in the right spot, in the order the spec checks them.
public enum PlacementFix: String, CaseIterable, Codable, Sendable {
    /// No body in view. The spec has no line for this; this one is ours.
    case stepIn
    case stepBack
    case comeCloser
    case moveLeft
    case moveRight
    case showFeet

    /// The spoken line, per the spec. Left and right are the player's own.
    public var phrase: String {
        switch self {
        case .stepIn: return "Stand in front of me"
        case .stepBack: return "Step back"
        case .comeCloser: return "Come closer"
        case .moveLeft: return "Move left"
        case .moveRight: return "Move right"
        case .showFeet: return "I can't see your feet"
        }
    }
}

/// The checklist on the placement screen. The sound check is handled after these pass.
public struct PlacementChecks: Equatable, Sendable {
    public var bodyVisible = false
    public var rightDistance = false
    public var centered = false
    public var feetVisible = false

    public init() {}

    public var allPassed: Bool { bodyVisible && rightDistance && centered && feetVisible }
}

/// One frame's verdict.
public struct PlacementUpdate: Equatable, Sendable {
    public var checks: PlacementChecks
    /// The first thing to fix, or nil when everything passes.
    public var fix: PlacementFix?
    /// A fix to say out loud now, if one is due.
    public var speak: PlacementFix?
    /// True once every check has held for `holdSeconds`.
    public var settled: Bool
    /// Head to ankle as a share of the frame height, for the debug overlay.
    public var bodyHeightFraction: Double?
    /// Root position from the middle, as a share of the frame width; positive is the player's right.
    public var centerOffset: Double?
}

/// The spec's placement check: whole body visible, right distance, centered, feet in view,
/// all holding for a second, with one spoken fix at a time.
///
/// Frame fractions are in the mirrored portrait view, where x grows toward the player's right.
/// So a player too far to their right (x above the middle) is told "Move left".
public final class PlacementChecker {
    private let config: DribbleConfig.Placement
    private var passingSince: Double?
    private var failingSince: Double?
    private var currentFix: PlacementFix?
    private var currentFixSince = 0.0
    private var lastSpoken: (fix: PlacementFix, time: Double)?

    public init(config: DribbleConfig = DribbleConfig()) {
        self.config = config.placement
    }

    public func reset() {
        passingSince = nil
        failingSince = nil
        currentFix = nil
        currentFixSince = 0
        lastSpoken = nil
    }

    /// Feeds one frame. Pass nil when no player was found in it.
    public func update(pose: BodyPose?, time: Double) -> PlacementUpdate {
        var result = evaluate(pose)

        if result.checks.allPassed {
            failingSince = nil
            if passingSince == nil { passingSince = time }
        } else {
            if failingSince == nil { failingSince = time }
            if let failingSince, time - failingSince >= config.failureGraceSeconds {
                passingSince = nil
            }
        }
        result.settled = passingSince.map { time - $0 >= config.holdSeconds } ?? false

        if result.fix != currentFix {
            currentFix = result.fix
            currentFixSince = time
        }
        if let fix = result.fix, time - currentFixSince >= config.fixSettleSeconds, isDue(fix, at: time) {
            result.speak = fix
            lastSpoken = (fix, time)
        }
        return result
    }

    private func isDue(_ fix: PlacementFix, at time: Double) -> Bool {
        guard let lastSpoken else { return true }
        let since = time - lastSpoken.time
        if since < config.fixGapSeconds { return false }
        return lastSpoken.fix != fix || since >= config.fixRepeatSeconds
    }

    /// The checks for one frame, without any timing.
    public func evaluate(_ pose: BodyPose?) -> PlacementUpdate {
        var checks = PlacementChecks()
        func done(_ fix: PlacementFix?, height: Double? = nil, offset: Double? = nil) -> PlacementUpdate {
            PlacementUpdate(checks: checks, fix: fix, speak: nil, settled: false,
                            bodyHeightFraction: height, centerOffset: offset)
        }

        guard let pose, !pose.joints.isEmpty else { return done(.stepIn) }

        let headTop = Joint.head.compactMap { pose.frameFraction($0)?.y }.max()
        let ankles = Joint.ankles.compactMap { pose.frameFraction($0) }
        let root = pose.frameFraction(.root)
        checks.bodyVisible = headTop != nil && root != nil && pose[.neck] != nil

        // Part of a body but no hips usually means the lower body is off the bottom: too close.
        guard let root else { return done(.stepBack) }

        let height: Double?
        if let headTop, let lowest = ankles.map(\.y).min() {
            height = headTop - lowest
        } else if let torso = pose.torsoLength {
            height = torso * config.bodyHeightPerTorso
        } else {
            height = nil
        }
        let offset = root.x - 0.5

        let ys = pose.joints.keys.compactMap { pose.frameFraction($0)?.y }
        let touchesTopOrBottom = ys.contains { $0 > 1 - config.edgeMargin || $0 < config.edgeMargin }
        let tooClose = touchesTopOrBottom || (height.map { $0 > config.maxBodyHeightFraction } ?? false)
        let tooFar = height.map { $0 < config.minBodyHeightFraction } ?? false
        checks.rightDistance = height != nil && !tooClose && !tooFar
        checks.centered = abs(offset) <= config.centerTolerance
        checks.feetVisible = ankles.count == 2

        let fix: PlacementFix?
        if tooClose {
            fix = .stepBack
        } else if tooFar {
            fix = .comeCloser
        } else if offset > config.centerTolerance {
            fix = .moveLeft
        } else if offset < -config.centerTolerance {
            fix = .moveRight
        } else if !checks.feetVisible {
            fix = .showFeet
        } else if !checks.bodyVisible || height == nil {
            fix = .stepIn
        } else {
            fix = nil
        }
        return done(fix, height: height, offset: offset)
    }
}
