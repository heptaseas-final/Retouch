import QuartzCore
import UIKit

@MainActor
final class BrightnessController {
    var easing: CGFloat = 0.25
    var maxRatePerSecond: CGFloat = 1.2
    var minWriteStep: CGFloat = 0.004
    var onChange: ((CGFloat) -> Void)?

    private(set) var baseline: CGFloat
    private(set) var target: CGFloat
    private(set) var current: CGFloat
    private var written: CGFloat
    private var lastBoost: CGFloat?
    private var displayLink: CADisplayLink?
    private var lastTick: CFTimeInterval = 0
    
    private enum Key {
        static let baseline = "bc.baseline"
        static let boosted = "bc.boosted"
        static let lastBoost = "bc.lastBoost"
    }
    private let defaults = UserDefaults.standard

    init() {
        let screenValue = Self.screen?.brightness ?? 0.5
        var value = screenValue
        var boost: CGFloat?

        // Sesi lalu berakhir saat boosted dan layar masih nyangkut di nilai itu:
        // pakai baseline asli, bukan nilai nyangkut tadi.
        if defaults.bool(forKey: Key.boosted),
           let savedBaseline = defaults.object(forKey: Key.baseline) as? Double,
           let savedBoost = defaults.object(forKey: Key.lastBoost) as? Double,
           abs(screenValue - CGFloat(savedBoost)) <= 0.01 {
            value = CGFloat(savedBaseline)
            boost = screenValue
        }

        baseline = value
        target = value
        current = value
        written = value
        lastBoost = boost
    }

    func captureBaseline() {
        stopDisplayLink()
        let value = Self.screen?.brightness ?? baseline
        let isOurs = abs(value - written) <= 0.01 || lastBoost.map { abs(value - $0) <= 0.01 } == true
        if !isOurs { baseline = value }
        target = baseline
        apply(baseline)
    }

    func ramp(to value: CGFloat) {
        target = value.clamped
        guard abs(target - current) >= minWriteStep else { return }
        startDisplayLink()
    }

    func set(_ value: CGFloat) {
        stopDisplayLink()
        target = value.clamped
        apply(target)
    }

    func restoreBaseline() {
        set(baseline)
    }

    private func apply(_ value: CGFloat) {
        current = value
        written = value
        let boosted = abs(value - baseline) > 0.01
        if boosted {
            lastBoost = value
            defaults.set(Double(value), forKey: Key.lastBoost)
        }
        defaults.set(boosted, forKey: Key.boosted)
        defaults.set(Double(baseline), forKey: Key.baseline)
        Self.screen?.brightness = value
        onChange?(value)
    }

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        lastTick = CACurrentMediaTime()
        let link = CADisplayLink(target: DisplayLinkProxy(self), selector: #selector(DisplayLinkProxy.tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    fileprivate func tick() {
        let now = CACurrentMediaTime()
        let dt = CGFloat(now - lastTick)
        lastTick = now

        let delta = target - current
        if abs(delta) < minWriteStep {
            apply(target)
            stopDisplayLink()
            return
        }
        let eased = delta * (1 - exp(-dt / easing))
        let maxStep = maxRatePerSecond * dt
        let next = current + min(max(eased, -maxStep), maxStep)
        if abs(next - written) >= minWriteStep {
            apply(next)
        } else {
            current = next
        }
    }

    private static var screen: UIScreen? {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.screen }
            .first
    }
}

private final class DisplayLinkProxy {
    weak var owner: BrightnessController?
    init(_ owner: BrightnessController) { self.owner = owner }

    @MainActor @objc func tick() { owner?.tick() }
}

private extension CGFloat {
    var clamped: CGFloat { Swift.min(Swift.max(self, 0), 1) }
}
