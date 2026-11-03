import Foundation

nonisolated struct HeadPoseRecognizer {
    var defaultTurnEnter = 20.0     // derajat, untuk pengguna baru
    var minTurnEnter = 14.0
    var maxTurnEnter = 24.0
    var turnDwell: TimeInterval = 0.5
    var yawSmoothing = 0.4
    var maxYawRate = 60.0           // derajat/detik; lebih cepat dari ini dianggap masih bergerak
    var yawSign = 1.0               // ganti -1 kalau zoom noleh ke sisi yang salah
    var lostGrace: TimeInterval = 0.8   // wajah hilang sesingkat ini: zoom ditahan, bukan dilepas
    var maxBaseline = 8.0           // batas geser posisi "lurus" yang boleh dipelajari
    var baselineTau = 6.0           // detik, makin besar makin pelan belajarnya
    var blendTau = 0.1

    private(set) var profile: HeadProfile
    private(set) var current: ZoomTarget?
    /// 0...1, seberapa jauh zoom sisi wajah berjalan
    private(set) var sideProgress: CGFloat = 0
    /// Sisi yang masih tampil, nil kalau progress sudah habis
    private(set) var sideShown: FaceSide?

    private var pending: (target: ZoomTarget, since: Date)?
    private var smoothedYaw: Double?
    private var lastTime: Date?
    private var lastSeen: Date?
    private var heldSide: FaceSide?
    private var blendTime: Date?
    private var episodeStart: Date?
    private var episodePeak = 0.0

    init(profile: HeadProfile = HeadProfile()) {
        var p = profile
        p.yawBaseline = min(max(p.yawBaseline, -8), 8)
        if p.turnPeak != 0 { p.turnPeak = min(max(p.turnPeak, 20), 45) }
        self.profile = p
    }

    // Ambang mengikuti kebiasaan noleh pengguna. Tanpa data: 20 / 10 / 28 derajat.
    private var enterAngle: Double {
        guard profile.turnPeak > 0 else { return defaultTurnEnter }
        return min(max(profile.turnPeak * 0.6, minTurnEnter), maxTurnEnter)
    }
    private var exitAngle: Double { enterAngle * 0.5 }
    private var fullAngle: Double { enterAngle * 1.4 }
    private var relativeYaw: Double { (smoothedYaw ?? 0) - profile.yawBaseline }

    /// `learn` = boleh belajar posisi lurus (false saat belajar dijeda atau tangan sedang aktif).
    mutating func update(face: FaceObservation?, learn: Bool, now: Date) -> ZoomTarget? {
        let before = current
        let result = step(face: face, learn: learn, now: now)
        trackEpisode(before: before, now: now)
        return result
    }

    private mutating func step(face: FaceObservation?, learn: Bool, now: Date) -> ZoomTarget? {
        guard let face, face.yaw.isFinite else { return holdWhileLost(now: now) }
        lastSeen = now
        let dt = max(lastTime.map { now.timeIntervalSince($0) } ?? 0.033, 0.001)
        lastTime = now

        let rawYaw = face.yaw * yawSign
        let previousYaw = smoothedYaw ?? rawYaw
        let smoothed = previousYaw + yawSmoothing * (rawYaw - previousYaw)
        smoothedYaw = smoothed
        let yawRate = abs(smoothed - previousYaw) / dt

        // Posisi lurus hanya dipelajari saat kepala lurus, stabil, dan tidak ada gesture
        if learn, current == nil, pending == nil,
           abs(relativeYaw) < exitAngle, yawRate < maxYawRate / 3 {
            let k = 1 - exp(-min(dt, 0.1) / baselineTau)
            let moved = profile.yawBaseline + (smoothed - profile.yawBaseline) * k
            profile.yawBaseline = min(max(moved, -maxBaseline), maxBaseline)
        }

        guard let raw = classify(relativeYaw) else {
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
        if let p = pending, now.timeIntervalSince(p.since) >= turnDwell {
            current = raw
            pending = nil
        }
        return current
    }

    /// Wajah tidak terbaca (mata terpejam, tangan menutupi): tahan keputusan terakhir sebentar.
    private mutating func holdWhileLost(now: Date) -> ZoomTarget? {
        if let seen = lastSeen, now.timeIntervalSince(seen) < lostGrace {
            pending = nil
            return current
        }
        reset()
        return nil
    }

    /// Catat puncak tiap noleh yang disengaja, lalu geser ambang pelan-pelan.
    private mutating func trackEpisode(before: ZoomTarget?, now: Date) {
        if current != nil {
            if before == nil {
                episodeStart = now
                episodePeak = 0
            }
            episodePeak = max(episodePeak, abs(relativeYaw))
        } else if before != nil, let start = episodeStart {
            episodeStart = nil
            guard now.timeIntervalSince(start) >= 0.6 else { return }
            let old = profile.turnPeak > 0 ? profile.turnPeak : 33.0
            let peak = min(max(episodePeak, 20), 45)
            profile.turnPeak = old + 0.25 * (peak - old)
        }
    }

    /// Haluskan zoom sisi wajah setelah gate lolos. `active` = sisi dari target final (nil kalau bukan sisi wajah).
    mutating func updateSideBlend(active: FaceSide?, now: Date) {
        let dt = min(max(blendTime.map { now.timeIntervalSince($0) } ?? 0.033, 0.001), 0.1)
        blendTime = now
        if let active { heldSide = active }

        var goal: CGFloat = 0
        if active != nil, smoothedYaw != nil {
            let raw = (abs(relativeYaw) - exitAngle) / (fullAngle - exitAngle)
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
        lastTime = nil
        lastSeen = nil
        episodeStart = nil
    }

    private func classify(_ yaw: Double) -> ZoomTarget? {
        let limit = current == nil ? enterAngle : exitAngle
        guard abs(yaw) >= limit else { return nil }
        // Zoom ke sisi wajah yang menghadap kamera (berlawanan dengan arah hidung)
        return .faceSide(yaw > 0 ? .left : .right)
    }
}
