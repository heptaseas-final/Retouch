import CoreImage
import Observation
import UIKit

@MainActor
@Observable
final class AutoLightDetector {
    private(set) var cameraState: CameraState = .idle
    private(set) var lightCondition: LightCondition?
    private(set) var roomLux: Double?
    private(set) var measuredLux: Double?
    private(set) var roomKelvin: Double?
    private(set) var dimLightLevel: Double = 0
    private(set) var isLowLight = false
    private(set) var isFaceVisible = false
    private(set) var appliedBrightness: Double = 0
    private(set) var manualBrightness: Double?
    private(set) var manualColor: ManualColorChoice?
    private(set) var filterColor: ManualColorChoice?

    var targetColorKelvin: Double { (manualColor ?? .natural).appearanceKelvin }

    @ObservationIgnored var appleWhiteBalanceBelowLux = 30.0
    @ObservationIgnored var warmUpTime: TimeInterval = 0.7

    @ObservationIgnored let renderer: MirrorRenderer
    @ObservationIgnored let frameForwarder = FrameForwarder()
    @ObservationIgnored private let camera = CameraSessionManager()
    @ObservationIgnored private let faceTracker = FaceTracker()
    @ObservationIgnored private let brightness = BrightnessController()
    @ObservationIgnored private var meter = LightMeter()
    @ObservationIgnored private var classifier = LightConditionClassifier()
    @ObservationIgnored private var compensation = DimLightCompensation()
    @ObservationIgnored private var colorTracker = ColorTemperatureTracker()
    @ObservationIgnored private var usesAppleWhiteBalance = false
    @ObservationIgnored private var manualColorBase: WhiteBalance?
    @ObservationIgnored private var lastRoomBalance: WhiteBalance?
    @ObservationIgnored private var isStarted = false
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
        camera.onFrame = { [renderer, frameForwarder] in
            renderer.render($0)
            frameForwarder.send($0)
        }

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

    func setManualColor(_ choice: ManualColorChoice) {
        manualColor = choice
        if manualColorBase == nil { manualColorBase = lastRoomBalance }
        applyManualColor()
    }

    func setFilterColor(_ choice: ManualColorChoice) {
        filterColor = choice
        renderer.flashColor = Self.edgeLightColor(for: choice)
    }

    func resetToAuto() {
        manualBrightness = nil
        manualColor = nil
        filterColor = nil
        renderer.flashColor = Self.edgeLightColor(for: .natural)
        manualColorBase = nil
        applyBrightness()
        restartColorAdaptation()
    }

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
        isLowLight = false
        renderer.targetLevel = 0
    }

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
        }
        if compensation.isOn != isLowLight {
            isLowLight = compensation.isOn
            applyBrightness()
        }
        updateColor(sample, roomLux: room)
    }

    private func applyBrightness() {
        guard isAppActive else { return }
        if let manualBrightness {
            brightness.set(manualBrightness)
            renderer.targetLevel = manualBrightness >= 0.98 ? 1 : 0
        } else {
            brightness.ramp(to: isLowLight ? 1 : brightness.baseline)
            renderer.targetLevel = isLowLight ? 1 : 0
        }
    }

    private func updateColor(_ sample: LightSample, roomLux: Double) {
        if manualColor != nil {
            if manualColorBase == nil, let current = sample.current {
                manualColorBase = current
                applyManualColor()
            }
            return
        }

        let veryDark = roomLux < appleWhiteBalanceBelowLux * (usesAppleWhiteBalance ? 2 : 1)
        if veryDark != usesAppleWhiteBalance {
            usesAppleWhiteBalance = veryDark
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

    private static func edgeLightColor(for choice: ManualColorChoice) -> CIColor {
        switch choice {
        case .natural: CIColor(red: 1, green: 1, blue: 1)
        case .warm: CIColor(red: 1, green: 0.925, blue: 0.733)
        case .cool: CIColor(red: 0.843, green: 0.973, blue: 1)  
        }
    }

    private static func roundedPercent(_ value: CGFloat) -> Double {
        (Double(value) * 100).rounded() / 100
    }
}
