import AVFoundation
import SwiftUI
import UIKit
import DribbleCore

/// The live front camera, mirrored like a selfie and fitted whole into the view (no cropping),
/// so the kid sees exactly what the placement check sees.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspect
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        view.rotateToPortrait()
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        override func layoutSubviews() {
            super.layoutSubviews()
            rotateToPortrait()
        }

        /// The app is portrait only, so the preview is always turned upright.
        func rotateToPortrait() {
            guard let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(90) else { return }
            connection.videoRotationAngle = 90
        }
    }
}

/// Where the camera picture sits inside a view of `size`, fitted whole like `.resizeAspect`.
func cameraRect(in size: CGSize, aspect: Double) -> CGRect {
    guard size.width > 0, size.height > 0, aspect > 0 else { return .zero }
    let width = min(size.width, size.height * aspect)
    let height = width / aspect
    return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
}

/// The tracked joints and bones drawn over the camera picture, for Debug mode.
struct SkeletonOverlay: View {
    let pose: BodyPose?

    var body: some View {
        Canvas { context, size in
            guard let pose else { return }
            let rect = cameraRect(in: size, aspect: pose.aspect)
            func place(_ joint: Joint) -> CGPoint? {
                guard let p = pose.frameFraction(joint) else { return nil }
                // y points up in the pose and down on screen.
                return CGPoint(x: rect.minX + p.x * rect.width, y: rect.maxY - p.y * rect.height)
            }
            var bones = Path()
            for (a, b) in Joint.bones {
                guard let pa = place(a), let pb = place(b) else { continue }
                bones.move(to: pa)
                bones.addLine(to: pb)
            }
            context.stroke(bones, with: .color(.green), lineWidth: 3)
            for joint in Joint.allCases {
                guard let p = place(joint) else { continue }
                let color: Color = joint == .leftWrist ? .blue : joint == .rightWrist ? .red : .yellow
                context.fill(Path(ellipseIn: CGRect(x: p.x - 5, y: p.y - 5, width: 10, height: 10)),
                             with: .color(color))
            }
        }
        .allowsHitTesting(false)
    }
}

/// Body-tracking numbers for Debug mode: frame rate, Vision time and an orientation check.
struct PoseDebugText: View {
    @Environment(SessionController.self) private var session

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(format: "Camera %d fps, tracking %.0f fps, Vision %.1f ms, skipped %d",
                        session.frameRate, session.poseFrameRate, session.poseMilliseconds,
                        session.droppedFrames))
            Text("Torso: \(session.pose?.torsoLength.map { String(format: "%.3f of frame height", $0) } ?? "–")")
            Text("Orientation: \(orientationText)")
        }
        .font(.caption.monospaced())
    }

    private var orientationText: String {
        switch session.pose?.looksUprightAndMirrored {
        case .some(true): return "OK (left wrist blue, right wrist red)"
        case .some(false): return "check: the pose looks flipped or rotated"
        case .none: return "–"
        }
    }
}
