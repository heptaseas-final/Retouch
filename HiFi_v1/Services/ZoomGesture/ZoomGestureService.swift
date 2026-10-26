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

    private let animator = ZoomAnimator()
    private let faceDetector = FaceLandmarkDetector()
    private let handDetector = HandPointDetector()
    private let stateQueue = DispatchQueue(label: "zoom.state")

    private var headPose = HeadPoseRecognizer()
    private var handProximity = HandProximityRecognizer()
    private var faceTracker = FacePointTracker()
    private var resolver = ZoomGestureResolver()
    private var viewSize: CGSize = .zero
    private var isGestureEnabled = true
    private var manualTarget: ZoomTarget = .fullFace
    private var pinchScale: CGFloat = 1
    private var pinchBase: CGFloat = 1

    // MARK: - Lifecycle
    func start() { DispatchQueue.main.async { [animator] in animator.start() } }
    func stop() { DispatchQueue.main.async { [animator] in animator.stop() } }

    func setViewSize(_ size: CGSize) {
        DispatchQueue.main.async { [animator] in animator.setViewSize(size) }
        stateQueue.async { [self] in viewSize = size }
    }

    func process(_ pixelBuffer: CVPixelBuffer) {
        let isAuto = stateQueue.sync { isGestureEnabled }
        faceDetector.submit(pixelBuffer)
        if isAuto { handDetector.submit(pixelBuffer) }
        let face = faceDetector.latest
        let hands = isAuto ? handDetector.latest : []
        let imageSize = CGSize(width: CVPixelBufferGetHeight(pixelBuffer),
                            height: CVPixelBufferGetWidth(pixelBuffer))
        stateQueue.async { [self] in
            update(face: face, hands: hands, imageSize: imageSize)
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
    private func update(face: FaceObservation?, hands: [CGPoint], imageSize: CGSize) {
        guard viewSize.width > 0, viewSize.height > 0 else { return }
        let converter = CoordinateConverter(imageSize: imageSize, viewSize: viewSize)

        // Mode manual: hanya perlu posisi wajah
        guard isGestureEnabled else {
            _ = faceTracker.update(face: face, covering: false, converter: converter)
            publish(manualTarget)
            return
        }

        let now = Date()
        let H = viewSize.height
        let hand = handProximity.trackHand(hands.map(converter.toView),
                                           points: faceTracker.points, viewHeight: H, now: now)
        let covering = handProximity.isCovering(hand: hand, points: faceTracker.points, viewHeight: H)
        let points = faceTracker.update(face: face, covering: covering, converter: converter)

        let handTarget = handProximity.update(hand: hand, points: points, viewHeight: H)
        let headTarget = headPose.update(face: covering ? nil : face, now: now)
        publish(resolver.resolve(hand: handTarget, head: headTarget, now: now))
    }

    /// Kirim target ke animator. Pinch mengalahkan semua gesture.
    private func publish(_ target: ZoomTarget) {
        if pinchScale > 1.01 {
            send(scale: pinchScale, focus: nil)
            return
        }
        let focus = focusPoint(for: target, faceTracker.points)
        send(scale: focus == nil ? 1 : target.zoomScale, focus: focus)
    }

    private func focusPoint(for target: ZoomTarget, _ p: FacePoints) -> CGPoint? {
        switch target {
        case .fullFace: return nil
        case .leftEye: return p.leftEye
        case .rightEye: return p.rightEye
        case .lips: return p.lips
        case .forehead: return p.forehead
        case .faceSide(let side):
            guard let c = p.center else { return nil }
            let dx = p.width * 0.08
            return CGPoint(x: side == .left ? c.x - dx : c.x + dx, y: c.y)
        }
    }

    private func send(scale: CGFloat, focus: CGPoint?) {
        DispatchQueue.main.async { [animator] in animator.setGoal(scale: scale, focus: focus) }
    }
}
