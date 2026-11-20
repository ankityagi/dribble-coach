import Foundation
@testable import DribbleCore

/// Made-up Vision bodies for tests: a kid standing upright facing the phone, in the mirrored portrait view.
enum PoseFactory {
    static let aspect = 1080.0 / 1920.0

    /// A standing body, normalized like Vision's output.
    /// - Parameters:
    ///   - centerX: the root's x as a share of the frame width.
    ///   - footY: ankle height as a share of the frame height.
    ///   - height: ankle to eyes as a share of the frame height (head top here is the eyes).
    static func standing(centerX: Double = 0.5, footY: Double = 0.1, height: Double = 0.65,
                         confidence: Double = 0.9, dropping: Set<Joint> = []) -> [Joint: JointObservation] {
        // Offsets across, in image-height units, turned into frame-width fractions below.
        func at(_ dx: Double, _ share: Double) -> JointObservation {
            JointObservation(x: centerX + dx * height / aspect, y: footY + share * height, confidence: confidence)
        }
        // Mirrored view: the player's left side shows on the left of the screen.
        var body: [Joint: JointObservation] = [
            .leftAnkle: at(-0.06, 0), .rightAnkle: at(0.06, 0),
            .leftKnee: at(-0.06, 0.29), .rightKnee: at(0.06, 0.29),
            .leftHip: at(-0.06, 0.55), .rightHip: at(0.06, 0.55), .root: at(0, 0.55),
            .leftWrist: at(-0.14, 0.5), .rightWrist: at(0.14, 0.5),
            .leftShoulder: at(-0.1, 0.84), .rightShoulder: at(0.1, 0.84), .neck: at(0, 0.85),
            .nose: at(0, 0.95), .leftEye: at(-0.02, 1.0), .rightEye: at(0.02, 1.0),
            .leftEar: at(-0.04, 0.98), .rightEar: at(0.04, 0.98),
        ]
        for joint in dropping { body[joint] = nil }
        return body
    }

    static func frame(_ time: Double, _ bodies: [Joint: JointObservation]...) -> PoseFrame {
        PoseFrame(time: time, aspect: aspect, bodies: bodies)
    }

    /// A tracked pose straight from a standing body, without smoothing, for placement tests.
    static func pose(time: Double = 0, centerX: Double = 0.5, footY: Double = 0.1, height: Double = 0.65,
                     dropping: Set<Joint> = []) -> BodyPose {
        let body = standing(centerX: centerX, footY: footY, height: height, dropping: dropping)
        var joints: [Joint: Point2] = [:]
        for (joint, observation) in body {
            joints[joint] = Point2(x: observation.point.x * aspect, y: observation.point.y)
        }
        let torso = 0.30 * height
        return BodyPose(time: time, aspect: aspect, joints: joints, torsoLength: torso)
    }
}
