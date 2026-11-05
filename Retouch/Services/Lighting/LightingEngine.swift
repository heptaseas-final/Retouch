import AVFoundation
import Foundation

struct LightingOutput: Equatable {
    var ringLight: Double
    var screenBrightnessCap: Double
}

final class LightingEngine {
    let config: LightingConfig
    var onOutput: ((LightingOutput) -> Void)?

    private let camera: CameraSessionManager
    private let lock = NSLock()
    private var _manualPanel: Double?
    private var _needsReset = true
    private var exposureRange: CameraExposureRange?
    private var lastTime: Double?
    private var smoothedLogLux: Float?
    private var panel: Float = 0
    private var isPanelOn = false
    private var quality = Quality.full
    private var published: LightingOutput?
    private var measuredFPS: Double = 0
    private var lastLogTime = -Double.infinity

    init(camera: CameraSessionManager, config: LightingConfig) {
        self.camera = camera
        self.config = config
    }

    var manualPanel: Double? {
        get { lock.withLock { _manualPanel } }
        set { lock.withLock { _manualPanel = newValue } }
    }

    func reset() {
        lock.withLock { _needsReset = true }
    }

    func process(_ frame: CameraFrame) -> FramePipeline.Parameters {
        let (needsReset, manual) = lock.withLock { () -> (Bool, Double?) in
            defer { _needsReset = false }
            return (_needsReset, _manualPanel)
        }
        if needsReset { restart() }

        let dt = min(max(frame.time - (lastTime ?? frame.time - 1.0 / 60), 1.0 / 240), 0.25)
        lastTime = frame.time
        measuredFPS += (1 / dt - measuredFPS) * 0.1
        updateQuality(dt: dt)

        if exposureRange == nil { exposureRange = camera.exposureRange() }
        camera.setExposureBias(log2(Luma.decode(config.faceBrightness) / Luma.decode(0.5)))

        let roomLux = estimateRoomLux(frame, dt: Float(dt))
        let darkness = darkness(roomLux: roomLux, threshold: config.ringLightStartLux)
        updatePanel(roomLux: roomLux, manual: manual, dt: Float(dt))
        publish(LightingOutput(ringLight: Double(panel), screenBrightnessCap: quality.brightnessCap))
        log(frame, roomLux: roomLux)

        let noise = noiseLevel(iso: frame.iso)
        var params = FramePipeline.Parameters()
        params.noise = noise
        params.chromaDenoise = darkness
        params.spatial = 0.6 * darkness
        params.edgeSharpen = 0.8 * quality.sharpen * darkness
        params.coring = 0.008 + 0.03 * noise
        return params
    }

    private func restart() {
        camera.setAutoExposure()
        camera.setAutoWhiteBalance()
        exposureRange = nil
        lastTime = nil
        smoothedLogLux = nil
        panel = 0
        isPanelOn = false
        published = nil
    }

    private func estimateRoomLux(_ frame: CameraFrame, dt: Float) -> Float? {
        guard let range = exposureRange, frame.exposureDuration > 0, frame.iso > 0 else { return nil }
        let offset = frame.exposureTargetOffset.isFinite ? min(max(frame.exposureTargetOffset, -4), 4) : 0
        let measured = config.luxCalibration * range.aperture * range.aperture
            / (Float(frame.exposureDuration) * frame.iso) * exp2(offset)
        let panelLight = 1 + (exp2(config.panelFullEV) - 1) * panel
        let logLux = log2(max(measured / panelLight, 0.1))
        let a = 1 - exp(-dt / 0.3)
        let smoothed = smoothedLogLux.map { $0 + (logLux - $0) * a } ?? logLux
        smoothedLogLux = smoothed
        return exp2(smoothed)
    }

    private func darkness(roomLux: Float?, threshold: Float) -> Float {
        guard let lux = roomLux else { return 0 }
        return min(max(log2(threshold / max(lux, 0.1)) / 1.5, 0), 1)
    }

    private func updatePanel(roomLux: Float?, manual: Double?, dt: Float) {
        if let manual {
            panel = Float(manual)
            return
        }
        let threshold = config.ringLightStartLux * (isPanelOn ? 1.25 : 1)
        let target = darkness(roomLux: roomLux, threshold: threshold) * quality.panelCap
        isPanelOn = target > 0.02
        let tau = Float(config.ringLightFadeTime) * (target > panel ? 1 : 2)
        panel += (target - panel) * (1 - exp(-dt / tau))
    }

    private func noiseLevel(iso: Float) -> Float {
        guard let range = exposureRange else { return 0 }
        let minISO = max(range.minISO, 1)
        let cap = max(range.maxISO * 0.5, minISO * 1.01)
        return min(max(log2(max(iso, minISO) / minISO) / log2(cap / minISO), 0), 1)
    }

    private func updateQuality(dt: TimeInterval) {
        let target = Quality.target(for: ProcessInfo.processInfo.thermalState)
        let a = Float(1 - exp(-dt / 2))
        quality.sharpen += (target.sharpen - quality.sharpen) * a
        quality.panelCap += (target.panelCap - quality.panelCap) * a
        quality.brightnessCap += (target.brightnessCap - quality.brightnessCap) * Double(a)
    }

    private func publish(_ output: LightingOutput) {
        if let published,
           abs(published.ringLight - output.ringLight) < 0.003,
           abs(published.screenBrightnessCap - output.screenBrightnessCap) < 0.01 {
            return
        }
        published = output
        DispatchQueue.main.async { [weak self] in self?.onOutput?(output) }
    }

    private func log(_ frame: CameraFrame, roomLux: Float?) {
        #if DEBUG
        guard LightingDebug.isLoggingEnabled, frame.time - lastLogTime >= 0.5 else { return }
        lastLogTime = frame.time
        print(String(format: "[Lighting] fps=%.0f iso=%.0f dur=1/%.0f offset=%.2f roomLux=%.0f ring=%.2f",
                     measuredFPS, frame.iso, 1 / max(frame.exposureDuration, 1e-6),
                     frame.exposureTargetOffset, roomLux ?? -1, panel))
        #endif
    }

    private struct Quality {
        var sharpen: Float
        var panelCap: Float
        var brightnessCap: Double

        static let full = Quality(sharpen: 1, panelCap: 1, brightnessCap: 1)

        static func target(for state: ProcessInfo.ThermalState) -> Quality {
            switch state {
            case .nominal: .full
            case .fair: Quality(sharpen: 0, panelCap: 1, brightnessCap: 1)
            case .serious: Quality(sharpen: 0, panelCap: 0.7, brightnessCap: 0.6)
            case .critical: Quality(sharpen: 0, panelCap: 0.3, brightnessCap: 0.5)
            @unknown default: .full
            }
        }
    }
}
