//
//  CameraSessionManager.swift
//  Retouch
//
//  Created by Davin P on 26/10/26.
//

import AVFoundation
import ImageIO

struct CameraFrame {
    let pixelBuffer: CVPixelBuffer
    let time: Double
    let exposureDuration: Double
    let iso: Float
    let exposureTargetOffset: Float
}

struct CameraExposureRange {
    var minISO: Float
    var maxISO: Float
    var aperture: Float
}

final class CameraSessionManager: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    var onFrame: ((CameraFrame) -> Void)?
    var onStateChange: ((CameraState) -> Void)?
    var frameRate: Int32 = 60
    var prefersAutoFrameRate = false
    /// Lebar frame yang dicari (4K). Frame lebih besar dari layar lalu dikecilkan oleh renderer:
    /// lebih tajam dan noise sensor ikut dirata-rata, tanpa delay.
    var preferredWidth: Int32 = 3840
    var maxRestartAttempts = 3
    var preferredStabilization: AVCaptureVideoStabilizationMode = .off

    private let sessionQueue = DispatchQueue(label: "autolight.camera.session")
    private let analysisQueue = DispatchQueue(label: "autolight.camera.analysis", qos: .userInitiated)
    private var device: AVCaptureDevice?
    private var videoConnection: AVCaptureConnection?

    private var isConfigured = false
    private var wantsRunning = false
    private var restartAttempts = 0


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

    func stop(reportAs state: CameraState = .idle) {
        sessionQueue.async {
            self.wantsRunning = false
            if self.session.isRunning { self.session.stopRunning() }
            self.report(state)
        }
    }

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
        updateStabilizationState()
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
        enableStabilization(output.connection(with: .video), device)

        lockFrameRate(device)
        configureFocus(device)
        self.device = device
        return true
    }

    private func configureFocus(_ device: AVCaptureDevice) {
        withLock(device) { d in
            if d.isFocusModeSupported(.continuousAutoFocus) { d.focusMode = .continuousAutoFocus }
            if d.isAutoFocusRangeRestrictionSupported { d.autoFocusRangeRestriction = .none }
            if d.isSmoothAutoFocusSupported { d.isSmoothAutoFocusEnabled = false }
            if d.isFocusPointOfInterestSupported { d.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5) }
        }
        #if DEBUG
        print("[Camera] focus autofocus=\(device.isFocusModeSupported(.continuousAutoFocus)) "
              + "minimumFocusDistance=\(device.minimumFocusDistance)mm "
              + "nearRange=\(device.isAutoFocusRangeRestrictionSupported)")
        #endif
    }

    private func enableStabilization(_ connection: AVCaptureConnection?, _ device: AVCaptureDevice) {
        videoConnection = connection
        guard let connection, connection.isVideoStabilizationSupported,
              device.activeFormat.isVideoStabilizationModeSupported(preferredStabilization) else { return }
        connection.preferredVideoStabilizationMode = preferredStabilization
    }

    private func updateStabilizationState() {
        #if DEBUG
        let active = videoConnection?.activeVideoStabilizationMode ?? .off
        print("[Camera] stabilization preferred=\(Self.name(preferredStabilization)) active=\(Self.name(active))")
        #endif
    }

    private static func name(_ mode: AVCaptureVideoStabilizationMode) -> String {
        switch mode {
        case .off: "off"
        case .standard: "standard"
        case .cinematic: "cinematic"
        case .cinematicExtended: "cinematicExtended"
        case .previewOptimized: "previewOptimized"
        case .cinematicExtendedEnhanced: "cinematicExtendedEnhanced"
        case .lowLatency: "lowLatency"
        case .auto: "auto"
        @unknown default: "unknown(\(mode.rawValue))"
        }
    }

    private func lockFrameRate(_ device: AVCaptureDevice) {
        var best: (format: AVCaptureDevice.Format, fps: Double, widthGap: Int32, auto: Bool)?
        for format in device.formats {
            let width = CMVideoFormatDescriptionGetDimensions(format.formatDescription).width
            guard width >= 1280, width <= preferredWidth else { continue }
            let maxFps = format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
            let fps = min(maxFps, Double(frameRate))
            let gap = preferredWidth - width
            let auto = prefersAutoFrameRate && format.isAutoVideoFrameRateSupported
            let better: Bool
            if let best {
                if fps != best.fps { better = fps > best.fps }
                else if gap != best.widthGap { better = gap < best.widthGap }
                else if auto != best.auto { better = auto }
                else { better = !format.isVideoBinned && best.format.isVideoBinned }
            } else {
                better = true
            }
            if better { best = (format, fps, gap, auto) }
        }
        guard let best else { return }
        let duration = CMTime(value: 1, timescale: Int32(best.fps))
        withLock(device) {
            $0.activeFormat = best.format
            if best.auto {
                $0.isAutoVideoFrameRateEnabled = true
            } else {
                $0.activeVideoMinFrameDuration = duration
                $0.activeVideoMaxFrameDuration = duration
            }
        }
        #if DEBUG
        let dims = CMVideoFormatDescriptionGetDimensions(best.format.formatDescription)
        print("[Camera] format \(dims.width)x\(dims.height) fps=\(best.fps) autoFrameRate=\(best.auto) "
              + "binned=\(best.format.isVideoBinned)")
        #endif
    }

    private func report(_ state: CameraState) {
        DispatchQueue.main.async { self.onStateChange?(state) }
    }

    @objc private func sessionDidStart(_ notification: Notification) {
        sessionQueue.async { if self.wantsRunning { self.report(.running) } }
    }

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
    
    func setAutoExposure() {
        guard let device, device.isExposureModeSupported(.continuousAutoExposure) else { return }
        withLock(device) { $0.exposureMode = .continuousAutoExposure }
    }

    func setAutoWhiteBalance() {
        guard let device, device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) else { return }
        withLock(device) { $0.whiteBalanceMode = .continuousAutoWhiteBalance }
    }

    func setExposureBias(_ ev: Float) {
        guard let device else { return }
        let bias = min(max(ev, device.minExposureTargetBias), device.maxExposureTargetBias)
        guard abs(device.exposureTargetBias - bias) > 0.01 else { return }
        withLock(device) { $0.setExposureTargetBias(bias, completionHandler: nil) }
    }

    func exposureRange() -> CameraExposureRange? {
        guard let device else { return nil }
        let format = device.activeFormat
        return CameraExposureRange(minISO: format.minISO, maxISO: format.maxISO, aperture: device.lensAperture)
    }

    private func withLock(_ device: AVCaptureDevice, _ body: (AVCaptureDevice) -> Void) {
        do {
            try device.lockForConfiguration()
            body(device)
            device.unlockForConfiguration()
        } catch {
            //print("Camera configuration failed: \(error)")
        }
    }

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let device, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        let exposure = Self.exposure(of: sampleBuffer) ?? (device.exposureDuration.seconds, device.iso)
        onFrame?(CameraFrame(pixelBuffer: pixelBuffer, time: time,
                             exposureDuration: exposure.duration, iso: exposure.iso,
                             exposureTargetOffset: device.exposureTargetOffset))
    }

    private static func exposure(of sampleBuffer: CMSampleBuffer) -> (duration: Double, iso: Float)? {
        guard let exif = CMGetAttachment(sampleBuffer, key: kCGImagePropertyExifDictionary,
                                         attachmentModeOut: nil) as? [String: Any],
              let duration = (exif[kCGImagePropertyExifExposureTime as String] as? NSNumber)?.doubleValue,
              let iso = (exif[kCGImagePropertyExifISOSpeedRatings as String] as? [NSNumber])?.first?.floatValue,
              duration > 0, iso > 0 else { return nil }
        return (duration, iso)
    }
}
