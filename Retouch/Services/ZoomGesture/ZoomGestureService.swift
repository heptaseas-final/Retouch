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

    // Nomor urut deteksi yang sudah diteruskan ke stateQueue (diakses di queue kamera, dijaga seqLock)
    private let seqLock = NSLock()
    private var queuedFaceSeq = 0
    private var queuedHandSeq = 0

    // State: hanya diakses di stateQueue
    private var headPose: HeadPoseRecognizer
    private var turnAnchor: Double          // turnPeak di awal pemakaian, batas geser belajar per sesi
    private var pitchRecognizer: HeadPitchRecognizer
    private var handProximity: HandProximityRecognizer
    private var resolver: ZoomGestureResolver
    private var faceTracker = FacePointTracker()
    private var pacer = DetectionPacer()
    private var viewSize: CGSize = .zero
    private var isGestureEnabled = true
    private var manualTarget: ZoomTarget = .fullFace

    // Hasil terakhir tiap sumber: dipakai ulang saat sumber lain yang baru
    private var lastFace: FaceObservation?
    private var lastScan = HandScan()
    private var lastTips: [CGPoint] = []
    private var lastHand: CGPoint?
    
    // Zoom bibir satu alur. lipsTracker hanya dipakai untuk trackHand (penghalus dan kecepatan tangan, pose 2 atau 3 jari)
    private var lipsTracker = HandProximityRecognizer()
    private var lipFlow = LipsZoomFlow()
    private var lipMotion = LipMotionRecognizer()
    private var lipsInput = LipsZoomFlow.Input()
    private var lipsHand: CGPoint?
    private var lastAllTips: [CGPoint] = []
    private var handTarget: ZoomTarget?
    private var headTarget: ZoomTarget?
    private var lastLogicTime = Date.distantPast
    private var prevFace: FaceObservation?
    private var prevFaceTime = Date.distantPast
    private var eventLog = ZoomEventLog()
    private var lastLoggedTarget: ZoomTarget = .fullFace

    // Pinch
    private var pinchScale: CGFloat = 1
    private var pinchBase: CGFloat = 1
    private var pinchActive = false
    private var pinchStartScale: CGFloat = 1
    private var pinchStartAuto = false
    private var pinchStartIdle = false
    private var pinchStartSide = false

    // Belajar per pengguna
    private var handProfile: HandProfile
    private var savedProfile = HeadProfile()
    private var savedHandProfile = HandProfile()
    private var savedPitchProfile = PitchProfile()
    private var learningPaused = false
    private var lastProfileCheck = Date.distantPast
    private var autoZoomSince: Date?
    private var lastAutoZoomEnd = Date.distantPast
    private var sideZoomSince: Date?
    private var lastSideZoomStart = Date.distantPast
    private var lastSideZoomEnd = Date.distantPast
    private var lastCorrection = Date.distantPast

    // Debug. `fps` = deteksi wajah per detik (bukan fps kamera), `handFps` = deteksi tangan per detik
    private var lastDebugSent = Date.distantPast
    private var fpsCount = 0
    private var fpsStart = Date()
    private var fps = 0

    init() {
        var profile = HandProfileStore.load()
        profile.beginSession()   // nilai tersimpan jadi titik awal; belajar hanya boleh geser sedikit dari sini
        handProfile = profile
        handProximity = HandProximityRecognizer(profile: profile)
        lipsTracker = HandProximityRecognizer(profile: profile)
        resolver = ZoomGestureResolver()
        let head = HeadPoseRecognizer(profile: HeadProfileStore.load())
        headPose = head
        turnAnchor = head.turnAnchor
        pitchRecognizer = HeadPitchRecognizer(profile: PitchProfileStore.load())
    }

    private func makeResolver() -> ZoomGestureResolver {
        ZoomGestureResolver()
    }

    private func makeHeadPose() -> HeadPoseRecognizer {
        HeadPoseRecognizer(profile: headPose.profile, turnAnchor: turnAnchor)   // hasil belajar tetap
    }

    private func makePitch() -> HeadPitchRecognizer {
        HeadPitchRecognizer(profile: pitchRecognizer.profile)
    }

    private func makeHandProximity() -> HandProximityRecognizer {
        HandProximityRecognizer(profile: handProfile)
    }

    /// Buang hasil deteksi lama yang tersimpan di service (bukan di detektor).
    private func clearCachedDetections() {
        lastFace = nil
        lastScan = HandScan()
        lastTips = []
        lastHand = nil
        handTarget = nil
        headTarget = nil
        prevFace = nil
        lastAllTips = []
        lipsTracker = makeHandProximity()
        lipFlow = LipsZoomFlow()
        lipMotion = LipMotionRecognizer()
        lipsInput = LipsZoomFlow.Input()
        lipsHand = nil
    }

    /// Anggap semua hasil deteksi yang ada sekarang sudah dibaca, supaya hasil lama tidak diproses ulang.
    private func syncQueuedSequences() {
        let faceSeq = faceDetector.snapshot.sequence
        let handSeq = handDetector.snapshot.sequence
        seqLock.lock()
        queuedFaceSeq = faceSeq
        queuedHandSeq = handSeq
        seqLock.unlock()
    }

    // MARK: - Lifecycle
    func start() { DispatchQueue.main.async { [animator] in animator.start() } }

    func stop() {
        DispatchQueue.main.async { [animator] in animator.stop() }
        stateQueue.async { [self] in
            HeadProfileStore.save(headPose.profile)
            HandProfileStore.save(handProfile)
            PitchProfileStore.save(pitchRecognizer.profile)
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
        syncQueuedSequences()
        stateQueue.async { [self] in
            headPose = makeHeadPose()
            pitchRecognizer = makePitch()
            handProximity = makeHandProximity()
            faceTracker = FacePointTracker()
            resolver = makeResolver()
            clearCachedDetections()
            pinchScale = 1
            pinchBase = 1
            pinchActive = false
            autoZoomSince = nil
            sideZoomSince = nil
            eventLog.finish(reason: "reset sesi", at: Date())
            lastLoggedTarget = .fullFace
            publish(isGestureEnabled ? .fullFace : manualTarget)
        }
    }

    // MARK: - Frame (dipanggil di queue kamera)
    /// Tampilan kamera tetap penuh. Di sini hanya diminta deteksi baru sesuai laju, dan logika keputusan
    /// hanya dijalankan kalau ada hasil deteksi dengan nomor urut baru.
    func process(_ pixelBuffer: CVPixelBuffer) {
        let (isAuto, interval) = stateQueue.sync { (isGestureEnabled, pacer.interval(now: Date())) }
        faceDetector.submit(pixelBuffer, minInterval: interval)
        if isAuto { handDetector.submit(pixelBuffer, minInterval: interval) }

        let face = faceDetector.snapshot
        let hand: DetectionSnapshot<HandScan>? = isAuto ? handDetector.snapshot : nil

        seqLock.lock()
        let newFace = face.sequence != queuedFaceSeq
        let newHand = hand.map { $0.sequence != queuedHandSeq } ?? false
        if newFace { queuedFaceSeq = face.sequence }
        if let hand, newHand { queuedHandSeq = hand.sequence }
        seqLock.unlock()
        guard newFace || newHand else { return }

        let handFps = handDetector.detectionsPerSecond
        let imageSize = CGSize(width: CVPixelBufferGetHeight(pixelBuffer),
                               height: CVPixelBufferGetWidth(pixelBuffer))
        stateQueue.async { [self] in
            update(faceSnap: newFace ? face : nil,
                   handSnap: newHand ? hand : nil,
                   handFps: handFps, imageSize: imageSize)
        }
    }

    // MARK: - Kontrol dari UI
    func setGestureEnabled(_ isEnabled: Bool) {
        syncQueuedSequences()
        stateQueue.async { [self] in
            isGestureEnabled = isEnabled
            headPose = makeHeadPose()   // hasil belajar tetap
            pitchRecognizer = makePitch()
            handProximity = makeHandProximity()
            resolver = makeResolver()
            clearCachedDetections()
            manualTarget = .fullFace
            pinchScale = 1      // sisa zoom manual ikut dibersihkan
            pinchBase = 1
            pinchActive = false
            autoZoomSince = nil
            sideZoomSince = nil
            eventLog.finish(reason: "mode auto diganti", at: Date())
            lastLoggedTarget = .fullFace
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
                // Zoom samping yang baru muncul (atau baru selesai dan singkat) lalu di-pinch keluar = tidak diminta
                let sideRecent = sideZoomSince.map { now.timeIntervalSince($0) <= ZoomTuning.sideCorrectionWindow } ?? false
                let sideJustEnded = sideZoomSince == nil
                    && now.timeIntervalSince(lastSideZoomEnd) < ZoomTuning.sideCorrectionAfterEnd
                    && lastSideZoomEnd.timeIntervalSince(lastSideZoomStart) <= ZoomTuning.sideCorrectionWindow
                pinchStartSide = isGestureEnabled && !pinchStartAuto && (sideRecent || sideJustEnded)
                pinchStartIdle = isGestureEnabled && !pinchStartAuto && !pinchStartSide && pinchBase < 1.2
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
        let ratio = finalScale / pinchStartScale
        let handUnwanted = pinchStartAuto && ratio < 0.85
        let sideUnwanted = pinchStartSide && ratio < 0.85
        let missed = pinchStartIdle && ratio > 1.25

        // Selalu dicatat di log; belajar dibatasi satu koreksi per 2 detik
        if handUnwanted || sideUnwanted { eventLog.notePinchOutAfterAuto() }
        if missed { eventLog.notePinchInWhileIdle() }
        guard handUnwanted || sideUnwanted || missed else { return }
        guard now.timeIntervalSince(lastCorrection) >= 2 else { return }

        if handUnwanted {
            handProfile.learnUnwanted()
            handProximity.apply(handProfile)
            lipsTracker.apply(handProfile)
        } else if sideUnwanted {
            headPose.noteUnwantedSide()
        } else {
            handProfile.learnMissed()
            handProximity.apply(handProfile)
            lipsTracker.apply(handProfile)
        }
        lastCorrection = now
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
        if pitchRecognizer.profile != savedPitchProfile {
            savedPitchProfile = pitchRecognizer.profile
            PitchProfileStore.save(savedPitchProfile)
        }
    }

    // MARK: - Logic
    /// Dipanggil hanya kalau ada deteksi baru. `faceSnap` / `handSnap` terisi hanya untuk sumber yang baru.
    private func update(faceSnap: DetectionSnapshot<FaceObservation?>?,
                        handSnap: DetectionSnapshot<HandScan>?,
                        handFps: Int, imageSize: CGSize) {
        guard viewSize.width > 0, viewSize.height > 0 else { return }
        let converter = CoordinateConverter(imageSize: imageSize, viewSize: viewSize)

        // Waktu logika selalu maju, walau dua detektor selesai tidak berurutan
        let now = max(max(faceSnap?.timestamp ?? .distantPast, handSnap?.timestamp ?? .distantPast),
                      lastLogicTime)
        lastLogicTime = now
        if let faceSnap { countDetection(at: faceSnap.timestamp) }

        // Mode manual: hanya perlu posisi wajah
        guard isGestureEnabled else {
            guard let faceSnap else { return }
            lastFace = faceSnap.value
            let points = faceTracker.update(face: lastFace, covering: false, converter: converter,
                                            now: faceSnap.timestamp)
            trackMotion(face: lastFace, hand: nil, at: faceSnap.timestamp)
            publish(manualTarget)
            sendDebug(target: manualTarget, tip: nil, grip: nil, points: points,
                      scan: HandScan(), face: lastFace, handFps: handFps, now: now)
            return
        }

        let H = viewSize.height

        // 1. Tangan: dilacak hanya saat ada deteksi tangan baru
        if let handSnap {
            lastScan = handSnap.value
            // Jalur mata: hanya pose 3 jari, sama seperti sebelumnya
            lastTips = lastScan.threeFingerGrips.map { converter.toView($0.tip) }
            lastHand = handProximity.trackHand(lastTips, points: faceTracker.points,
                                               viewHeight: H, now: handSnap.timestamp)
            // Jalur bibir: pose 2 atau 3 jari
            lastAllTips = lastScan.grips.map { converter.toView($0.tip) }
            lipsHand = lipsTracker.trackHand(lastAllTips, points: faceTracker.points,
                                             viewHeight: H, now: handSnap.timestamp)
        }
        var covering = handProximity.isCovering(hand: lastHand, points: faceTracker.points)
        // Tangan pose 2 jari atau jari yang sedang menahan zoom bibir juga menutupi bibir: titik wajah dibekukan
        if !covering {
            let fp = faceTracker.points
            if let h = lipsHand, let lips = fp.lips, fp.width > 0,
               hypot(h.x - lips.x, h.y - lips.y) / fp.width < ZoomTuning.coverDistance {
                covering = true
            } else if lipFlow.isActive && lipsInput.fingerNear {
                covering = true
            }
        }

        // 2. Titik wajah: diperbarui hanya saat ada deteksi wajah baru
        var points = faceTracker.points
        if let faceSnap {
            lastFace = faceSnap.value
            points = faceTracker.update(face: lastFace, covering: covering, converter: converter,
                                        now: faceSnap.timestamp)
        }

        // 3. Keputusan tangan: hanya saat ada deteksi tangan baru
        if let handSnap {
            let support = ZoomTuning.pitchEnabled && ZoomTuning.pitchHandSupportEnabled && pitchRecognizer.isLifted
            let raw = handProximity.update(hand: lastHand, points: points, headSupport: support,
                                           now: handSnap.timestamp)
            // Bibir tidak lagi diputuskan di sini, tapi oleh LipsZoomFlow. Mata tidak berubah.
            handTarget = raw == .lips ? nil : raw
            lipsInput = lipsReadiness(points: points, converter: converter, support: support)
        }

        // 4. Keputusan kepala: hanya saat ada deteksi wajah baru
        if let faceSnap {
            let learn = !learningPaused && handTarget == nil && !lipFlow.isActive
            let faceForHead = covering ? nil : faceSnap.value
            let freezesBefore = pitchRecognizer.freezeCount
            pitchRecognizer.update(face: faceForHead, learn: learn, covered: covering, now: faceSnap.timestamp)
            if pitchRecognizer.freezeCount > freezesBefore {
                eventLog.noteFreezes(pitchRecognizer.freezeCount - freezesBefore)
            }
            // Dongak/tunduk cepat: tahan keputusan yaw dan jangan belajar, supaya tidak ada zoom samping palsu
            let freeze = ZoomTuning.pitchEnabled && ZoomTuning.pitchYawFreezeEnabled
                && pitchRecognizer.isFrozen(now: faceSnap.timestamp)
            lipMotion.update(face: faceForHead, ignore: freeze, now: faceSnap.timestamp)
            headTarget = headPose.update(face: faceForHead, learn: learn && !freeze, covered: covering,
                                         yawFrozen: freeze, now: faceSnap.timestamp)
        }
        
        trackMotion(face: faceSnap != nil ? lastFace : nil, hand: lastHand ?? lipsHand, at: now,
                    faceChecked: faceSnap != nil)

        // Zoom bibir: mata yang aktif selalu menang (satu target aktif), flow bibir dibatalkan
        if handTarget != nil {
            lipFlow.cancel()
        } else {
            var input = lipsInput
            input.lipsMoving = lipMotion.isMoving
            lipFlow.update(input, now: now)
        }

        let target = resolver.resolve(hand: handTarget, lips: lipFlow.isActive, head: headTarget,
                                      covering: covering, headStraight: headPose.isStraight, now: now)

        // Catat kapan auto zoom (mata/bibir) mulai dan selesai, bahan untuk membaca koreksi manual
        let handDriven = target == .leftEye || target == .rightEye || target == .lips
        if handDriven, autoZoomSince == nil { autoZoomSince = now }
        if !handDriven, autoZoomSince != nil {
            autoZoomSince = nil
            lastAutoZoomEnd = now
        }

        // Zoom samping: dipakai untuk membaca pinch keluar sebagai koreksi "tidak diminta"
        var isSide = false
        if case .faceSide = target { isSide = true }
        if isSide, sideZoomSince == nil {
            sideZoomSince = now
            lastSideZoomStart = now
        }
        if !isSide, sideZoomSince != nil {
            sideZoomSince = nil
            lastSideZoomEnd = now
        }

        let previousTarget = lastLoggedTarget
        eventLog.update(target, at: now) { endReason(from: previousTarget, to: target) }
        lastLoggedTarget = target

        saveProfileIfNeeded(now: now)

        publish(target)
        
        let threeGrips = lastScan.threeFingerGrips
        var grip: CGPoint?
        if let hand = lastHand,
           let index = lastTips.indices.min(by: {
               hypot(lastTips[$0].x - hand.x, lastTips[$0].y - hand.y)
                   < hypot(lastTips[$1].x - hand.x, lastTips[$1].y - hand.y)
           }), index < lastScan.grips.count {
            grip = converter.toView(threeGrips[index].grip)
        }
        sendDebug(target: target, tip: lastHand, grip: grip, points: points,
                  scan: lastScan, face: lastFace, handFps: handFps, now: now)
    }

    /// Catat gerakan kepala/tangan untuk mode hemat daya saat semuanya diam.
    private func trackMotion(face: FaceObservation?, hand: CGPoint?, at now: Date, faceChecked: Bool = true) {
        if hand != nil { pacer.noteMotion(at: now) }
        guard faceChecked else { return }
        guard let f = face else {
            prevFace = nil
            return
        }
        if let p = prevFace {
            let dt = max(now.timeIntervalSince(prevFaceTime), 0.001)
            let move = hypot(f.center.x - p.center.x, f.center.y - p.center.y) / max(f.width, 0.01) / dt
            let yawMove = (f.yaw.isFinite && p.yaw.isFinite) ? abs(f.yaw - p.yaw) / dt : 0
            if move > ZoomTuning.idleFaceSpeed || yawMove > ZoomTuning.idleYawRate {
                pacer.noteMotion(at: now)
            }
        }
        prevFace = f
        prevFaceTime = now
    }
    
    private func lipsReadiness(points: FacePoints, converter: CoordinateConverter, support: Bool) -> LipsZoomFlow.Input {
        var input = LipsZoomFlow.Input()
        let W = points.width
        guard W > 0, let lips = points.lips else { return input }
        let eyes = [points.leftEye, points.rightEye].compactMap { $0 }
        func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

        let holdRadius = CGFloat(ZoomTuning.lipsHoldRadius)
        input.fingerNear = lastScan.fingertips.contains { raw in
            let p = converter.toView(raw)
            let dLips = dist(p, lips)
            let dEye = eyes.map { dist(p, $0) }.min() ?? .infinity
            return dLips < dEye && dLips / W < holdRadius
        }

        guard let hand = lipsHand,
              let idx = lastAllTips.indices.min(by: { dist(lastAllTips[$0], hand) < dist(lastAllTips[$1], hand) }),
              idx < lastScan.grips.count else { return input }
        let dLips = dist(hand, lips) / W
        let dEye = (eyes.map { dist(hand, $0) }.min() ?? .infinity) / W
        var limit = lipsTracker.enterDistance
        if support { limit *= ZoomTuning.pitchLipsReach }
        let intent = dLips < limit
            && lipsTracker.speed < lipsTracker.maxIntentSpeed
            && dEye - dLips >= lipsTracker.winMargin
        let grip = lastScan.grips[idx]
        input.pose2Ready = intent && grip.twoFinger
        input.pose3Ready = intent && grip.threeFinger
        return input
    }

    /// Kirim target ke animator. Pinch mengalahkan semua gesture.
    private func publish(_ target: ZoomTarget) {
        if pinchScale > 1.01 {
            send(scale: pinchScale, focus: .pinch)
            return
        }
        guard let focus = focusPoint(for: target, faceTracker.points) else {
            send(scale: 1, focus: .center)
            return
        }
        // Besar zoom selalu sama untuk satu target; transisi dihaluskan ZoomAnimator
        send(scale: target.zoomScale, focus: .target(target, focus))
    }

    private func focusPoint(for target: ZoomTarget, _ p: FacePoints) -> CGPoint? {
        switch target {
        case .fullFace: return nil
        case .leftEye: return p.leftEye
        case .rightEye: return p.rightEye
        case .lips: return p.lips
        case .faceSide(let side): return sideFocus(side, p)
        }
    }

    /// Zoom sisi wajah menuju mata yang terlihat kamera, bukan tengah wajah.
    private func sideFocus(_ side: FaceSide, _ p: FacePoints) -> CGPoint? {
        guard let c = p.center else { return nil }
        let k = ZoomTuning.sideFocusStrength   // kekuatan tetap, tidak lagi mengikuti sudut kepala
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

    // MARK: - Reset belajar dan log (untuk testing)
    /// Hapus semua hasil belajar tersimpan (kepala, tangan, pitch) dan kembali ke nilai awal.
    func resetLearning() {
        stateQueue.async { [self] in
            let freshHead = HeadProfile()
            HeadProfileStore.reset()
            HandProfileStore.reset()
            PitchProfileStore.reset()

            var freshHand = HandProfile()
            freshHand.beginSession()
            handProfile = freshHand
            savedProfile = freshHead
            savedHandProfile = freshHand
            savedPitchProfile = PitchProfile()
            headPose = HeadPoseRecognizer(profile: freshHead)
            turnAnchor = headPose.turnAnchor
            pitchRecognizer = HeadPitchRecognizer(profile: PitchProfile())
            handProximity = makeHandProximity()
            resolver = makeResolver()
            clearCachedDetections()
            lastCorrection = .distantPast
            autoZoomSince = nil
            sideZoomSince = nil
            eventLog.finish(reason: "reset profil belajar", at: Date())
            lastLoggedTarget = .fullFace
            publish(isGestureEnabled ? .fullFace : manualTarget)
        }
    }

    func zoomLogSummary() -> ZoomLogSummary {
        stateQueue.sync { eventLog.summary(now: Date()) }
    }

    func zoomLogText() -> String {
        stateQueue.sync { eventLog.exportText(now: Date(), profileNote: profileNote()) }
    }

    func clearZoomLog() {
        stateQueue.async { [self] in
            eventLog.reset()
            lastLoggedTarget = resolver.target
        }
    }

    private func profileNote() -> String {
        func f(_ v: Double) -> String { String(format: "%.2f", v) }
        return "profil: enterDistance \(f(handProfile.enterDistance)) | maxSpeed \(f(handProfile.maxIntentSpeed))"
            + " | turnPeak \(f(headPose.profile.turnPeak)) | yawBaseline \(f(headPose.profile.yawBaseline))"
            + " | pitchBaseline \(f(pitchRecognizer.profile.pitchBaseline)) | exitHold \(f(resolver.exitHold))"
    }

    private func endReason(from old: ZoomTarget, to new: ZoomTarget) -> String {
        if new != .fullFace { return "pindah ke \(new.debugName)" }
        if case .faceSide = old { return "kepala rileks atau wajah hilang" }
        if old == .lips { return String(format: "penahan bibir hilang %.1fs", ZoomTuning.lipsReleaseDwell) }
        return String(format: "tangan hilang, jeda %.1fs habis", resolver.exitHold)
    }

    /// Status kepala untuk debug overlay: yaw + pitch (untuk memeriksa apakah yaw ikut bergeser saat dongak).
    private func headStateText() -> String {
        let base = headPose.current?.debugName ?? "-"
        guard ZoomTuning.pitchEnabled else { return resolver.headLocked ? "\(base) kunci" : base }
        let pitch = pitchRecognizer.relative.map { String(format: "%+.0f", $0) } ?? "-"
        let flags = (resolver.headLocked ? " kunci" : "")
            + (pitchRecognizer.isLifted ? " naik" : "")
            + (pitchRecognizer.isFrozen(now: lastLogicTime) ? " beku" : "")
        return "\(base) | pitch \(pitch)°\(flags)"
    }

    // MARK: - Debug
    /// Menghitung deteksi wajah per detik (bukan fps kamera).
    private func countDetection(at now: Date) {
        fpsCount += 1
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
            guard let tip, let p, points.width > 0 else { return nil }
            return hypot(tip.x - p.x, tip.y - p.y) / points.width   // lebar wajah, sama dengan satuan recognizer
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
            headState: headStateText(),
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
