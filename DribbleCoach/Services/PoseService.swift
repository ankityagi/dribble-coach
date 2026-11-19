import CoreMedia
import Foundation
import ImageIO
import Vision
import DribbleCore

/// One processed camera frame.
struct PoseResult {
    /// Everything Vision found, in the mirrored portrait view.
    let frame: PoseFrame
    /// The tracked player, smoothed, or nil when they aren't in view.
    let pose: BodyPose?
    let processingSeconds: Double
    let measuredFrameRate: Double
    let droppedFrames: Int
}

/// Vision body pose on each camera frame, on its own queue, dropping frames that arrive while busy.
/// Also runs the body tracker and the frame-rate governor, per the spec's PoseService.
final class PoseService {
    /// Turns the front camera's raw frames upright for a phone held in portrait, without mirroring.
    /// Vision names left and right from how a body looks, so it must see the real, unmirrored picture;
    /// x is mirrored afterwards. If the debug overlay says "Orientation: check", this is the line to look at.
    static let uprightOrientation = CGImagePropertyOrientation.right

    private let queue = DispatchQueue(label: "dribblecoach.pose", qos: .userInteractive)
    private let lock = NSLock()
    private var busy = false
    private var dropped = 0

    private let tracker: BodyTracker
    private let governor: FrameRateGovernor

    /// Called on the pose queue after every processed frame.
    var onResult: ((PoseResult) -> Void)?
    /// Called on the pose queue when the governor drops the frame rate.
    var onFallback: ((Int) -> Void)?

    init(config: DribbleConfig) {
        tracker = BodyTracker(config: config)
        governor = FrameRateGovernor(config: config)
    }

    /// Starts a new session: forgets the player and any earlier fallback.
    func reset(frameRate: Int) {
        queue.sync {
            tracker.reset()
            governor.reset(to: frameRate)
        }
        lock.withLock { dropped = 0 }
    }

    /// Call from the camera queue. Returns at once; the frame is skipped if the last one is still in Vision.
    func process(_ sampleBuffer: CMSampleBuffer, time: Double) {
        let skip: Bool = lock.withLock {
            if busy {
                dropped += 1
                return true
            }
            busy = true
            return false
        }
        guard !skip else { return }

        queue.async { [weak self] in
            guard let self else { return }
            defer { self.lock.withLock { self.busy = false } }
            self.run(sampleBuffer, time: time)
        }
    }

    private func run(_ sampleBuffer: CMSampleBuffer, time: Double) {
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: Self.uprightOrientation,
                                            options: [:])
        let started = HostClock.now()
        do {
            try handler.perform([request])
        } catch {
            return
        }
        let processing = HostClock.now() - started

        let bodies = (request.results ?? []).map(Self.joints(of:))
        let frame = PoseFrame(time: time, aspect: Self.portraitAspect(of: sampleBuffer), bodies: bodies)
        let pose = tracker.update(frame)
        if let rate = governor.record(frameTime: time, processingSeconds: processing) {
            onFallback?(rate)
        }
        let droppedSoFar = lock.withLock { dropped }
        onResult?(PoseResult(frame: frame, pose: pose, processingSeconds: processing,
                             measuredFrameRate: governor.measuredFrameRate, droppedFrames: droppedSoFar))
    }

    private static let jointNames: [Joint: VNHumanBodyPoseObservation.JointName] = [
        .nose: .nose, .leftEye: .leftEye, .rightEye: .rightEye, .leftEar: .leftEar, .rightEar: .rightEar,
        .neck: .neck, .leftShoulder: .leftShoulder, .rightShoulder: .rightShoulder,
        .root: .root, .leftHip: .leftHip, .rightHip: .rightHip,
        .leftKnee: .leftKnee, .rightKnee: .rightKnee, .leftAnkle: .leftAnkle, .rightAnkle: .rightAnkle,
        .leftWrist: .leftWrist, .rightWrist: .rightWrist,
    ]

    /// Vision's points, mirrored so x grows toward the player's right as on the selfie-style preview.
    private static func joints(of observation: VNHumanBodyPoseObservation) -> [Joint: JointObservation] {
        guard let points = try? observation.recognizedPoints(.all) else { return [:] }
        var result: [Joint: JointObservation] = [:]
        for (joint, name) in jointNames {
            guard let point = points[name], point.confidence > 0 else { continue }
            result[joint] = JointObservation(x: 1 - Double(point.location.x), y: Double(point.location.y),
                                             confidence: Double(point.confidence))
        }
        return result
    }

    /// Width over height of the upright frame. The raw buffer is landscape, so it's the short side over the long.
    private static func portraitAspect(of sampleBuffer: CMSampleBuffer) -> Double {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return 9.0 / 16.0 }
        let width = Double(CVPixelBufferGetWidth(buffer))
        let height = Double(CVPixelBufferGetHeight(buffer))
        guard width > 0, height > 0 else { return 9.0 / 16.0 }
        return min(width, height) / max(width, height)
    }
}
