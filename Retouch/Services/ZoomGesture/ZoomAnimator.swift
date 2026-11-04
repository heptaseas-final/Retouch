import SwiftUI

/// Menghaluskan skala dan geser di 60 fps. Semua state hanya disentuh di main thread.
/// Besar zoom untuk satu target selalu sama; posisi dijaga lewat pembatasan geser (pan).
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
    private let panTau: CGFloat = 0.12
    private let lockZone: CGFloat = 0.12
    private let scaleLock = NSLock()

    private var viewSize: CGSize = .zero
    private var goalScale: CGFloat = 1
    private var mode: Mode = .none
    private var lockedFocus: CGPoint?
    private var isRecentering = false
    private var focusFilterX = ZoomAnimator.focusFilter()
    private var focusFilterY = ZoomAnimator.focusFilter()
    private var currentScale: CGFloat = 1
    private var panX: CGFloat = 0
    private var panY: CGFloat = 0
    private var lastState = ZoomState()
    private var link: CADisplayLink?
    private var shownScale: CGFloat = 1

    func reset() {
        goalScale = 1
        currentScale = 1
        panX = 0
        panY = 0
        mode = .none
        lockedFocus = nil
        isRecentering = false
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
            isRecentering = false
        case .pinch:
            guard mode != .pinch else { return }
            mode = .pinch
            lockedFocus = CGPoint(x: viewSize.width / 2 - panX / currentScale,
                                  y: viewSize.height / 2 - panY / currentScale)
            isRecentering = false
        case .target(let target, let raw):
            if mode != .target(target) {
                focusFilterX.reset()
                focusFilterY.reset()
            }
            let t = CACurrentMediaTime()
            let point = CGPoint(x: focusFilterX.filter(Double(raw.x), t: t),
                                y: focusFilterY.filter(Double(raw.y), t: t))
            if mode != .target(target) {
                mode = .target(target)
                lockedFocus = point
                isRecentering = true
            } else if isRecentering || isOutsideLockZone(point) {
                lockedFocus = point
                isRecentering = true
            }
        }
    }

    private func isOutsideLockZone(_ point: CGPoint) -> Bool {
        let cx = viewSize.width / 2, cy = viewSize.height / 2
        let sx = cx + currentScale * (point.x - cx) + panX
        let sy = cy + currentScale * (point.y - cy) + panY
        return hypot(sx - cx, sy - cy) > viewSize.width * lockZone
    }

    private static func focusFilter() -> OneEuroFilter {
        var filter = OneEuroFilter()
        filter.minCutoff = 0.5
        filter.beta = 0.02
        return filter
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

        let ap = 1 - exp(-dt / panTau)
        panX += (goalX - panX) * ap
        panY += (goalY - panY) * ap

        if isRecentering, abs(goalX - panX) < 0.5, abs(goalY - panY) < 0.5,
           abs(goalScale - currentScale) < 0.01 {
            isRecentering = false
        }

        if abs(lastState.scale - currentScale) > 0.0005
            || abs(lastState.offset.width - panX) > 0.05
            || abs(lastState.offset.height - panY) > 0.05 {
            lastState = ZoomState(scale: currentScale, offset: CGSize(width: panX, height: panY))
            onChange?(lastState)
        }
    }
}
