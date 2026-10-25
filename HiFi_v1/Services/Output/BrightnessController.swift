import QuartzCore
import UIKit

/// Drives the screen brightness towards a target with an eased glide and a
/// capped rate, so it changes gradually and never jumps (PRD Epic 3).
@MainActor
final class BrightnessController {
    /// Time constant of the glide toward the target, in seconds. With the
    /// rate cap below, even a full swing finishes in under 1 s (PRD Success Metrics).
    var easing: CGFloat = 0.25
    /// Maximum change in brightness per second (0…1 scale).
    var maxRatePerSecond: CGFloat = 1.2
    /// Smallest change worth sending to the screen. Each write is a call into
    /// the system, and writing every frame competes with the camera preview.
    var minWriteStep: CGFloat = 0.004
    /// Called whenever the applied brightness changes.
    var onChange: ((CGFloat) -> Void)?

    /// Brightness the user had when the feature activated; compensation adds
    /// to it, and it is given back when the app leaves.
    private(set) var baseline: CGFloat
    private(set) var target: CGFloat
    private(set) var current: CGFloat
    private var written: CGFloat
    private var displayLink: CADisplayLink?
    private var lastTick: CFTimeInterval = 0

    init() {
        let value = Self.screen?.brightness ?? 0.5
        baseline = value
        target = value
        current = value
        written = value
    }

    /// Reads the screen's current brightness as the new baseline, when the
    /// feature activates or the app returns to foreground.
    ///
    /// If the screen still shows the value we last wrote (iOS didn't take a
    /// restore while the app was leaving), it's our boost, not the user's
    /// choice: the old baseline is kept, so it never ratchets upward.
    func captureBaseline() {
        stopDisplayLink()
        let value = Self.screen?.brightness ?? baseline
        if abs(value - written) > 0.01 { baseline = value }
        target = baseline
        apply(baseline)
    }

    /// Ramps gradually towards `value`.
    func ramp(to value: CGFloat) {
        target = value.clamped
        guard abs(target - current) >= minWriteStep else { return }
        startDisplayLink()
    }

    /// Applies `value` immediately; used for direct manual control.
    func set(_ value: CGFloat) {
        stopDisplayLink()
        target = value.clamped
        apply(target)
    }

    /// Gives the user's own brightness back at once, e.g. when the app is leaving.
    func restoreBaseline() {
        set(baseline)
    }

    private func apply(_ value: CGFloat) {
        current = value
        written = value
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
        // Track the glide every frame but only write to the screen in visible steps.
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

/// Breaks the retain cycle between CADisplayLink and its target.
private final class DisplayLinkProxy {
    weak var owner: BrightnessController?
    init(_ owner: BrightnessController) { self.owner = owner }

    @MainActor @objc func tick() { owner?.tick() }
}

private extension CGFloat {
    var clamped: CGFloat { Swift.min(Swift.max(self, 0), 1) }
}
