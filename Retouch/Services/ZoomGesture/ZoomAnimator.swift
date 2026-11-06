import SwiftUI

nonisolated final class ZoomAnimator: NSObject, @unchecked Sendable {
    enum Focus: Equatable {
        case center
        case pinch
        case target(ZoomTarget, CGPoint)
    }

    private enum Mode: Equatable {
        case none, pinch
        case target(ZoomTarget)
    }

    var onChange: (@Sendable (ZoomState) -> Void)?

    private let zoomInTau = ZoomTuning.zoomInTau
    private let zoomOutTau = ZoomTuning.zoomOutTau
    private let scaleLock = NSLock()

    private var viewSize: CGSize = .zero
    private var goalScale: CGFloat = 1
    private var mode: Mode = .none
    private var lockedFocus: CGPoint?

    // Masa transisi: dari target baru muncul sampai tampilan sudah menetap. Selama itu zona diam mati,
    // supaya target tetap langsung diarahkan ke tengah seperti sebelumnya.
    private var inTransition = false
    private var transitionStart: CFTimeInterval = 0

    private var focusFilterX = ZoomAnimator.focusFilter()
    private var focusFilterY = ZoomAnimator.focusFilter()
    private var lastRawFocus: CGPoint?
    private var lastFilteredFocus: CGPoint = .zero

    private var currentScale: CGFloat = 1
    private var panX: CGFloat = 0
    private var panY: CGFloat = 0
    private var velX: CGFloat = 0
    private var velY: CGFloat = 0
    private var lastState = ZoomState()
    private var link: CADisplayLink?
    private var shownScale: CGFloat = 1

    func reset() {
        goalScale = 1
        currentScale = 1
        panX = 0
        panY = 0
        velX = 0
        velY = 0
        mode = .none
        lockedFocus = nil
        inTransition = false
        lastRawFocus = nil
        focusFilterX.reset()
        focusFilterY.reset()
        scaleLock.lock(); shownScale = 1; scaleLock.unlock()
        lastState = ZoomState()
        onChange?(lastState)
    }

    var displayedScale: CGFloat {
        scaleLock.lock(); defer { scaleLock.unlock() }
        return shownScale
    }

    func start() {
        guard link == nil else { return }
        let l = CADisplayLink(target: self, selector: #selector(tick(_:)))
        l.add(to: .main, forMode: .common)
        link = l
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    func setViewSize(_ size: CGSize) { viewSize = size }

    func setGoal(scale: CGFloat, focus: Focus) {
        goalScale = scale
        switch focus {
        case .center:
            mode = .none
            lockedFocus = nil
            inTransition = false
            lastRawFocus = nil
        case .pinch:
            guard mode != .pinch else { return }
            mode = .pinch
            lockedFocus = CGPoint(x: viewSize.width / 2 - panX / currentScale,
                                  y: viewSize.height / 2 - panY / currentScale)
            inTransition = false
            lastRawFocus = nil
        case .target(let target, let raw):
            let isNew = mode != .target(target)
            if isNew {
                focusFilterX.reset()
                focusFilterY.reset()
                lastRawFocus = nil
            }

            // Filter hanya dijalankan kalau titik mentahnya benar-benar baru (bukan sampel basi yang diulang)
            let point: CGPoint
            if let last = lastRawFocus, last == raw {
                point = lastFilteredFocus
            } else {
                let t = CACurrentMediaTime()
                point = CGPoint(x: focusFilterX.filter(Double(raw.x), t: t),
                                y: focusFilterY.filter(Double(raw.y), t: t))
                lastRawFocus = raw
                lastFilteredFocus = point
            }

            if isNew {
                mode = .target(target)
                lockedFocus = point
                inTransition = true
                transitionStart = CACurrentMediaTime()
            } else {
                updateAnchor(with: point)
            }
        }
    }

    /// Zona diam: selama titik fokus masih di dalam zona di sekitar anchor, tampilan tidak bergeser.
    /// Kalau keluar, anchor hanya bergeser sebesar kelebihannya (tidak melompat ke titik baru).
    private func updateAnchor(with point: CGPoint) {
        guard let anchor = lockedFocus else {
            lockedFocus = point
            return
        }
        if inTransition {
            lockedFocus = point
            return
        }
        let s = max(currentScale, 1)
        let dx = (point.x - anchor.x) * s
        let dy = (point.y - anchor.y) * s
        let dist = hypot(dx, dy)
        let r = viewSize.width * ZoomTuning.focusDeadZone
        guard dist > r else { return }
        let t = (dist - r) / dist
        lockedFocus = CGPoint(x: anchor.x + (point.x - anchor.x) * t,
                              y: anchor.y + (point.y - anchor.y) * t)
    }

    private static func focusFilter() -> OneEuroFilter {
        var filter = OneEuroFilter()
        filter.minCutoff = ZoomTuning.focusMinCutoff
        filter.beta = ZoomTuning.focusBeta
        return filter
    }

    /// Spring teredam kritis: kecepatan selalu kontinu walau target meloncat di laju deteksi.
    private static func smoothDamp(_ current: CGFloat, _ target: CGFloat, _ velocity: inout CGFloat,
                                   smoothTime: CGFloat, dt: CGFloat) -> CGFloat {
        let omega = 2 / max(smoothTime, 0.0001)
        let x = omega * dt
        let e = 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x)
        let change = current - target
        let temp = (velocity + omega * change) * dt
        velocity = (velocity - omega * temp) * e
        return target + (change + temp) * e
    }

    @objc private func tick(_ link: CADisplayLink) {
        let size = viewSize
        guard size.width > 0, size.height > 0 else { return }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let dt = min(max(CGFloat(link.targetTimestamp - link.timestamp), 1.0 / 120.0), 0.05)

        // Besar zoom hanya mengikuti goal, tidak bergantung posisi wajah di layar
        let tau = goalScale > currentScale ? zoomInTau : zoomOutTau
        currentScale += (goalScale - currentScale) * (1 - exp(-dt / tau))
        scaleLock.lock(); shownScale = currentScale; scaleLock.unlock()

        let maxX = (currentScale - 1) * size.width / 2
        let maxY = (currentScale - 1) * size.height / 2

        var goalX: CGFloat = 0
        var goalY: CGFloat = 0
        if goalScale > 1, let f = lockedFocus {
            goalX = currentScale * (center.x - f.x)
            goalY = currentScale * (center.y - f.y)
        }

        // Geser dibatasi supaya gambar tidak keluar dari tepi layar
        goalX = min(max(goalX, -maxX), maxX)
        goalY = min(max(goalY, -maxY), maxY)

        panX = Self.smoothDamp(panX, goalX, &velX, smoothTime: ZoomTuning.panSmoothTime, dt: dt)
        panY = Self.smoothDamp(panY, goalY, &velY, smoothTime: ZoomTuning.panSmoothTime, dt: dt)

        if inTransition {
            let converged = abs(goalX - panX) < 1 && abs(goalY - panY) < 1
                && abs(goalScale - currentScale) < 0.03
            if converged || CACurrentMediaTime() - transitionStart > ZoomTuning.focusTransitionMax {
                inTransition = false
            }
        }

        if abs(lastState.scale - currentScale) > 0.0005
            || abs(lastState.offset.width - panX) > 0.05
            || abs(lastState.offset.height - panY) > 0.05 {
            lastState = ZoomState(scale: currentScale, offset: CGSize(width: panX, height: panY))
            onChange?(lastState)
        }
    }
}
