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
    private var selectedFPS: Double?
    private var isThermalCapped = false


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
        center.addObserver(self, selector: #selector(thermalStateDidChange),
                           name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
    }

    @objc private func thermalStateDidChange(_ notification: Notification) {
        sessionQueue.async { self.applyThermalFrameRate() }
    }

    private func applyThermalFrameRate() {
        guard let device, let selectedFPS else { return }
        let state = ProcessInfo.processInfo.thermalState
        let shouldCap = state == .serious || state == .critical
        guard shouldCap != isThermalCapped else { return }
        isThermalCapped = shouldCap
        let fps = shouldCap ? min(selectedFPS, 30) : selectedFPS
        let duration = CMTime(seconds: 1.0 / fps, preferredTimescale: 60_000)
        withLock(device) { camera in
            camera.activeVideoMinFrameDuration = duration
            camera.activeVideoMaxFrameDuration = duration
        }
        #if DEBUG
        print("[Camera] Thermal \(state.rawValue): fps -> \(fps)")
        #endif
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
        report(session.isRunning ? .running : .failed)
    }

    private func configureColorAndExposure(_ device: AVCaptureDevice){
        withLock(device) { device in
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }
            
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
        }
    }
    
    private func configure() -> Bool {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device) else { return false }

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        
        if session.canSetSessionPreset(.inputPriority) {
            session.sessionPreset = .inputPriority
        } else {
            session.sessionPreset = .high
        }
        session.automaticallyConfiguresCaptureDeviceForWideColor = false

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
        configureColorAndExposure(device)
        
        self.device = device
        
        setAutoExposure()
        setAutoWhiteBalance()
        
        return true
    }

    private func configureFocus(_ device: AVCaptureDevice) {
        withLock(device) { d in
            if d.isFocusModeSupported(.continuousAutoFocus) { d.focusMode = .continuousAutoFocus }
            if d.isAutoFocusRangeRestrictionSupported { d.autoFocusRangeRestriction = .none }
            if d.isSmoothAutoFocusSupported { d.isSmoothAutoFocusEnabled = false }
            if d.isFocusPointOfInterestSupported { d.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5) }
            d.automaticallyAdjustsFaceDrivenAutoFocusEnabled = false
            d.isFaceDrivenAutoFocusEnabled = true
            d.automaticallyAdjustsFaceDrivenAutoExposureEnabled = false
            d.isFaceDrivenAutoExposureEnabled = true
        }
        enableVideoHDR(device)
    }

    private func enableVideoHDR(_ device: AVCaptureDevice) {
        guard device.activeFormat.isVideoHDRSupported else { return }
        withLock(device) { d in
            d.automaticallyAdjustsVideoHDREnabled = false
            d.isVideoHDREnabled = true
        }
    }

    private func enableStabilization(_ connection: AVCaptureConnection?, _ device: AVCaptureDevice) {
        videoConnection = connection
        guard let connection, connection.isVideoStabilizationSupported,
              device.activeFormat.isVideoStabilizationModeSupported(preferredStabilization) else { return }
        connection.preferredVideoStabilizationMode = preferredStabilization
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
        let targetFPS = min(max(Double(frameRate), 30), 60)
        let minimumFPS = 29.0

        var best: (
            format: AVCaptureDevice.Format,
            fps: Double,
            pixelCount: Int64,
            isBinned: Bool,
            hdr: Bool,
            p3: Bool,
            auto: Bool
        )?

        for format in device.formats {
            let dimensions = CMVideoFormatDescriptionGetDimensions(
                format.formatDescription
            )

            let width = dimensions.width
            let height = dimensions.height

            guard width >= 1280,
                  width <= preferredWidth else {
                continue
            }

            let supportedFPS = format.videoSupportedFrameRateRanges
                .compactMap { range -> Double? in
                    let fps = min(range.maxFrameRate, targetFPS)

                    guard fps >= minimumFPS,
                          fps >= range.minFrameRate else {
                        return nil
                    }

                    return fps
                }
                .max()

            guard let fps = supportedFPS else {
                continue
            }

            let pixelCount = Int64(width) * Int64(height)
            let auto = prefersAutoFrameRate && format.isAutoVideoFrameRateSupported

            let candidate = (
                format: format,
                fps: fps,
                pixelCount: pixelCount,
                isBinned: format.isVideoBinned,
                hdr: format.isVideoHDRSupported,
                p3: format.supportedColorSpaces.contains(.P3_D65),
                auto: auto
            )

            let better: Bool

            if let current = best {
                if candidate.pixelCount != current.pixelCount {
                    better = candidate.pixelCount > current.pixelCount
                }
                else if candidate.fps != current.fps {
                    better = candidate.fps > current.fps
                }
                else if candidate.hdr != current.hdr {
                    better = candidate.hdr
                }
                else if candidate.p3 != current.p3 {
                    better = candidate.p3
                }
                else if candidate.isBinned != current.isBinned {
                    better = !candidate.isBinned
                }
                else {
                    better = candidate.auto && !current.auto
                }
            } else {
                better = true
            }

            if better {
                best = candidate
            }
        }

        guard let best else {
            #if DEBUG
            print("[Camera] No format supports the requested 30–60 FPS range.")
            #endif
            return
        }

        let duration = CMTime(
            seconds: 1.0 / best.fps,
            preferredTimescale: 60_000
        )

        withLock(device) { camera in
            camera.activeFormat = best.format
            camera.activeColorSpace = best.p3 ? .P3_D65 : .sRGB

            if best.auto {
                camera.isAutoVideoFrameRateEnabled = true
            } else {
                camera.isAutoVideoFrameRateEnabled = false
                camera.activeVideoMinFrameDuration = duration
                camera.activeVideoMaxFrameDuration = duration
            }
        }
        selectedFPS = best.auto ? nil : best.fps
        isThermalCapped = false
        applyThermalFrameRate()

        #if DEBUG
        let actualDimensions = CMVideoFormatDescriptionGetDimensions(
            device.activeFormat.formatDescription
        )

        let actualDuration = device.activeVideoMaxFrameDuration
        let actualFPS = actualDuration.seconds > 0
            ? 1.0 / actualDuration.seconds
            : 0

        print("""
        [Camera] Selected format:
          Resolution: \(actualDimensions.width)x\(actualDimensions.height)
          Target FPS: \(best.fps)
          Active FPS limit: \(String(format: "%.2f", actualFPS))
          Binned: \(device.activeFormat.isVideoBinned)
          Auto FPS: \(best.auto)
          Video HDR supported: \(best.hdr)
          Color space: \(device.activeColorSpace == .P3_D65 ? "P3" : "sRGB")
        """)
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
