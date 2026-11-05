import Foundation

nonisolated struct HeadPoseRecognizer {
    var defaultTurnEnter = 20.0     // derajat, untuk pengguna baru
    var minTurnEnter = ZoomTuning.minTurnEnter   // derajat, batas bawah ambang masuk (naik dari 14)
    var maxTurnEnter = 24.0
    var turnDwell: TimeInterval = ZoomTuning.sideEnterDwell      // noleh harus bertahan sebelum masuk
    var turnExitDwell: TimeInterval = ZoomTuning.sideExitDwell   // rileks harus bertahan sebelum keluar
    var yawTau = ZoomTuning.yawTau  // detik, penghalus yaw berbasis waktu
    var maxYawRate = 60.0           // derajat/detik; lebih cepat dari ini dianggap masih bergerak
    var yawSign = 1.0               // ganti -1 kalau zoom noleh ke sisi yang salah
    var lostGrace: TimeInterval = 0.8   // wajah hilang sesingkat ini: zoom ditahan, bukan dilepas
    var coverGrace: TimeInterval = ZoomTuning.coverGrace   // sama, tapi saat tangan/brush menutupi wajah (ada batasnya)
    var maxBaseline = 8.0           // batas geser posisi "lurus" yang boleh dipelajari
    var baselineTau = 6.0           // detik, makin besar makin pelan belajarnya

    private(set) var profile: HeadProfile
    private(set) var current: ZoomTarget?
    /// Kepala sedang di zona lurus (terbaca wajahnya, yaw di bawah sudut keluar, tidak sedang dibekukan).
    /// Salah kalau wajah tidak terbaca. Dipakai resolver untuk membuka kunci zoom samping.
    private(set) var isStraight = false

    /// Nilai `turnPeak` di awal pemakaian app. Total geser per sesi dibatasi di sekitar nilai ini
    /// (`ZoomTuning.turnLearnSessionCap`), walau recognizer dibuat ulang saat reset sesi.
    let turnAnchor: Double

    private var pending: (target: ZoomTarget, since: Date)?
    private var exitPending: Date?
    private var smoothedYaw: Double?
    private var lastTime: Date?
    private var lastSeen: Date?
    private var episodeStart: Date?
    private var episodePeak = 0.0
    private var episodeSettled: TimeInterval = 0   // lama noleh yang sudah menetap (kepala tidak sedang bergerak)

    // Catatan langkah terakhir, dipakai trackEpisode
    private var sawFace = false
    private var stepDt: TimeInterval = 0
    private var stepYawRate = 0.0

    init(profile: HeadProfile = HeadProfile(), turnAnchor: Double? = nil) {
        var p = profile
        p.yawBaseline = min(max(p.yawBaseline, -8), 8)
        if p.turnPeak != 0 { p.turnPeak = min(max(p.turnPeak, 20), 45) }
        self.profile = p
        self.turnAnchor = turnAnchor ?? (p.turnPeak > 0 ? p.turnPeak : ZoomTuning.turnPeakDefault)
    }

    // Ambang mengikuti kebiasaan noleh pengguna. Tanpa data: 20 derajat masuk, setengahnya keluar.
    private var enterAngle: Double {
        guard profile.turnPeak > 0 else { return defaultTurnEnter }
        return min(max(profile.turnPeak * 0.6, minTurnEnter), maxTurnEnter)
    }
    private var exitAngle: Double { enterAngle * 0.5 }
    private var relativeYaw: Double { (smoothedYaw ?? 0) - profile.yawBaseline }

    /// Dipanggil hanya saat ada hasil deteksi wajah baru. `now` = cap waktu deteksi itu.
    /// `learn` = boleh belajar posisi lurus (false saat belajar dijeda atau tangan sedang aktif).
    /// `covered` = wajah sengaja tidak diberikan karena tangan/brush menutupinya, jadi hilangnya data
    /// ditahan lebih lama (`coverGrace`) dan tidak dianggap user selesai.
    /// `yawFrozen` = kepala sedang dongak/tunduk cepat, yaw tidak bisa dipercaya: keputusan ditahan.
    mutating func update(face: FaceObservation?, learn: Bool, covered: Bool = false,
                         yawFrozen: Bool = false, now: Date) -> ZoomTarget? {
        let before = current
        sawFace = false
        isStraight = false
        let result = step(face: face, learn: learn, covered: covered, yawFrozen: yawFrozen, now: now)
        trackEpisode(before: before, now: now)
        return result
    }

    /// Pengguna zoom out manual tak lama setelah zoom samping muncul: naikkan sedikit ambang noleh.
    /// Naiknya dibatasi per sesi dan tidak pernah menurunkan nilai.
    mutating func noteUnwantedSide() {
        let old = profile.turnPeak > 0 ? profile.turnPeak : ZoomTuning.turnPeakDefault
        let limit = min(turnAnchor + ZoomTuning.turnLearnSessionCap, 45)
        profile.turnPeak = max(old, min(old + ZoomTuning.turnUnwantedStep, limit))
    }

    private mutating func step(face: FaceObservation?, learn: Bool, covered: Bool,
                               yawFrozen: Bool, now: Date) -> ZoomTarget? {
        guard let face, face.yaw.isFinite else { return holdWhileLost(covered: covered, now: now) }
        lastSeen = now
        let dt = max(lastTime.map { now.timeIntervalSince($0) } ?? ZoomTuning.nominalStep, 0.001)
        lastTime = now

        let rawYaw = face.yaw * yawSign
        let previousYaw = smoothedYaw ?? rawYaw
        // Penghalus berbasis waktu: hasilnya sama berapa pun laju deteksinya
        let alpha = 1 - exp(-min(dt, ZoomTuning.maxStep) / yawTau)
        let smoothed = previousYaw + alpha * (rawYaw - previousYaw)
        smoothedYaw = smoothed
        let yawRate = abs(smoothed - previousYaw) / dt

        // Dongak/tunduk cepat bisa menggeser estimasi yaw: jangan putuskan apa pun, tahan yang sekarang
        if yawFrozen {
            pending = nil
            return current
        }
        sawFace = true
        stepDt = dt
        stepYawRate = yawRate
        isStraight = abs(relativeYaw) < exitAngle

        // Posisi lurus hanya dipelajari saat kepala lurus, stabil, dan tidak ada gesture
        if learn, current == nil, pending == nil,
           abs(relativeYaw) < exitAngle, yawRate < maxYawRate / 3 {
            let k = 1 - exp(-min(dt, ZoomTuning.maxStep) / baselineTau)
            let moved = profile.yawBaseline + (smoothed - profile.yawBaseline) * k
            profile.yawBaseline = min(max(moved, -maxBaseline), maxBaseline)
        }

        guard let raw = classify(relativeYaw) else {
            pending = nil
            guard current != nil else {
                exitPending = nil
                return nil
            }
            // Kepala sudah di zona rileks: zoom baru dilepas kalau bertahan selama dwell keluar,
            // supaya kepala yang kembali lurus sebentar tidak langsung menurunkan zoom.
            if exitPending == nil { exitPending = now }
            if let since = exitPending, now.timeIntervalSince(since) >= turnExitDwell {
                current = nil
                exitPending = nil
            }
            return current
        }
        exitPending = nil
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
    private mutating func holdWhileLost(covered: Bool, now: Date) -> ZoomTarget? {
        let grace = covered ? max(lostGrace, coverGrace) : lostGrace
        if let seen = lastSeen, now.timeIntervalSince(seen) < grace {
            pending = nil
            return current
        }
        reset()
        return nil
    }

    /// Catat puncak noleh yang disengaja, lalu geser ambang pelan-pelan. Hanya noleh yang sudah menetap
    /// (kepala diam di sudut itu) selama `turnLearnMinEpisode` yang dihitung; puncak diambil dari saat menetap.
    private mutating func trackEpisode(before: ZoomTarget?, now: Date) {
        if current != nil {
            if before == nil {
                episodeStart = now
                episodePeak = 0
                episodeSettled = 0
            }
            if sawFace, stepYawRate < maxYawRate / 3, abs(relativeYaw) >= exitAngle {
                episodeSettled += min(stepDt, ZoomTuning.maxStep)
                episodePeak = max(episodePeak, abs(relativeYaw))
            }
        } else if before != nil, episodeStart != nil {
            episodeStart = nil
            guard episodeSettled >= ZoomTuning.turnLearnMinEpisode else { return }
            let old = profile.turnPeak > 0 ? profile.turnPeak : ZoomTuning.turnPeakDefault
            let peak = min(max(episodePeak, 20), 45)
            var moved = old + ZoomTuning.turnLearnStep * (peak - old)
            // Batas total geser per sesi
            moved = min(max(moved, turnAnchor - ZoomTuning.turnLearnSessionCap),
                        turnAnchor + ZoomTuning.turnLearnSessionCap)
            profile.turnPeak = min(max(moved, 20), 45)
        }
    }

    private mutating func reset() {
        current = nil
        pending = nil
        exitPending = nil
        smoothedYaw = nil
        lastTime = nil
        lastSeen = nil
        episodeStart = nil
    }

    private func classify(_ yaw: Double) -> ZoomTarget? {
        // Hysteresis: masuk di sudut besar, keluar di sudut kecil
        let limit = current == nil ? enterAngle : exitAngle
        guard abs(yaw) >= limit else { return nil }
        // Zoom ke sisi wajah yang menghadap kamera (berlawanan dengan arah hidung)
        return .faceSide(yaw > 0 ? .left : .right)
    }
}
