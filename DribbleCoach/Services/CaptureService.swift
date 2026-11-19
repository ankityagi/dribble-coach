import AVFoundation
import CoreMedia

enum CaptureServiceError: LocalizedError {
    case permissionDenied
    case noCamera
    case setupFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied: return "Dribble Coach needs the camera to see how you dribble. Turn it on in Settings."
        case .noCamera: return "The front camera isn't available right now."
        case .setupFailed: return "The camera couldn't start. Try again."
        }
    }
}

/// The front camera, per the spec: 1080p, 60 fps where the phone supports it, frames timed on the host clock.
///
/// Frames come out unrotated and unmirrored; `PoseService` tells Vision how to turn them upright.
/// The camera never touches the audio session, which `AudioService` owns.
final class CaptureService: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "dribblecoach.capture.session")
    private let videoQueue = DispatchQueue(label: "dribblecoach.capture.video", qos: .userInteractive)
    private let output = AVCaptureVideoDataOutput()
    private var device: AVCaptureDevice?
    private var isConfigured = false

    /// Called on the video queue with each frame and its host time in seconds.
    var onFrame: ((CMSampleBuffer, Double) -> Void)?

    static func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    /// Starts the camera and returns the frame rate it runs at: `preferred` if a 1080p format allows it, else 30.
    func start(preferredFrameRate preferred: Int) async throws -> Int {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async {
                do {
                    let rate = try self.configureIfNeeded(preferredFrameRate: preferred)
                    if !self.session.isRunning { self.session.startRunning() }
                    continuation.resume(returning: rate)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stop() {
        sessionQueue.async {
            self.unlockExposureAndWhiteBalanceNow()
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    /// Switches frame rate on the running camera, for the fallback to 30 fps.
    func setFrameRate(_ fps: Int) {
        sessionQueue.async {
            guard let device = self.device else { return }
            do {
                try device.lockForConfiguration()
                Self.apply(frameRate: fps, to: device)
                device.unlockForConfiguration()
            } catch {
                // Keep the old rate; the governor will not ask twice.
            }
        }
    }

    /// Per the spec, exposure and white balance are locked once placement passes,
    /// so lighting changes don't shift the picture mid-drill.
    func lockExposureAndWhiteBalance() {
        sessionQueue.async {
            guard let device = self.device, (try? device.lockForConfiguration()) != nil else { return }
            if device.isExposureModeSupported(.locked) { device.exposureMode = .locked }
            if device.isWhiteBalanceModeSupported(.locked) { device.whiteBalanceMode = .locked }
            device.unlockForConfiguration()
        }
    }

    func unlockExposureAndWhiteBalance() {
        sessionQueue.async { self.unlockExposureAndWhiteBalanceNow() }
    }

    private func unlockExposureAndWhiteBalanceNow() {
        guard let device, (try? device.lockForConfiguration()) != nil else { return }
        if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
        if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
            device.whiteBalanceMode = .continuousAutoWhiteBalance
        }
        device.unlockForConfiguration()
    }

    // MARK: - Setup

    private func configureIfNeeded(preferredFrameRate: Int) throws -> Int {
        if isConfigured, let device {
            try device.lockForConfiguration()
            let rate = Self.apply(frameRate: preferredFrameRate, to: device)
            device.unlockForConfiguration()
            return rate
        }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            throw CaptureServiceError.noCamera
        }

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        // Leave the audio session alone. Otherwise the capture session rewrites it on start
        // and undoes AudioService's measurement mode.
        session.automaticallyConfiguresApplicationAudioSession = false

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw CaptureServiceError.setupFailed }
        session.addInput(input)

        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String:
                                    kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: videoQueue)
        guard session.canAddOutput(output) else { throw CaptureServiceError.setupFailed }
        session.addOutput(output)

        try device.lockForConfiguration()
        if let format = Self.bestFormat(for: device, frameRate: preferredFrameRate) {
            device.activeFormat = format
        }
        let rate = Self.apply(frameRate: preferredFrameRate, to: device)
        device.unlockForConfiguration()

        self.device = device
        isConfigured = true
        return rate
    }

    /// A 1080p full-range format that reaches `frameRate`, or the 1080p format with the highest rate.
    private static func bestFormat(for device: AVCaptureDevice, frameRate: Int) -> AVCaptureDevice.Format? {
        let formats = device.formats.filter { format in
            let size = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let subtype = CMFormatDescriptionGetMediaSubType(format.formatDescription)
            return size.width == 1920 && size.height == 1080
                && subtype == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        }
        func maxRate(_ format: AVCaptureDevice.Format) -> Double {
            format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
        }
        return formats.first { maxRate($0) >= Double(frameRate) } ?? formats.max { maxRate($0) < maxRate($1) }
    }

    /// Sets a fixed frame rate, capped at what the active format allows. Call with the device locked.
    @discardableResult
    private static func apply(frameRate: Int, to device: AVCaptureDevice) -> Int {
        let supported = device.activeFormat.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 30
        let rate = Int(min(Double(frameRate), supported))
        let duration = CMTime(value: 1, timescale: CMTimeScale(rate))
        device.activeVideoMinFrameDuration = duration
        device.activeVideoMaxFrameDuration = duration
        return rate
    }

    // MARK: - Frames

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        let presentation = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        // Frame times are on the session's clock; move them to the host clock the audio uses.
        let hostTime = CMSyncConvertTime(presentation, from: session.synchronizationClock ?? CMClockGetHostTimeClock(),
                                         to: CMClockGetHostTimeClock())
        onFrame?(sampleBuffer, CMTimeGetSeconds(hostTime))
    }
}
