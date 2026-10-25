import AVFoundation

/// One light reading taken from a sampled frame.
struct LightSample {
    /// Auto exposure state, for `LightMeter` (PRD Epic 2).
    var iso: Double
    var exposureDuration: Double
    var aperture: Double
    /// EV the image sits away from what auto exposure aimed for (negative = darker).
    var exposureTargetOffset: Double
    /// White balance the camera is applying right now.
    var current: WhiteBalance?
    /// White balance a gray-world estimate suggests for this frame. Unlike the
    /// camera's own auto WB, this keeps updating while WB is locked.
    var grayWorld: WhiteBalance?
}

/// Owns the front-camera session (PRD Epic 1, SDD §4.1): permission, setup,
/// interruptions and reconnect. Reports a light sample from each sampled frame.
///
/// Frames never leave this class except to be drawn: only a few numbers are
/// forwarded, and nothing is written to disk or sent over the network.
final class CameraSessionManager: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()

    /// Called on the main queue for each sampled frame.
    var onLightSample: ((LightSample) -> Void)?
    /// Called on the frame queue with every frame, in sensor orientation, for display.
    var onFrame: ((CVPixelBuffer) -> Void)?
    /// Called on the main queue.
    var onStateChange: ((CameraState) -> Void)?

    /// Analysis runs at most this often; the preview itself is unaffected.
    var sampleInterval: CFTimeInterval = 0.1
    /// Fixed preview frame rate. Without it, auto exposure lowers the frame
    /// rate in dim rooms and the mirror stutters.
    var frameRate: Int32 = 30
    /// Time constant of the white balance glide, in seconds.
    var whiteBalanceGlide: Double = 0.35
    /// Restart attempts after a runtime error before reporting `.failed`.
    var maxRestartAttempts = 3

    private let sessionQueue = DispatchQueue(label: "autolight.camera.session")
    private let analysisQueue = DispatchQueue(label: "autolight.camera.analysis", qos: .userInitiated)
    private var device: AVCaptureDevice?
    private var lastSampleTime: CFTimeInterval = 0

    // Owned by sessionQueue.
    private var isConfigured = false
    private var wantsRunning = false
    private var restartAttempts = 0

    // Owned by analysisQueue.
    private var appliedGains: AVCaptureDevice.WhiteBalanceGains?
    private var targetGains: AVCaptureDevice.WhiteBalanceGains?
    private var lastGlideTime: CFTimeInterval = 0

    override init() {
        super.init()
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(sessionDidStart),
                           name: AVCaptureSession.didStartRunningNotification, object: session)
        center.addObserver(self, selector: #selector(sessionWasInterrupted),
                           name: AVCaptureSession.wasInterruptedNotification, object: session)
        center.addObserver(self, selector: #selector(sessionInterruptionEnded),
                           name: AVCaptureSession.interruptionEndedNotification, object: session)
        center.addObserver(self, selector: #selector(sessionRuntimeError),
                           name: AVCaptureSession.runtimeErrorNotification, object: session)
    }

    // MARK: - Lifecycle

    /// Checks permission every time, so returning from Settings with access
    /// granted starts the camera without restarting the app.
    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            sessionQueue.async { self.configureAndRun() }
        case .notDetermined:
            report(.notDetermined)
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    self.sessionQueue.async { self.configureAndRun() }
                } else {
                    self.report(.permissionDenied)
                }
            }
        default:
            report(.permissionDenied)
        }
    }

    /// `state`: `.idle` when the host stops the mirror, `.reconnecting` when
    /// the app goes to background and will come back.
    func stop(reportAs state: CameraState = .idle) {
        sessionQueue.async {
            self.wantsRunning = false
            if self.session.isRunning { self.session.stopRunning() }
            self.report(state)
        }
    }

    /// Builds the session again from nothing, for the "try again" button.
    func retry() {
        sessionQueue.async {
            self.session.beginConfiguration()
            self.session.inputs.forEach(self.session.removeInput)
            self.session.outputs.forEach(self.session.removeOutput)
            self.session.commitConfiguration()
            self.isConfigured = false
        }
        start()
    }

    private func configureAndRun() {
        wantsRunning = true
        restartAttempts = 0
        if !isConfigured {
            report(.starting)
            guard configure() else { report(.failed); return }
            isConfigured = true
        }
        if !session.isRunning { session.startRunning() }
        report(session.isRunning ? .running : .failed)
    }

    private func configure() -> Bool {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device) else { return false }

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .high

        guard session.canAddInput(input) else { return false }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: analysisQueue)
        guard session.canAddOutput(output) else { return false }
        session.addOutput(output)
        // Frames are left in sensor orientation (landscape); MirrorRenderer
        // turns them into an upright mirror itself, so the result never
        // depends on connection settings that iOS may not apply.

        lockFrameRate(device)
        self.device = device
        return true
    }

    private func lockFrameRate(_ device: AVCaptureDevice) {
        let supported = device.activeFormat.videoSupportedFrameRateRanges.contains {
            $0.minFrameRate <= Double(frameRate) && Double(frameRate) <= $0.maxFrameRate
        }
        guard supported else { return }
        let duration = CMTime(value: 1, timescale: frameRate)
        withLock(device) {
            $0.activeVideoMinFrameDuration = duration
            $0.activeVideoMaxFrameDuration = duration
        }
    }

    private func report(_ state: CameraState) {
        DispatchQueue.main.async { self.onStateChange?(state) }
    }

    // MARK: - Interruptions (PRD Epic 1, Negative 3)

    @objc private func sessionDidStart(_ notification: Notification) {
        sessionQueue.async { if self.wantsRunning { self.report(.running) } }
    }

    /// Incoming call, another app taking the camera, Split View, …
    /// The session resumes by itself once the interruption ends.
    @objc private func sessionWasInterrupted(_ notification: Notification) {
        sessionQueue.async { if self.wantsRunning { self.report(.reconnecting) } }
    }

    @objc private func sessionInterruptionEnded(_ notification: Notification) {
        sessionQueue.async {
            guard self.wantsRunning else { return }
            if !self.session.isRunning { self.session.startRunning() }
            self.report(self.session.isRunning ? .running : .reconnecting)
        }
    }

    /// E.g. media services were reset. Restarts the session a few times, a
    /// second apart, before giving up.
    @objc private func sessionRuntimeError(_ notification: Notification) {
        sessionQueue.async {
            guard self.wantsRunning else { return }
            self.report(.reconnecting)
            self.restartAfterError()
        }
    }

    private func restartAfterError() {
        guard wantsRunning else { return }
        guard restartAttempts < maxRestartAttempts else { report(.failed); return }
        restartAttempts += 1
        sessionQueue.asyncAfter(deadline: .now() + 1) {
            guard self.wantsRunning else { return }
            self.session.startRunning()
            if self.session.isRunning {
                self.restartAttempts = 0
                self.report(.running)
            } else {
                self.restartAfterError()
            }
        }
    }

    // MARK: - White balance (PRD Epic 4)

    /// Hands white balance back to the camera's continuous auto mode.
    func useAutoWhiteBalance() {
        analysisQueue.async {
            self.targetGains = nil
            self.appliedGains = nil
            guard let device = self.device,
                  device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) else { return }
            self.withLock(device) { $0.whiteBalanceMode = .continuousAutoWhiteBalance }
        }
    }

    /// Takes manual control of white balance and glides to `target` over a
    /// fraction of a second instead of jumping, so skin colour never snaps.
    func glideWhiteBalance(to target: WhiteBalance) {
        analysisQueue.async {
            guard let device = self.device, device.isLockingWhiteBalanceWithCustomDeviceGainsSupported else { return }
            let values = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(
                temperature: Float(target.temperature), tint: Float(target.tint))
            self.targetGains = Self.clamp(device.deviceWhiteBalanceGains(for: values), device)
            if self.appliedGains == nil {
                self.appliedGains = device.deviceWhiteBalanceGains
                self.lastGlideTime = CACurrentMediaTime()
            }
        }
    }

    /// Runs on every frame (analysisQueue) while a glide is in progress.
    private func stepWhiteBalanceGlide(_ device: AVCaptureDevice) {
        guard let target = targetGains, var gains = appliedGains else { return }
        let now = CACurrentMediaTime()
        let k = Float(1 - exp(-(now - lastGlideTime) / whiteBalanceGlide))
        lastGlideTime = now

        gains.redGain += (target.redGain - gains.redGain) * k
        gains.greenGain += (target.greenGain - gains.greenGain) * k
        gains.blueGain += (target.blueGain - gains.blueGain) * k
        let remaining = max(abs(target.redGain - gains.redGain),
                            abs(target.greenGain - gains.greenGain),
                            abs(target.blueGain - gains.blueGain))
        let finished = remaining < 0.002
        if finished { gains = target }

        // Skip the device call when nothing visible would change.
        if !finished, let applied = appliedGains,
           max(abs(gains.redGain - applied.redGain), abs(gains.blueGain - applied.blueGain)) < 0.001 {
            return
        }
        appliedGains = gains
        if finished { targetGains = nil }
        let clamped = Self.clamp(gains, device)
        withLock(device) { $0.setWhiteBalanceModeLocked(with: clamped, completionHandler: nil) }
    }

    private static func clamp(_ gains: AVCaptureDevice.WhiteBalanceGains,
                              _ device: AVCaptureDevice) -> AVCaptureDevice.WhiteBalanceGains {
        let maxGain = device.maxWhiteBalanceGain
        func c(_ g: Float) -> Float { min(max(g, 1), maxGain) }
        return .init(redGain: c(gains.redGain), greenGain: c(gains.greenGain), blueGain: c(gains.blueGain))
    }

    private func withLock(_ device: AVCaptureDevice, _ body: (AVCaptureDevice) -> Void) {
        do {
            try device.lockForConfiguration()
            body(device)
            device.unlockForConfiguration()
        } catch {
            print("Camera configuration failed: \(error)")
        }
    }

    // MARK: - Frame sampling

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let device else { return }
        stepWhiteBalanceGlide(device)
        if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) { onFrame?(pixelBuffer) }

        let now = CACurrentMediaTime()
        guard now - lastSampleTime >= sampleInterval else { return }
        lastSampleTime = now

        let sample = LightSample(iso: Double(device.iso),
                                 exposureDuration: device.exposureDuration.seconds,
                                 aperture: Double(device.lensAperture),
                                 exposureTargetOffset: Double(device.exposureTargetOffset),
                                 current: Self.whiteBalance(device.deviceWhiteBalanceGains, device),
                                 grayWorld: Self.whiteBalance(device.grayWorldDeviceWhiteBalanceGains, device))
        DispatchQueue.main.async { self.onLightSample?(sample) }
    }

    private static func whiteBalance(_ gains: AVCaptureDevice.WhiteBalanceGains,
                                     _ device: AVCaptureDevice) -> WhiteBalance? {
        guard gains.redGain >= 1, gains.greenGain >= 1, gains.blueGain >= 1 else { return nil }
        let values = device.temperatureAndTintValues(for: clamp(gains, device))
        return WhiteBalance(temperature: Double(values.temperature), tint: Double(values.tint))
    }
}
