import Foundation

nonisolated struct HeadPoseRecognizer {
    var turnEnter = 20.0            // derajat
    var turnExit = 10.0
    var downEnter = 0.05            // kenaikan rasio hidung-mata dari posisi lurus
    var downExit = 0.025
    var turnDwell: TimeInterval = 0.5
    var downDwell: TimeInterval = 1.0
    var ratioSmoothing = 0.3
    var yawSmoothing = 0.4
    var maxYawRate = 60.0           // derajat/detik; lebih cepat dari ini dianggap masih bergerak
    var yawSign = 1.0               // ganti -1 kalau zoom noleh ke sisi yang salah
    var pitchSign = 1.0             // ganti -1 kalau menunduk tidak terdeteksi
    var isForeheadEnabled = false
    var holdRelease: TimeInterval = 0.8   // dahi nyangkut di zona hysteresis selama ini: lepas dan belajar ulang baseline
    var blendFull = 25.0            // derajat, progress sisi wajah penuh (mulai naik dari turnExit)
    var blendTau = 0.1              // detik, makin kecil makin cepat

    private(set) var current: ZoomTarget?
    private(set) var lastDown = 0.0
    private(set) var lastRatio = 0.0
    /// 0...1, seberapa jauh zoom sisi wajah berjalan
    private(set) var sideProgress: CGFloat = 0
    /// Sisi yang masih tampil, nil kalau progress sudah habis
    private(set) var sideShown: FaceSide?
    var baselineValue: Double { baseline ?? 0 }

    private var pending: (target: ZoomTarget, since: Date)?
    private var baseline: Double?
    private var smoothedRatio: Double?
    private var smoothedYaw: Double?
    private var lastTime: Date?
    private var heldSide: FaceSide?
    private var blendTime: Date?
    private var releaseSince: Date?
    private var relearnUntil = Date.distantPast

    mutating func update(face: FaceObservation?, now: Date) -> ZoomTarget? {
        guard let face, face.pitchRatio.isFinite else {
            reset()
            return nil
        }
        let dt = max(lastTime.map { now.timeIntervalSince($0) } ?? 0.033, 0.001)
        lastTime = now

        let rawYaw = face.yaw * yawSign
        let previousYaw = smoothedYaw ?? rawYaw
        let yaw = previousYaw + yawSmoothing * (rawYaw - previousYaw)
        smoothedYaw = yaw
        let yawRate = abs(yaw - previousYaw) / dt

        let ratio = smoothedRatio.map { $0 + ratioSmoothing * (face.pitchRatio - $0) } ?? face.pitchRatio
        smoothedRatio = ratio
        lastRatio = ratio
        let down = (ratio - (baseline ?? ratio)) * pitchSign
        lastDown = down

        // Dahi nyangkut: kepala sudah balik tapi down masih di zona hysteresis. Lepas saja, baseline dipelajari
        // lebih cepat sebentar. Baseline TIDAK di-set ke pose sekarang, supaya pose menunduk tidak ikut jadi "lurus".
        if current == .forehead, down < downEnter, down >= downExit {
            let since = releaseSince ?? now
            releaseSince = since
            if now.timeIntervalSince(since) >= holdRelease {
                current = nil
                pending = nil
                releaseSince = nil
                relearnUntil = now.addingTimeInterval(1.5)
            }
        } else {
            releaseSince = nil
        }

        // Posisi "lurus" hanya dipelajari saat kepala lurus, stabil, dan tidak ada kandidat gesture
        if current == nil, pending == nil, abs(yaw) < turnExit, yawRate < maxYawRate {
            learnBaseline(ratio, fast: abs(down) < downEnter * 0.5, boost: now < relearnUntil)
        }

        guard let raw = classify(yaw: yaw, down: down) else {
            current = nil
            pending = nil
            return nil
        }
        if raw == current {
            pending = nil
            return current
        }
        if yawRate > maxYawRate {       // kepala masih bergerak: belum dihitung
            pending = nil
            return current
        }
        if pending?.target != raw { pending = (raw, now) }
        let dwell = raw == .forehead ? downDwell : turnDwell
        if let p = pending, now.timeIntervalSince(p.since) >= dwell {
            current = raw
            pending = nil
        }
        return current
    }

    /// Haluskan zoom sisi wajah setelah gate lolos. `active` = sisi dari target final (nil kalau bukan sisi wajah).
    /// Tidak mengubah keputusan gate, hanya menghasilkan sideProgress.
    mutating func updateSideBlend(active: FaceSide?, now: Date) {
        let dt = min(max(blendTime.map { now.timeIntervalSince($0) } ?? 0.033, 0.001), 0.1)
        blendTime = now
        if let active { heldSide = active }

        var goal: CGFloat = 0
        if active != nil, let yaw = smoothedYaw {
            let raw = (abs(yaw) - turnExit) / (blendFull - turnExit)
            goal = CGFloat(min(max(raw, 0), 1))
        }
        sideProgress += (goal - sideProgress) * CGFloat(1 - exp(-dt / blendTau))

        if active == nil && sideProgress < 0.01 {
            sideProgress = 0
            heldSide = nil
        }
        sideShown = sideProgress > 0.01 ? heldSide : nil
    }

    private mutating func reset() {
        current = nil
        pending = nil
        smoothedYaw = nil
        smoothedRatio = nil
        lastTime = nil
        releaseSince = nil
    }

    private mutating func learnBaseline(_ value: Double, fast: Bool, boost: Bool) {
        guard let b = baseline else {
            baseline = value
            return
        }
        baseline = b + (value - b) * (fast ? 0.05 : (boost ? 0.02 : 0.003))
    }

    private func classify(yaw: Double, down: Double) -> ZoomTarget? {
        var turnLimit = turnEnter
        if case .faceSide(_)? = current { turnLimit = turnExit }
        if abs(yaw) >= turnLimit {
            // Zoom ke sisi wajah yang menghadap kamera (berlawanan dengan arah hidung)
            return .faceSide(yaw > 0 ? .left : .right)
        }
        // Menunduk hanya dihitung saat kepala tidak menoleh: noleh ikut mengubah rasio hidung-mata
        guard isForeheadEnabled, abs(yaw) < turnExit else { return nil }
        let downLimit = current == .forehead ? downExit : downEnter
        return down >= downLimit ? .forehead : nil
    }
}
