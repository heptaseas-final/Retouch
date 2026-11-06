import Foundation

/// Membaca apakah bibir sedang bergerak (melipat, mengatup, menarik, senyum).
/// Hanya sinyal penahan: tidak pernah memicu zoom sendiri.
nonisolated struct LipMotionRecognizer {
    var baselineTau = ZoomTuning.lipMotionBaselineTau
    var devTau = ZoomTuning.lipMotionDevTau
    var enter = ZoomTuning.lipMotionEnter
    var exit = ZoomTuning.lipMotionExit
    var lostGrace = ZoomTuning.lipMotionLostGrace

    private(set) var isMoving = false
    private(set) var deviation = 0.0     // satuan jarak antar mata, sudah dihaluskan

    private struct Shape { var w: Double, h: Double, g: Double }
    private var baseline: Shape?
    private var lastTime: Date?
    private var lastSeen: Date?

    /// Dipanggil hanya saat ada hasil deteksi wajah baru. Beri `face = nil` saat tangan menutupi wajah.
    /// `ignore` = kepala sedang dongak/tunduk cepat, bentuk bibir tidak bisa dipercaya: status ditahan.
    mutating func update(face: FaceObservation?, ignore: Bool, now: Date) {
        guard let face, face.mouthWidth.isFinite, face.mouthHeight.isFinite, face.mouthGap.isFinite else {
            holdWhileLost(now: now)
            return
        }
        lastSeen = now
        let shape = Shape(w: face.mouthWidth, h: face.mouthHeight, g: face.mouthGap)
        let dt = min(max(lastTime.map { now.timeIntervalSince($0) } ?? ZoomTuning.nominalStep, 0.001),
                     ZoomTuning.maxStep)
        lastTime = now

        guard var base = baseline else {
            baseline = shape
            deviation = 0
            return
        }
        if ignore {
            baseline = shape   // jangan sampai sisa dongak terbaca sebagai gerakan bibir
            return
        }

        let raw = max(abs(shape.w - base.w), abs(shape.h - base.h), abs(shape.g - base.g))
        deviation += (1 - exp(-dt / devTau)) * (raw - deviation)

        let k = 1 - exp(-dt / baselineTau)
        base.w += (shape.w - base.w) * k
        base.h += (shape.h - base.h) * k
        base.g += (shape.g - base.g) * k
        baseline = base

        // Histeresis: masuk di simpangan besar, keluar di simpangan kecil
        if isMoving {
            if deviation < exit { isMoving = false }
        } else if deviation >= enter {
            isMoving = true
        }
    }

    private mutating func holdWhileLost(now: Date) {
        if let seen = lastSeen, now.timeIntervalSince(seen) < lostGrace { return }
        isMoving = false
        deviation = 0
        baseline = nil
        lastTime = nil
        lastSeen = nil
    }
}
