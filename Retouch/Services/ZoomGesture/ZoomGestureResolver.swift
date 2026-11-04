import Foundation

nonisolated struct ZoomGestureResolver {
    var exitHold: TimeInterval = ZoomTuning.exitHold   // jeda sebelum turun tingkat atau zoom out penuh (tetap, tidak dipelajari)
    // Dwell di sini adalah penjaga kedua; dwell utama untuk target tangan ada di HandProximityRecognizer
    var switchDwell: TimeInterval = ZoomTuning.resolverSwitchDwell        // pindah antar target (termasuk mata L/R)
    var lipsSwitchDwell: TimeInterval = ZoomTuning.resolverLipsSwitchDwell   // pindah ke bibir dari target lain
    var lipsFirstDwell: TimeInterval = ZoomTuning.resolverLipsFirstDwell     // zoom pertama ke bibir dari full face
    var handCooldown: TimeInterval = 0.5      // kepala ditekan setelah tangan hilang (target non-tangan)
    var exitCooldown: TimeInterval = 1.0      // kepala ditekan setelah zoom out
    var coverHold: TimeInterval = ZoomTuning.coverHold   // tahan zoom saat tangan menutupi wajah (ada batasnya)

    private(set) var target: ZoomTarget = .fullFace
    /// Sejak ada aktivitas tangan (mata/bibir), zoom samping diblok sampai kepala lurus sekali.
    /// Menoleh yang sudah jadi posisi makeup tidak boleh berubah jadi zoom samping begitu tangan pergi.
    private(set) var headLocked = false
    private var straightSince: Date?
    private var lastActive = Date.distantPast
    private var lastHandSeen = Date.distantPast
    private var lastExit = Date.distantPast
    private var pending: (target: ZoomTarget, since: Date)?

    init(exitHold: TimeInterval = ZoomTuning.exitHold) { self.exitHold = exitHold }

    /// `head` = keputusan mentah dari HeadPoseRecognizer. `covering` = tangan/brush sedang menutupi wajah,
    /// jadi data wajah bisa hilang sebentar dan itu bukan tanda user selesai.
    /// `headStraight` = kepala sedang lurus (HeadPoseRecognizer.isStraight).
    mutating func resolve(hand: ZoomTarget?, head: ZoomTarget?, covering: Bool, headStraight: Bool,
                          now: Date) -> ZoomTarget {
        if hand != nil { lastHandSeen = now }
        let handDriven = Self.isHandTarget(target)
        updateHeadLock(handActive: hand != nil || handDriven, head: head, headStraight: headStraight, now: now)

        // Dari mata/bibir, kepala baru boleh mengambil alih setelah jeda (bukan hanya cooldown singkat).
        // Selama tangan menutupi wajah, zoom mata/bibir tidak diserahkan ke kepala.
        let settle = handDriven ? exitHold : handCooldown
        let headAllowed = now.timeIntervalSince(lastHandSeen) >= settle
            && now.timeIntervalSince(lastExit) >= exitCooldown
            && !(covering && handDriven)
            && !headLocked

        guard let candidate = hand ?? (headAllowed ? head : nil) else {
            pending = nil
            // Tangan menutupi wajah: tahan lebih lama, tetap ada batas (dihitung dari aktivitas terakhir)
            let hold = covering ? max(exitHold, coverHold) : exitHold
            if target != .fullFace, now.timeIntervalSince(lastActive) >= hold {
                zoomOut(at: now)
            }
            return target
        }

        lastActive = now
        if candidate == target {
            pending = nil
            return target
        }
        if pending?.target != candidate { pending = (candidate, now) }

        let isFirst = target == .fullFace
        let dwell: TimeInterval
        if candidate == .lips {
            dwell = isFirst ? lipsFirstDwell : lipsSwitchDwell
        } else {
            // Mata L ke mata R juga memakai dwell, tidak lagi langsung
            dwell = isFirst ? 0 : switchDwell
        }
        if let p = pending, now.timeIntervalSince(p.since) >= dwell {
            target = candidate
            pending = nil
        }
        return target
    }

    /// Kunci dipasang selama ada aktivitas tangan. Dibuka kalau tangan sudah tidak aktif, kepala lurus
    /// selama `headRearmStraight`, dan HeadPoseRecognizer juga sudah melepas keputusan sampingnya
    /// (supaya sisa hysteresis tidak memunculkan zoom samping tepat setelah kunci dibuka).
    private mutating func updateHeadLock(handActive: Bool, head: ZoomTarget?, headStraight: Bool, now: Date) {
        guard ZoomTuning.headRearmEnabled else {
            headLocked = false
            return
        }
        if handActive {
            headLocked = true
            straightSince = nil
            return
        }
        guard headLocked else { return }
        if headStraight, head == nil {
            if straightSince == nil { straightSince = now }
            if let since = straightSince, now.timeIntervalSince(since) >= ZoomTuning.headRearmStraight {
                headLocked = false
                straightSince = nil
            }
        } else {
            straightSince = nil
        }
    }

    private mutating func zoomOut(at now: Date) {
        target = .fullFace
        lastExit = now
        pending = nil
    }

    private static func isEye(_ t: ZoomTarget) -> Bool { t == .leftEye || t == .rightEye }
    private static func isHandTarget(_ t: ZoomTarget) -> Bool { isEye(t) || t == .lips }

    func idleTime(now: Date) -> TimeInterval {
        target == .fullFace ? 0 : now.timeIntervalSince(lastActive)
    }
}
