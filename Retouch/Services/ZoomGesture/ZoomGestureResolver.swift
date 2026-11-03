import Foundation

nonisolated struct ZoomGestureResolver {
    var exitHold: TimeInterval = 1.0          // jeda sebelum turun tingkat atau zoom out penuh
    var quickExitConfirm: TimeInterval = 0.4  // tangan jauh + kepala lurus selama ini: zoom out langsung
    var switchDwell: TimeInterval = 0.0
    var lipsSwitchDwell: TimeInterval = 0.0   // pindah ke bibir dari target lain
    var lipsFirstDwell: TimeInterval = 0.0    // zoom pertama ke bibir dari full face
    var handCooldown: TimeInterval = 0.5      // kepala ditekan setelah tangan hilang (target non-tangan)
    var exitCooldown: TimeInterval = 1.0      // kepala ditekan setelah zoom out

    private(set) var target: ZoomTarget = .fullFace
    private var lastActive = Date.distantPast
    private var lastHandSeen = Date.distantPast
    private var lastExit = Date.distantPast
    private var farSince: Date?
    private var pending: (target: ZoomTarget, since: Date)?
    private var gapEMA: TimeInterval = 0
    private var handLostAt: Date?
    private var lastHoldExit: (target: ZoomTarget, at: Date)?

    init(exitHold: TimeInterval = 1.0) { self.exitHold = exitHold }

    /// `head` = keputusan mentah dari HeadPoseRecognizer. `handFar` = tangan sudah jauh dari semua fitur.
    mutating func resolve(hand: ZoomTarget?, head: ZoomTarget?, handFar: Bool, now: Date) -> ZoomTarget {
        if hand != nil { lastHandSeen = now }
        let handDriven = Self.isHandTarget(target)

        // Ukur jeda antar goresan: tangan hilang lalu kembali sebelum zoom turun
        if handDriven {
            if hand == nil, handLostAt == nil { handLostAt = now }
            if hand != nil, let lost = handLostAt {
                let gap = now.timeIntervalSince(lost)
                if gap > 0.15, gap < exitHold { recordGap(gap) }
                handLostAt = nil
            }
        } else {
            handLostAt = nil
        }

        // Dari mata/bibir, kepala baru boleh mengambil alih setelah jeda (bukan hanya cooldown singkat)
        let settle = handDriven ? exitHold : handCooldown
        let headAllowed = now.timeIntervalSince(lastHandSeen) >= settle
            && now.timeIntervalSince(lastExit) >= exitCooldown

        guard let candidate = hand ?? (headAllowed ? head : nil) else {
            pending = nil
            if target != .fullFace, now.timeIntervalSince(lastActive) >= exitHold {
                zoomOut(at: now, byHold: true)
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
        } else if Self.isEye(candidate), Self.isEye(target) {
            dwell = 0       // mata L ke mata R langsung, tanpa jeda
        } else {
            dwell = isFirst ? 0 : switchDwell
        }
        if let p = pending, now.timeIntervalSince(p.since) >= dwell {
            // Zoom baru turun karena jeda, lalu tangan balik ke target yang sama: turunnya terlalu cepat
            if hand != nil, let last = lastHoldExit, last.target == candidate,
               now.timeIntervalSince(last.at) < 1.5 {
                exitHold = min(exitHold * 1.1, 1.8)
                gapEMA = exitHold / 1.6
            }
            lastHoldExit = nil
            target = candidate
            pending = nil
        }
        return target
    }

    private mutating func zoomOut(at now: Date, byHold: Bool = false) {
        if byHold { lastHoldExit = (target, now) }
        target = .fullFace
        lastExit = now
        pending = nil
        farSince = nil
        handLostAt = nil
    }
    
    private mutating func recordGap(_ gap: TimeInterval) {
        gapEMA = gapEMA == 0 ? gap : gapEMA + 0.2 * (gap - gapEMA)
        exitHold = min(max(gapEMA * 1.6, 0.7), 1.8)
    }

    private static func isEye(_ t: ZoomTarget) -> Bool { t == .leftEye || t == .rightEye }
    private static func isHandTarget(_ t: ZoomTarget) -> Bool { isEye(t) || t == .lips }

    func idleTime(now: Date) -> TimeInterval {
        target == .fullFace ? 0 : now.timeIntervalSince(lastActive)
    }
}
