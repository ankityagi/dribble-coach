import Foundation

/// Turns Vision's raw bodies into one smoothed player per frame, per the spec:
/// drop low-confidence joints, pick the largest body and follow it by its root,
/// smooth each joint with a One Euro filter, and keep a steady torso length as the body scale.
///
/// Not thread-safe: call it from the Vision queue only.
public final class BodyTracker {
    private let config: DribbleConfig.Pose
    private var filters: [Joint: PointFilter] = [:]
    private var lastSeen: [Joint: Double] = [:]
    private var scaleFilter: OneEuroFilter
    private var torsoLength: Double?
    private var anchor: Point2?
    private var anchorTime: Double?

    /// Goes up by one each time the tracker picks a new subject, for the debug log.
    public private(set) var subjectChanges = 0

    public init(config: DribbleConfig = DribbleConfig()) {
        self.config = config.pose
        scaleFilter = OneEuroFilter(minCutoff: config.pose.scaleCutoff, beta: 0)
    }

    public func reset() {
        filters = [:]
        lastSeen = [:]
        scaleFilter.reset()
        torsoLength = nil
        anchor = nil
        anchorTime = nil
    }

    /// The player in this frame, or nil when they aren't in it.
    public func update(_ frame: PoseFrame) -> BodyPose? {
        let bodies = frame.bodies
            .map { confidentJoints($0, aspect: frame.aspect) }
            .filter { $0.count >= 3 }

        guard let (body, isNewSubject) = chooseSubject(bodies, time: frame.time) else { return nil }
        if isNewSubject {
            subjectChanges += 1
            filters = [:]
            lastSeen = [:]
            scaleFilter.reset()
            torsoLength = nil
        }

        var smoothed: [Joint: Point2] = [:]
        for (joint, point) in body {
            if let seen = lastSeen[joint], frame.time - seen > config.jointResetSeconds {
                filters[joint]?.reset()
            }
            var filter = filters[joint] ?? PointFilter(minCutoff: config.smoothingMinCutoff,
                                                       beta: config.smoothingBeta,
                                                       derivativeCutoff: config.smoothingDerivativeCutoff)
            smoothed[joint] = filter.filter(point, at: frame.time)
            filters[joint] = filter
            lastSeen[joint] = frame.time
        }

        if let neck = smoothed[.neck], let root = smoothed[.root] {
            torsoLength = scaleFilter.filter(neck.distance(to: root), at: frame.time)
        }
        anchor = Self.anchor(of: body)
        anchorTime = frame.time

        return BodyPose(time: frame.time, aspect: frame.aspect, joints: smoothed, torsoLength: torsoLength)
    }

    /// Joints at or above their confidence floor, moved into image-height units.
    private func confidentJoints(_ body: [Joint: JointObservation], aspect: Double) -> [Joint: Point2] {
        var result: [Joint: Point2] = [:]
        for (joint, observation) in body where observation.confidence >= config.minConfidence(for: joint) {
            result[joint] = Point2(x: observation.point.x * aspect, y: observation.point.y)
        }
        return result
    }

    /// The followed body if it's still in the frame, otherwise the largest one.
    private func chooseSubject(_ bodies: [[Joint: Point2]], time: Double) -> ([Joint: Point2], Bool)? {
        guard !bodies.isEmpty else { return nil }

        if let anchor, let anchorTime, time - anchorTime <= config.subjectLostSeconds {
            let scale = torsoLength ?? Self.torso(of: bodies[0]) ?? 0.25
            let maxJump = config.maxRootJumpTorsos * scale
            let nearest = bodies
                .compactMap { body in Self.anchor(of: body).map { (body, $0.distance(to: anchor)) } }
                .min { $0.1 < $1.1 }
            if let nearest, nearest.1 <= maxJump {
                return (nearest.0, false)
            }
            // Someone else is in view but the player isn't: report nothing rather than jump to them.
            return nil
        }

        guard let largest = bodies.max(by: { Self.area(of: $0) < Self.area(of: $1) }) else { return nil }
        return (largest, true)
    }

    /// Where a body is: its root, else the middle of its hips, else its neck, else the middle of its joints.
    static func anchor(of body: [Joint: Point2]) -> Point2? {
        if let root = body[.root] { return root }
        if let l = body[.leftHip], let r = body[.rightHip] { return Point2(x: (l.x + r.x) / 2, y: (l.y + r.y) / 2) }
        if let neck = body[.neck] { return neck }
        guard !body.isEmpty else { return nil }
        let n = Double(body.count)
        return Point2(x: body.values.map(\.x).reduce(0, +) / n, y: body.values.map(\.y).reduce(0, +) / n)
    }

    static func torso(of body: [Joint: Point2]) -> Double? {
        guard let neck = body[.neck], let root = body[.root] else { return nil }
        return neck.distance(to: root)
    }

    /// Area of the box around a body's joints, for picking the largest body.
    static func area(of body: [Joint: Point2]) -> Double {
        let xs = body.values.map(\.x)
        let ys = body.values.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return 0 }
        return (maxX - minX) * (maxY - minY)
    }
}
