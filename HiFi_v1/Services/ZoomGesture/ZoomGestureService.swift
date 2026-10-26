//
//  ZoomGestureService.swift
//  HiFi_v1
//
//  Created by Davin P on 25/10/26.
//
import AVFoundation

nonisolated final class ZoomGestureService: ZoomGestureServicing, @unchecked Sendable {
    var onZoomChange: (@Sendable (ZoomState) -> Void)? {
        get { animator.onChange }
        set { animator.onChange = newValue }
    }
    var onDebugInfo: (@Sendable (ZoomDebugInfo) -> Void)?

    private let animator = ZoomAnimator()
    private let faceDetector = FaceLandmarkDetector()
    private let handDetector = HandPointDetector()
    private let stateQueue = DispatchQueue(label: "zoom.state")

    // State: hanya diakses di stateQueue
    private var headPose = HeadPoseRecognizer()
    private var handProximity = HandProximityRecognizer()
    private var faceTracker = FacePointTracker()
    private var resolver = ZoomGestureResolver()
    private var viewSize: CGSize = .zero
    private var isGestureEnabled = true
    private var manualTarget: ZoomTarget = .fullFace
    private var pinchScale: CGFloat = 1
    private var pinchBase: CGFloat = 1

    // Debug
    private var lastDebugSent = Date.distantPast
    private var fpsCount = 0
    private var fpsStart = Date()
    private var fps = 0

    // MARK: - Lifecycle
    func start() { DispatchQueue.main.async { [animator] in animator.start() } }
    func stop() { DispatchQueue.main.async { [animator] in animator.stop() } }

    func setViewSize(_ size: CGSize) {
        DispatchQueue.main.async { [animator] in animator.setViewSize(size) }
        stateQueue.async { [self] in viewSize = size }
    }

    // MARK: - Frame (dipanggil di queue kamera)
    func process(_ pixelBuffer: CVPixelBuffer) {
        let isAuto = stateQueue.sync { isGestureEnabled }
        faceDetector.submit(pixelBuffer)
        if isAuto { handDetector.submit(pixelBuffer) }
        let face = faceDetector.latest
        let scan = isAuto ? handDetector.latest : HandScan()
        let handFps = handDetector.detectionsPerSecond
        let imageSize = CGSize(width: CVPixelBufferGetHeight(pixelBuffer),
                               height: CVPixelBufferGetWidth(pixelBuffer))
        stateQueue.async { [self] in
            update(face: face, scan: scan, handFps: handFps, imageSize: imageSize)
        }
    }

    // MARK: - Kontrol dari UI
    func setGestureEnabled(_ isEnabled: Bool) {
        stateQueue.async { [self] in
            isGestureEnabled = isEnabled
            headPose = HeadPoseRecognizer()
            handProximity = HandProximityRecognizer()
            resolver = ZoomGestureResolver()
            manualTarget = .fullFace
            pinchScale = 1
            pinchBase = 1
            publish(.fullFace)
        }
    }

    func setManualTarget(_ target: ZoomTarget) {
        stateQueue.async { [self] in
            manualTarget = target
            if !isGestureEnabled { publish(target) }
        }
    }

    func pinchChanged(_ magnification: CGFloat) {
        stateQueue.async { [self] in
            pinchScale = min(max(pinchBase * magnification, 1), 3)
            publish(isGestureEnabled ? resolver.target : manualTarget)
        }
    }

    func pinchEnded() {
        stateQueue.async { [self] in
            pinchBase = pinchScale < 1.05 ? 1 : pinchScale
            pinchScale = pinchBase
            publish(isGestureEnabled ? resolver.target : manualTarget)
        }
    }

    // MARK: - Logic
    private func update(face: FaceObservation?, scan: HandScan, handFps: Int, imageSize: CGSize) {
        countFrame()
        guard viewSize.width > 0, viewSize.height > 0 else { return }
        let converter = CoordinateConverter(imageSize: imageSize, viewSize: viewSize)
        let now = Date()

        // Mode manual: hanya perlu posisi wajah
        guard isGestureEnabled else {
            let points = faceTracker.update(face: face, covering: false, converter: converter)
            publish(manualTarget)
            sendDebug(target: manualTarget, tip: nil, grip: nil, points: points,
                      scan: HandScan(), face: face, handFps: handFps, now: now)
            return
        }

        let H = viewSize.height
        // Jarak selalu dihitung dari perkiraan ujung brush, bukan dari pegangan
        let tips = scan.grips.map { converter.toView($0.tip) }
        let hand = handProximity.trackHand(tips, points: faceTracker.points, viewHeight: H, now: now)
        let covering = handProximity.isCovering(hand: hand, points: faceTracker.points, viewHeight: H)
        let points = faceTracker.update(face: face, covering: covering, converter: converter)

        let handTarget = handProximity.update(hand: hand, points: points, viewHeight: H, now: now)
        let headTarget = headPose.update(face: covering ? nil : face, now: now)
        let target = resolver.resolve(hand: handTarget, head: headTarget, now: now)

        // Gate sisi wajah tetap di HeadPoseRecognizer dan resolver. Blend hanya menghaluskan gerakannya.
        var activeSide: FaceSide?
        if case .faceSide(let side) = target { activeSide = side }
        headPose.updateSideBlend(active: activeSide, now: now)

        publish(target)

        var grip: CGPoint?
        if let hand,
           let index = tips.indices.min(by: {
               hypot(tips[$0].x - hand.x, tips[$0].y - hand.y) < hypot(tips[$1].x - hand.x, tips[$1].y - hand.y)
           }) {
            grip = converter.toView(scan.grips[index].grip)
        }
        sendDebug(target: target, tip: hand, grip: grip, points: points,
                  scan: scan, face: face, handFps: handFps, now: now)
    }

    /// Kirim target ke animator. Pinch mengalahkan semua gesture.
    private func publish(_ target: ZoomTarget) {
        if pinchScale > 1.01 {
            send(scale: pinchScale, focus: .pinch)
            return
        }
        var effective = target
        if target == .fullFace, let side = headPose.sideShown { effective = .faceSide(side) }

        guard let focus = focusPoint(for: effective, faceTracker.points) else {
            send(scale: 1, focus: .center)
            return
        }
        send(scale: zoomScale(for: effective), focus: .target(effective, focus))
    }
  
    private func zoomScale(for target: ZoomTarget) -> CGFloat {
        guard case .faceSide = target else { return target.zoomScale }
        return 1 + (target.zoomScale - 1) * headPose.sideProgress
    }

    private func focusPoint(for target: ZoomTarget, _ p: FacePoints) -> CGPoint? {
        switch target {
        case .fullFace:
            // Selagi sisi wajah masih memudar, fokus ikut turun halus sebelum benar-benar lepas
            guard let side = headPose.sideShown else { return nil }
            return sideFocus(side, p)
        case .leftEye: return p.leftEye
        case .rightEye: return p.rightEye
        case .lips: return p.lips
        case .forehead: return p.forehead
        case .faceSide(let side): return sideFocus(side, p)
        }
    }

    private func sideFocus(_ side: FaceSide, _ p: FacePoints) -> CGPoint? {
        guard let c = p.center else { return nil }
        let dx = p.width * 0.08 * headPose.sideProgress
        return CGPoint(x: side == .left ? c.x - dx : c.x + dx, y: c.y)
    }
  
    private func send(scale: CGFloat, focus: ZoomAnimator.Focus) {
        DispatchQueue.main.async { [animator] in animator.setGoal(scale: scale, focus: focus) }
    }

    // MARK: - Debug
    private func countFrame() {
        fpsCount += 1
        let now = Date()
        if now.timeIntervalSince(fpsStart) >= 1 {
            fps = fpsCount
            fpsCount = 0
            fpsStart = now
        }
    }

    /// Dikirim ±10 kali per detik, hanya kalau GestureDebug.isEnabled
    private func sendDebug(target: ZoomTarget, tip: CGPoint?, grip: CGPoint?, points: FacePoints,
                           scan: HandScan, face: FaceObservation?, handFps: Int, now: Date) {
        guard GestureDebug.isEnabled, let onDebugInfo,
              now.timeIntervalSince(lastDebugSent) >= 0.1 else { return }
        lastDebugSent = now
        let H = viewSize.height
        func dist(_ p: CGPoint?) -> CGFloat? {
            guard let tip, let p else { return nil }
            return hypot(tip.x - p.x, tip.y - p.y) / H
        }
        onDebugInfo(ZoomDebugInfo(
            target: target.debugName,
            distLeftEye: dist(points.leftEye),
            distRightEye: dist(points.rightEye),
            distLips: dist(points.lips),
            handsSeen: scan.handsSeen,
            gripCount: scan.grips.count,
            pinchRatio: scan.pinchRatio,
            handConfidence: scan.confidence,
            yaw: face?.yaw ?? 0,
            down: headPose.lastDown,
            ratio: headPose.lastRatio,
            baseline: headPose.baselineValue,
            faceAspect: face?.aspect ?? 0,
            headState: headPose.current?.debugName ?? "-",
            idleTime: resolver.idleTime(now: now),
            exitHold: resolver.exitHold,
            fps: fps,
            handFps: handFps,
            gripPoint: grip,
            tipPoint: tip,
            targetPoint: focusPoint(for: target, points)
        ))
    }
}
