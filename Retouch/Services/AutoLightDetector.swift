import Observation
import UIKit

@MainActor
@Observable
final class AutoLightDetector {
    private(set) var cameraState: CameraState = .idle
    private(set) var appliedBrightness: Double = 0
    private(set) var manualBrightness: Double?
    private(set) var filterColor: ManualColorChoice?
    private(set) var ringLightLevel: Double = 0

    @ObservationIgnored let config = LightingConfig()
    @ObservationIgnored let pipeline: FramePipeline
    @ObservationIgnored var renderer: MirrorRenderer { pipeline.renderer }
    @ObservationIgnored var frameForwarder: FrameForwarder { pipeline.vision }

    @ObservationIgnored private let camera = CameraSessionManager()
    @ObservationIgnored private let brightness = BrightnessController()
    @ObservationIgnored private let engine: LightingEngine
    @ObservationIgnored private var autoRingLight = 0.0
    @ObservationIgnored private var brightnessCap = 1.0
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var isAppActive = UIApplication.shared.applicationState == .active
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init() {
        camera.prefersAutoFrameRate = config.autoFrameRateInDark
        engine = LightingEngine(camera: camera, config: config)
        pipeline = FramePipeline(lighting: engine)
        appliedBrightness = Self.roundedPercent(brightness.current)

        brightness.onChange = { [weak self] value in
            guard let self else { return }
            let rounded = Self.roundedPercent(value)
            if rounded != appliedBrightness { appliedBrightness = rounded }
        }
        camera.onStateChange = { [weak self] in self?.cameraStateChanged($0) }
        camera.onFrame = { [pipeline] frame in pipeline.process(frame) }
        engine.onOutput = { [weak self] in self?.engineDidUpdate($0) }

        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.resignActive() }
            },
            center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.becomeActive() }
            },
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.enterBackground() }
            },
            center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.enterForeground() }
            },
        ]
    }

    func start() {
        guard !(isStarted && cameraState == .running) else { return }
        isStarted = true
        UIApplication.shared.isIdleTimerDisabled = true
        brightness.captureBaseline()
        camera.start()
    }

    func stop() {
        isStarted = false
        UIApplication.shared.isIdleTimerDisabled = false
        camera.stop()
        pauseAdjustments()
        brightness.restoreBaseline()
    }

    func retryCameraSetup() {
        guard isStarted else { return start() }
        camera.retry()
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func setManualBrightness(_ level: Double) {
        manualBrightness = min(max(level, 0), 1)
        applyBrightness()
    }

    func setFilterColor(_ choice: ManualColorChoice) {
        filterColor = choice
    }

    func resetToAuto() {
        manualBrightness = nil
        filterColor = nil
        applyBrightness()
    }

    // MARK: - Lifecycle

    private func resignActive() {
        isAppActive = false
        guard isStarted else { return }
        brightness.restoreBaseline()
        ringLightLevel = 0
    }

    private func becomeActive() {
        isAppActive = true
        guard isStarted else { return }
        applyBrightness()
    }

    private func enterBackground() {
        guard isStarted else { return }
        UIApplication.shared.isIdleTimerDisabled = false
        camera.stop(reportAs: .reconnecting)
        pauseAdjustments()
        brightness.restoreBaseline()
    }

    private func enterForeground() {
        guard isStarted else { return }
        start()
    }

    private func cameraStateChanged(_ state: CameraState) {
        let wasRunning = cameraState == .running
        cameraState = state
        if state == .running, !wasRunning {
            resumeFromScratch()
        } else if state != .running, wasRunning {
            pauseAdjustments()
            if isStarted { brightness.ramp(to: brightness.baseline) }
        }
    }

    private func pauseAdjustments() {
        engine.reset()
        autoRingLight = 0
        ringLightLevel = 0
    }

    private func resumeFromScratch() {
        pauseAdjustments()
        applyBrightness()
    }

    // MARK: - Lighting

    private func engineDidUpdate(_ output: LightingOutput) {
        guard isStarted, cameraState == .running else { return }
        autoRingLight = output.ringLight
        brightnessCap = output.screenBrightnessCap
        if manualBrightness == nil { applyAutoLight() }
    }

    private func applyBrightness() {
        guard isAppActive else { return }
        if let manualBrightness {
            brightness.set(manualBrightness)
            let baseline = Double(brightness.baseline)
            let level = baseline >= 0.98
                ? (manualBrightness >= 0.98 ? 1 : 0)
                : min(max((manualBrightness - baseline) / (1 - baseline), 0), 1)
            ringLightLevel = level
            engine.manualPanel = level
        } else {
            engine.manualPanel = nil
            applyAutoLight()
        }
    }

    private func applyAutoLight() {
        guard isAppActive else { return }
        if ringLightLevel != autoRingLight { ringLightLevel = autoRingLight }
        let baseline = Double(brightness.baseline)
        let pre = Double(max(config.panelPreRampFraction, 0.01))
        let t = min(max(autoRingLight / pre, 0), 1)
        let target = baseline + (1 - baseline) * t * t * (3 - 2 * t)
        brightness.ramp(to: CGFloat(min(target, max(baseline, brightnessCap))))
    }

    private static func roundedPercent(_ value: CGFloat) -> Double {
        (Double(value) * 100).rounded() / 100
    }
}
