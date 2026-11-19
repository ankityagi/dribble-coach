import Foundation

/// The body joints v1 uses, named as the player's own left and right.
///
/// The spec's text says 13 joints but lists these 17; eyes up needs the eyes and ears, so all 17 are kept.
public enum Joint: String, CaseIterable, Codable, CodingKeyRepresentable, Sendable {
    case nose, leftEye, rightEye, leftEar, rightEar
    case neck, leftShoulder, rightShoulder
    case root, leftHip, rightHip
    case leftKnee, rightKnee, leftAnkle, rightAnkle
    case leftWrist, rightWrist

    public static let head: [Joint] = [.nose, .leftEye, .rightEye, .leftEar, .rightEar]
    public static let ankles: [Joint] = [.leftAnkle, .rightAnkle]

    /// Bones for drawing the debug skeleton.
    public static let bones: [(Joint, Joint)] = [
        (.leftEar, .leftEye), (.leftEye, .nose), (.nose, .rightEye), (.rightEye, .rightEar),
        (.nose, .neck),
        (.neck, .leftShoulder), (.neck, .rightShoulder),
        (.leftShoulder, .leftWrist), (.rightShoulder, .rightWrist),
        (.neck, .root), (.root, .leftHip), (.root, .rightHip),
        (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
    ]
}

/// A point in the portrait camera frame as the player sees it on screen (mirrored, like a selfie).
///
/// y points up, as in Vision. x grows toward the player's right. Raw points from Vision are
/// normalized (0...1 on both axes); points out of `BodyTracker` are in image-height units,
/// so x runs 0...aspect and distances mean the same in both directions.
public struct Point2: Equatable, Codable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public func distance(to other: Point2) -> Double {
        ((x - other.x) * (x - other.x) + (y - other.y) * (y - other.y)).squareRoot()
    }
}

/// One joint as Vision reported it: a normalized point and its confidence.
public struct JointObservation: Equatable, Codable, Sendable {
    public var point: Point2
    public var confidence: Double

    public init(point: Point2, confidence: Double) {
        self.point = point
        self.confidence = confidence
    }

    public init(x: Double, y: Double, confidence: Double) {
        self.init(point: Point2(x: x, y: y), confidence: confidence)
    }
}

/// Everything Vision found in one camera frame, before any choosing or smoothing.
/// This is what the debug pose log stores, one per line.
public struct PoseFrame: Equatable, Codable, Sendable {
    /// Host time of the frame, seconds.
    public var time: Double
    /// Frame width divided by height in the portrait view (about 0.5625 for 1080 × 1920).
    public var aspect: Double
    /// One entry per body Vision found, in normalized coordinates.
    public var bodies: [[Joint: JointObservation]]

    public init(time: Double, aspect: Double, bodies: [[Joint: JointObservation]]) {
        self.time = time
        self.aspect = aspect
        self.bodies = bodies
    }
}

/// The tracked player in one frame: confident joints only, smoothed, in image-height units.
public struct BodyPose: Equatable, Sendable {
    public let time: Double
    /// Frame width divided by height; x runs 0...aspect.
    public let aspect: Double
    public let joints: [Joint: Point2]
    /// Smoothed neck-to-root length, in image-height units: the unit for every body distance.
    /// Held from earlier frames when the neck or root is missing; nil until first seen.
    public let torsoLength: Double?

    public init(time: Double, aspect: Double, joints: [Joint: Point2], torsoLength: Double?) {
        self.time = time
        self.aspect = aspect
        self.joints = joints
        self.torsoLength = torsoLength
    }

    public subscript(joint: Joint) -> Point2? { joints[joint] }

    /// A point as a share of the frame: x and y both 0...1.
    public func frameFraction(_ joint: Joint) -> Point2? {
        guard let p = joints[joint], aspect > 0 else { return nil }
        return Point2(x: p.x / aspect, y: p.y)
    }

    /// A distance in torso lengths, or nil before the torso has been seen.
    public func inTorsos(_ distance: Double) -> Double? {
        guard let torsoLength, torsoLength > 0 else { return nil }
        return distance / torsoLength
    }

    /// A quick sanity check of camera orientation and mirroring for the debug overlay:
    /// facing the phone upright, the nose is above the neck and, mirrored, the player's left
    /// shoulder shows on the left. Nil when those joints are missing.
    public var looksUprightAndMirrored: Bool? {
        guard let nose = joints[.nose], let neck = joints[.neck],
              let left = joints[.leftShoulder], let right = joints[.rightShoulder] else { return nil }
        return nose.y > neck.y && left.x < right.x
    }
}
