
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
    private var headPose = HeadPoseRecognizer(profile: HeadProfileStore.load())
    private var handProximity: HandProximityRecognizer
    private var resolver: ZoomGestureResolver
    private var faceTracker = FacePointTracker()
    private var viewSize: CGSize = .zero
    private var isGestureEnabled = true
    private var manualTarget: ZoomTarget = .fullFace

    // Pinch
    private var pinchScale: CGFloat = 1
    private var pinchBase: CGFloat = 1
    private var pinchActive = false
    private var pinchStartScale: CGFloat = 1
    private var pinchStartAuto = false
    private var pinchStartIdle = false

    // Belajar per pengguna
    private var handProfile: HandProfile
    private var savedProfile = HeadProfile()
    private var savedHandProfile = HandProfile()
    private var learningPaused = false
    private var lastProfileCheck = Date.distantPast
    private var autoZoomSince: Date?
    private var lastAutoZoomEnd = Date.distantPast
    private var lastCorrection = Date.distantPast

    // Debug
    private var lastDebugSent = Date.distantPast
    private var fpsCount = 0
    private var fpsStart = Date()
    private var fps = 0

    init() {
        let profile = HandProfileStore.load()
        handProfile = profile
        handProximity = HandProximityRecognizer(profile: profile)
        resolver = ZoomGestureResolver(exitHold: profile.exitHold)
    }

    private func makeResolver() -> ZoomGestureResolver {
        ZoomGestureResolver(exitHold: handProfile.exitHold)
    }

    private func makeHandProximity() -> HandProximityRecognizer {
        HandProximityRecognizer(profile: handProfile)
    }

    // MARK: - Lifecycle
    func start() { DispatchQueue.main.async { [animator] in animator.start() } }

    func stop() {
        DispatchQueue.main.async { [animator] in animator.stop() }
        stateQueue.async { [self] in
            HeadProfileStore.save(headPose.profile)
            HandProfileStore.save(handProfile)
        }
    }

    func setViewSize(_ size: CGSize) {
        DispatchQueue.main.async { [animator] in animator.setViewSize(size) }
        stateQueue.async { [self] in viewSize = size }
    }

    /// Sesi kamera baru (setelah terputus atau kembali dari background): buang semua state sesi.
    /// Hasil belajar per pengguna tetap dipertahankan.
    func resetSession() {
        DispatchQueue.main.async { [animator] in animator.reset() }
        faceDetector.reset()
        handDetector.reset()
        stateQueue.async { [self] in
            headPose = HeadPoseRecognizer(profile: headPose.profile)
            handProximity = makeHandProximity()
            faceTracker = FacePointTracker()
            resolver = makeResolver()
            pinchScale = 1
            pinchBase = 1
            pinchActive = false
            autoZoomSince = nil
            publish(isGestureEnabled ? .fullFace : manualTarget)
        }
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
            headPose = HeadPoseRecognizer(profile: headPose.profile)   // hasil belajar tetap
            handProximity = makeHandProximity()
            resolver = makeResolver()
            manualTarget = .fullFace
            pinchScale = 1      // sisa zoom manual ikut dibersihkan
            pinchBase = 1
            pinchActive = false
            autoZoomSince = nil
            publish(.fullFace)
        }
    }

    func setManualTarget(_ target: ZoomTarget) {
        stateQueue.async { [self] in
            manualTarget = target
            pinchScale = 1
            pinchBase = 1
            pinchActive = false
            if !isGestureEnabled { publish(target) }
        }
    }

    func setLearningPaused(_ paused: Bool) {
        stateQueue.async { [self] in learningPaused = paused }
    }

    func pinchChanged(_ magnification: CGFloat) {
        stateQueue.async { [self] in
            if !pinchActive {
                pinchActive = true
                pinchBase = max(animator.displayedScale, 1)   // mulai dari zoom yang sedang tampil
                pinchStartScale = pinchBase
                let now = Date()
                pinchStartAuto = isGestureEnabled
                    && (autoZoomSince != nil || now.timeIntervalSince(lastAutoZoomEnd) < 3)
                pinchStartIdle = isGestureEnabled && !pinchStartAuto && pinchBase < 1.2
            }
            pinchScale = min(max(pinchBase * magnification, 1), 3)
            publish(isGestureEnabled ? resolver.target : manualTarget)
        }
    }

    func pinchEnded() {
        stateQueue.async { [self] in
            learnFromPinch(finalScale: pinchScale)
            pinchActive = false
            pinchBase = pinchScale < 1.05 ? 1 : pinchScale
            pinchScale = pinchBase
            publish(isGestureEnabled ? resolver.target : manualTarget)
        }
    }

    /// Koreksi manual dipakai sebagai sinyal: zoom out setelah auto = tidak diminta,
    /// zoom in saat auto diam = terlewat.
    private func learnFromPinch(finalScale: CGFloat) {
        guard isGestureEnabled, pinchStartScale > 0 else { return }
        let now = Date()
        guard now.timeIntervalSince(lastCorrection) >= 2 else { return }
        let ratio = finalScale / pinchStartScale
        if pinchStartAuto, ratio < 0.85 {
            handProfile.learnUnwanted()
        } else if pinchStartIdle, ratio > 1.25 {
            handProfile.learnMissed()
        } else {
            return
        }
        lastCorrection = now
        handProximity.apply(handProfile)
    }

    private func saveProfileIfNeeded(now: Date) {
        guard now.timeIntervalSince(lastProfileCheck) >= 10 else { return }
        lastProfileCheck = now
        if headPose.profile != savedProfile {
            savedProfile = headPose.profile
            HeadProfileStore.save(savedProfile)
        }
        if handProfile != savedHandProfile {
            savedHandProfile = handProfile
            HandProfileStore.save(handProfile)
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
        // Jarak dihitung dari perkiraan ujung brush, bukan dari pegangan
        let tips = scan.grips.map { converter.toView($0.tip) }
        let hand = handProximity.trackHand(tips, points: faceTracker.points, viewHeight: H, now: now)
        let covering = handProximity.isCovering(hand: hand, points: faceTracker.points)
        let points = faceTracker.update(face: face, covering: covering, converter: converter)

        let handTarget = handProximity.update(hand: hand, points: points, now: now)
        let learn = !learningPaused && handTarget == nil
        let headTarget = headPose.update(face: covering ? nil : face, learn: learn, now: now)
        let handFar = handProximity.isFar(hand: hand, points: points)
        let target = resolver.resolve(hand: handTarget, head: headTarget, handFar: handFar, now: now)

        // Catat kapan auto zoom (mata/bibir) mulai dan selesai, bahan untuk membaca koreksi manual
        let handDriven = target == .leftEye || target == .rightEye || target == .lips
        if handDriven, autoZoomSince == nil { autoZoomSince = now }
        if !handDriven, autoZoomSince != nil {
            autoZoomSince = nil
            lastAutoZoomEnd = now
        }
        if abs(resolver.exitHold - handProfile.exitHold) > 0.001 { handProfile.exitHold = resolver.exitHold }
        saveProfileIfNeeded(now: now)

        // Selama zoom mata/bibir, progress sisi wajah tetap mengikuti kepala. Saat turun tingkat,
        // zoom langsung meluncur ke 1,35x, tidak mulai dari 1x dulu.
        var activeSide: FaceSide?
        switch target {
        case .faceSide(let side):
            activeSide = side
        case .leftEye, .rightEye, .lips:
            if case .faceSide(let side)? = headTarget { activeSide = side }
        default:
            break
        }
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
        case .faceSide(let side): return sideFocus(side, p)
        }
    }

    /// Zoom sisi wajah menuju mata yang terlihat kamera, bukan tengah wajah.
    private func sideFocus(_ side: FaceSide, _ p: FacePoints) -> CGPoint? {
        guard let c = p.center else { return nil }
        let k = headPose.sideProgress
        // Sisi kiri layar menghadap kamera = mata kiri layar yang paling terlihat, begitu juga sebaliknya
        guard let eye = side == .left ? p.leftEye : p.rightEye else {
            let dx = p.width * 0.08 * k
            return CGPoint(x: side == .left ? c.x - dx : c.x + dx, y: c.y)
        }
        return CGPoint(x: c.x + (eye.x - c.x) * k, y: c.y + (eye.y - c.y) * k)
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

    private func sendDebug(target: ZoomTarget, tip: CGPoint?, grip: CGPoint?, points: FacePoints,
                           scan: HandScan, face: FaceObservation?, handFps: Int, now: Date) {
        guard GestureDebug.isEnabledGestureDebug, let onDebugInfo,
              now.timeIntervalSince(lastDebugSent) >= 0.1 else { return }
        lastDebugSent = now
        func dist(_ p: CGPoint?) -> CGFloat? {
            guard let tip, let p, points.scale > 0 else { return nil }
            return hypot(tip.x - p.x, tip.y - p.y) / points.scale
        }
        let faceYaw = face.map { $0.yaw }.flatMap { $0.isFinite ? $0 : nil } ?? 0
        onDebugInfo(ZoomDebugInfo(
            target: target.debugName,
            distLeftEye: dist(points.leftEye),
            distRightEye: dist(points.rightEye),
            distLips: dist(points.lips),
            handsSeen: scan.handsSeen,
            gripCount: scan.grips.count,
            pinchRatio: scan.pinchRatio,
            handConfidence: scan.confidence,
            yaw: faceYaw,
            yawBaseline: headPose.profile.yawBaseline,
            turnPeak: headPose.profile.turnPeak,
            eyeSpan: points.scale,
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
