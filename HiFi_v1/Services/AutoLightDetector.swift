import Observation
import UIKit

/// Auto Light Detector service (PRD; SDD §4.5 LightingController and §5 interface).
///
/// Wires camera → light meter → classifier → brightness / edge light / white
/// balance. Everything adapts to the room on its own; the host UI reads the
/// state below, places a `MirrorPreview`, and calls the methods. It handles
/// app background/foreground itself.
///
/// Pipeline per sample (10×/s):
///
///     ISO, exposure, aperture ─► LightMeter (lux, smoothed)
///         ─► DimLightCompensation.roomLux (screen's own light taken out)
///         ─► LightConditionClassifier (hysteresis + 0.5 s debounce) ─► lightCondition
///         ─► DimLightCompensation.level ─► screen brightness + edge light
///     WB gains + face visible ─► ColorTemperatureTracker ─► camera white balance
@MainActor
@Observable
final class AutoLightDetector {
    // MARK: State for the UI

    private(set) var cameraState: CameraState = .idle
    /// Committed room condition; nil until the first reading has held for the debounce window.
    private(set) var lightCondition: LightCondition?
    /// Room light with the screen's own light taken out, in estimated lux.
    private(set) var roomLux: Double?
    /// Lux as the camera measures it, screen light included (for debugging).
    private(set) var measuredLux: Double?
    /// Colour temperature of the room light as currently judged.
    private(set) var roomKelvin: Double?
    /// Strength of dim-light compensation, 0 (off) to 1.
    private(set) var dimLightLevel: Double = 0
    private(set) var isFaceVisible = false
    /// Screen brightness as applied, rounded to whole percent so the UI redraws
    /// only when a label would change.
    private(set) var appliedBrightness: Double = 0
    /// Non-nil while the user has taken over that dimension (PRD Epic 5).
    private(set) var manualBrightness: Double?
    private(set) var manualColor: ManualColorChoice?

    /// Colour temperature the face is shown as if lit by: Natural unless the user picked otherwise.
    var targetColorKelvin: Double { (manualColor ?? .natural).appearanceKelvin }

    // MARK: Tuning

    /// Below this room light, white balance is handed to Apple's face-aware
    /// auto WB. There the gray-world estimate is mostly sensor noise and
    /// pushes the face red. Leaves again above twice this.
    @ObservationIgnored var appleWhiteBalanceBelowLux = 30.0
    /// Readings are ignored this long after the camera (re)starts, while auto
    /// exposure is still settling and its values don't describe the room yet.
    @ObservationIgnored var warmUpTime: TimeInterval = 0.7

    // MARK: Components

    @ObservationIgnored let renderer: MirrorRenderer
    @ObservationIgnored private let camera = CameraSessionManager()
    @ObservationIgnored private let faceTracker = FaceTracker()
    @ObservationIgnored private let brightness = BrightnessController()
    @ObservationIgnored private var meter = LightMeter()
    @ObservationIgnored private var classifier = LightConditionClassifier()
    @ObservationIgnored private var compensation = DimLightCompensation()
    @ObservationIgnored private var colorTracker = ColorTemperatureTracker()
    @ObservationIgnored private var usesAppleWhiteBalance = false
    /// Room light the manual colour is applied on top of; frozen while manual.
    @ObservationIgnored private var manualColorBase: WhiteBalance?
    @ObservationIgnored private var lastRoomBalance: WhiteBalance?
    @ObservationIgnored private var isStarted = false
    /// False while the app is inactive (app switcher, Control Center, lock):
    /// the screen then stays at the user's own brightness.
    @ObservationIgnored private var isAppActive = UIApplication.shared.applicationState == .active
    @ObservationIgnored private var runningSince = Date.distantPast
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init() {
        renderer = MirrorRenderer(faceTracker: faceTracker)
        compensation.thresholdLux = classifier.thresholds.darkBelow
        appliedBrightness = Self.roundedPercent(brightness.current)

        brightness.onChange = { [weak self] value in
            guard let self else { return }
            let rounded = Self.roundedPercent(value)
            if rounded != appliedBrightness { appliedBrightness = rounded }
        }
        camera.onStateChange = { [weak self] in self?.cameraStateChanged($0) }
        camera.onLightSample = { [weak self] in self?.ingest($0) }
        camera.onFrame = { [renderer] in renderer.render($0) }

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

    // MARK: Control surface (SDD §5)

    /// Starts the mirror: asks for camera permission if needed, records the
    /// current screen brightness as the baseline, and keeps the screen awake.
    func start() {
        // Already running: re-reading the baseline now would pick up our own boost.
        guard !(isStarted && cameraState == .running) else { return }
        isStarted = true
        UIApplication.shared.isIdleTimerDisabled = true
        brightness.captureBaseline()
        camera.start()
    }

    /// Stops the mirror and gives the user's brightness back.
    func stop() {
        isStarted = false
        UIApplication.shared.isIdleTimerDisabled = false
        camera.stop()
        pauseAdjustments()
        brightness.restoreBaseline()
    }

    /// For the "try again" button after `.failed`.
    func retryCameraSetup() {
        guard isStarted else { return start() }
        camera.retry()
    }

    /// For the button shown with `.permissionDenied`.
    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// Fixes screen brightness at `level` (0…1); brightness and edge light stop adapting.
    func setManualBrightness(_ level: Double) {
        manualBrightness = min(max(level, 0), 1)
        applyBrightness()
    }

    /// Shows the face as if lit by `choice`, based on the room light right now;
    /// colour stops adapting to the room.
    func setManualColor(_ choice: ManualColorChoice) {
        manualColor = choice
        if manualColorBase == nil { manualColorBase = lastRoomBalance }
        applyManualColor()
    }

    /// Clears both overrides and adapts again from the current room condition.
    func resetToAuto() {
        manualBrightness = nil
        manualColor = nil
        manualColorBase = nil
        applyBrightness()
        restartColorAdaptation()
    }

    // MARK: Lifecycle

    /// Gives the brightness back as soon as the app starts leaving. By
    /// `didEnterBackground` iOS may no longer apply it, and an app swiped
    /// away in the app switcher gets no later callback at all.
    private func resignActive() {
        isAppActive = false
        guard isStarted else { return }
        brightness.restoreBaseline()
        renderer.targetLevel = 0
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
        meter.reset()
        classifier.reset()
        compensation.reset()
        faceTracker.reset()
        lightCondition = nil
        roomLux = nil
        measuredLux = nil
        isFaceVisible = false
        dimLightLevel = 0
        renderer.targetLevel = 0
    }

    /// After (re)connecting, readings start from scratch (Scenario 2.1.3).
    private func resumeFromScratch() {
        pauseAdjustments()
        runningSince = .now
        usesAppleWhiteBalance = false
        applyBrightness()
        if manualColor != nil, manualColorBase != nil {
            applyManualColor()
        } else {
            restartColorAdaptation()
        }
    }

    // MARK: Adaptive logic

    private func ingest(_ sample: LightSample) {
        guard cameraState == .running, Date.now.timeIntervalSince(runningSince) >= warmUpTime else { return }
        let faceVisible = faceTracker.isFaceVisible
        if faceVisible != isFaceVisible { isFaceVisible = faceVisible }

        guard let lux = meter.ingest(sample) else { return }
        let room = compensation.roomLux(from: lux)
        measuredLux = lux
        roomLux = room
        classifier.ingest(room)
        if classifier.condition != lightCondition { lightCondition = classifier.condition }

        if compensation.update(lux: lux, isDark: classifier.condition == .dark) {
            dimLightLevel = compensation.level
            applyBrightness()
        }
        updateColor(sample, roomLux: room)
    }

    /// Auto: baseline in medium/bright rooms, rising proportionally toward
    /// full brightness as the room gets darker (SDD §4.5).
    private func applyBrightness() {
        guard isAppActive else { return }
        if let manualBrightness {
            brightness.set(manualBrightness)
            renderer.targetLevel = 0
        } else {
            let baseline = Double(brightness.baseline)
            brightness.ramp(to: baseline + dimLightLevel * (1 - baseline))
            renderer.targetLevel = dimLightLevel
        }
    }

    private func updateColor(_ sample: LightSample, roomLux: Double) {
        if manualColor != nil {
            // Picked before the first reading: use the camera's auto WB as the room light.
            if manualColorBase == nil, let current = sample.current {
                manualColorBase = current
                applyManualColor()
            }
            return
        }

        let veryDark = roomLux < appleWhiteBalanceBelowLux * (usesAppleWhiteBalance ? 2 : 1)
        if veryDark != usesAppleWhiteBalance {
            usesAppleWhiteBalance = veryDark
            // Back in the light, recalibrate from wherever auto WB ended up, so there is no jump.
            restartColorAdaptation()
        }

        if usesAppleWhiteBalance {
            lastRoomBalance = sample.current
        } else {
            if let room = colorTracker.update(current: sample.current, grayWorld: sample.grayWorld,
                                              isFaceVisible: isFaceVisible) {
                camera.glideWhiteBalance(to: room.rendered(asIfLitBy: targetColorKelvin))
            }
            lastRoomBalance = colorTracker.roomBalance ?? sample.current
        }
        roomKelvin = lastRoomBalance?.temperature
    }

    private func applyManualColor() {
        guard let manualColorBase else { return }
        camera.glideWhiteBalance(to: manualColorBase.rendered(asIfLitBy: targetColorKelvin))
    }

    private func restartColorAdaptation() {
        colorTracker.reset()
        camera.useAutoWhiteBalance()
    }

    private static func roundedPercent(_ value: CGFloat) -> Double {
        (Double(value) * 100).rounded() / 100
    }
}
