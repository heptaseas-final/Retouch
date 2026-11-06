//import CoreGraphics
//import Foundation
//
///// Tangan / brush dekat mata atau mulut. Semua jarak dalam satuan lebar wajah yang sudah dihaluskan
///// (FacePoints.width).
//nonisolated struct HandProximityRecognizer {
//    var enterDistance = CGFloat(ZoomTuning.handEnterDistance)
//    var exitDistance = CGFloat(ZoomTuning.handEnterDistance) * 1.5
//    var eyeEnterFactor = ZoomTuning.eyeEnterFactor
//    var enterDwell = ZoomTuning.handEnterDwell
//    var eyeEnterDwell = ZoomTuning.eyeEnterDwell
//    var winMargin = ZoomTuning.handWinMargin
//    var switchRatio: CGFloat = 0.85
//    var switchMargin = ZoomTuning.handSwitchMargin
//    var switchHold = ZoomTuning.handSwitchDwell
//    var holdGrace = ZoomTuning.handHoldGrace
//    var coverDistance = ZoomTuning.coverDistance
//    var maxIntentSpeed = CGFloat(ZoomTuning.handMaxSpeed)   // lebar wajah/detik; lebih cepat = tangan cuma lewat
//    var jumpDistance: CGFloat = 0.9     // loncatan posisi tangan (lebar wajah) dianggap tangan baru
//    var speedTau = ZoomTuning.handSpeedTau     // detik, penghalus kecepatan tangan
//    var maxHandGap = ZoomTuning.handMaxGap     // detik, jeda lebih lama dari ini = tangan baru
//
//    private var filterX = OneEuroFilter()
//    private var filterY = OneEuroFilter()
//    private var lastHandTime: TimeInterval = 0
//    private var prevHand: CGPoint?
//    private var enterCandidate: (target: ZoomTarget, since: Date)?
//    private var switchPending: (target: ZoomTarget, since: Date)?
//    private var outSince: Date?
//    private(set) var current: ZoomTarget?
//    private(set) var speed: CGFloat = 0   // lebar wajah/detik, sudah dihaluskan
//    private(set) var lastDistance: CGFloat = .infinity
//
//    init(profile: HandProfile = HandProfile()) { apply(profile) }
//
//    /// Ubah sensitivitas tanpa menghapus state tracking.
//    mutating func apply(_ profile: HandProfile) {
//        enterDistance = CGFloat(profile.enterDistance)
//        exitDistance = enterDistance * 1.5
//        maxIntentSpeed = CGFloat(profile.maxIntentSpeed)
//    }
//
//    /// Pilih tangan paling dekat ke wajah (tangan di paha diabaikan), haluskan, dan ukur kecepatannya.
//    /// Dipanggil hanya saat ada hasil deteksi tangan baru; `now` = cap waktu deteksi itu.
//    /// `H` hanya dipakai untuk normalisasi filter, bukan untuk jarak.
//    mutating func trackHand(_ candidates: [CGPoint], points: FacePoints,
//                            viewHeight H: CGFloat, now: Date) -> CGPoint? {
//        let W = points.width
//        guard !candidates.isEmpty, W > 0 else {
//            prevHand = nil
//            return nil
//        }
//        let anchors = points.handTargets.map { $0.1 }
//        var chosen = candidates[0]
//        if !anchors.isEmpty {
//            var best = CGFloat.infinity
//            for c in candidates {
//                let d = anchors.map { hypot(c.x - $0.x, c.y - $0.y) }.min() ?? .infinity
//                if d < best {
//                    best = d
//                    chosen = c
//                }
//            }
//        }
//        let t = now.timeIntervalSinceReferenceDate
//        let dt = max(t - lastHandTime, 0.001)
//        var jumped = true
//        if let prev = prevHand, dt <= maxHandGap,
//           hypot(chosen.x - prev.x, chosen.y - prev.y) / W <= jumpDistance {
//            jumped = false
//        }
//        if jumped {
//            filterX.reset()
//            filterY.reset()
//        }
//        lastHandTime = t
//
//        let nx = filterX.filter(Double(chosen.x / H), t: t)
//        let ny = filterY.filter(Double(chosen.y / H), t: t)
//        let p = CGPoint(x: CGFloat(nx) * H, y: CGFloat(ny) * H)
//        lastDistance = (anchors.map { hypot(p.x - $0.x, p.y - $0.y) }.min() ?? .infinity) / W
//
//        if jumped {
//            speed = maxIntentSpeed * 2   // tangan baru muncul: tahan sampai kecepatannya terukur
//        } else if let prev = prevHand {
//            let instant = hypot(p.x - prev.x, p.y - prev.y) / W / CGFloat(dt)
//            // Penghalus berbasis waktu, bukan per frame
//            let alpha = CGFloat(1 - exp(-min(dt, ZoomTuning.maxStep) / Double(speedTau)))
//            speed += alpha * (instant - speed)
//        }
//        prevHand = p
//        return p
//    }
//
//    /// Tangan di dekat wajah, posisinya dikunci. Zona sengaja kecil supaya brush di pipi/dahi
//    /// tidak mematikan data kepala.
//    func isCovering(hand: CGPoint?, points: FacePoints) -> Bool {
//        guard let h = hand, points.width > 0 else { return false }
//        return points.handTargets.contains {
//            hypot(h.x - $0.1.x, h.y - $0.1.y) / points.width < coverDistance
//        }
//    }
//
//    /// Dipanggil hanya saat ada hasil deteksi tangan baru.
//    /// Masuk: tangan dekat fitur yang sama, bergerak pelan, dan jelas lebih dekat dari fitur lain,
//    /// selama dwell. Pindah: target baru jelas lebih dekat dari target aktif, selama dwell.
//    /// `headSupport` = kepala sedang mendongak (Tahap 5). Hanya memperkuat: radius masuk sedikit lebih lebar
//    /// dan dwell sedikit lebih pendek. Tanpa tangan, dongak tidak melakukan apa-apa.
//    mutating func update(hand: CGPoint?, points: FacePoints, headSupport: Bool = false, now: Date) -> ZoomTarget? {
//        let W = points.width
//        var ranked: [(target: ZoomTarget, dist: CGFloat)] = []
//        if let h = hand, W > 0 {
//            ranked = points.handTargets
//                .map { (target: $0.0, dist: hypot(h.x - $0.1.x, h.y - $0.1.y) / W) }
//                .sorted { $0.dist < $1.dist }
//        }
//        let best = ranked.first
//        let secondDist = ranked.dropFirst().first?.dist ?? .infinity
//
//        // Syarat niat: cukup dekat, pelan, dan menang jelas atas kandidat kedua
//        var intent = false
//        if let b = best {
//            var limit = Self.isEye(b.target) ? enterDistance * eyeEnterFactor : enterDistance
//            if headSupport { limit *= Self.isEye(b.target) ? ZoomTuning.pitchEyeReach : ZoomTuning.pitchLipsReach }
//            intent = b.dist < limit && speed < maxIntentSpeed && secondDist - b.dist >= winMargin
//        }
//
//        guard let cur = current else {
//            outSince = nil
//            switchPending = nil
//            if intent, let b = best {
//                if enterCandidate?.target != b.target { enterCandidate = (b.target, now) }
//                var need = Self.isEye(b.target) ? eyeEnterDwell : enterDwell
//                if headSupport {
//                    need *= Self.isEye(b.target) ? ZoomTuning.pitchEyeDwellFactor : ZoomTuning.pitchLipsDwellFactor
//                }
//                if let c = enterCandidate, now.timeIntervalSince(c.since) >= need {
//                    current = c.target
//                    enterCandidate = nil
//                }
//            } else {
//                enterCandidate = nil
//            }
//            return current
//        }
//        enterCandidate = nil
//
//        // Bertahan: selama masih di dalam radius keluar. Terlepas hanya kalau di luar cukup lama.
//        var holdDist = best?.dist ?? .infinity
//        var curPos: CGPoint?
//        if let h = hand, W > 0, let p = Self.position(of: cur, in: points) {
//            holdDist = hypot(h.x - p.x, h.y - p.y) / W
//            curPos = p
//        }
//        if holdDist < exitDistance {
//            outSince = nil
//        } else {
//            if outSince == nil { outSince = now }
//            if let since = outSince, now.timeIntervalSince(since) >= holdGrace {
//                current = nil
//                outSince = nil
//                switchPending = nil
//                return current
//            }
//        }
//
//        var wantsSwitch = false
//        if intent, let b = best, b.target != cur, let h = hand, W > 0, let cp = curPos {
//            let curDist = hypot(h.x - cp.x, h.y - cp.y) / W
//            wantsSwitch = b.dist < switchRatio * curDist && curDist - b.dist >= switchMargin
//        }
//        if wantsSwitch, let b = best {
//            if switchPending?.target != b.target { switchPending = (b.target, now) }
//            if let p = switchPending, now.timeIntervalSince(p.since) >= switchHold {
//                current = b.target
//                outSince = nil
//                switchPending = nil
//            }
//        } else {
//            switchPending = nil
//        }
//        return current
//    }
//
//    private static func isEye(_ t: ZoomTarget) -> Bool { t == .leftEye || t == .rightEye }
//
//    private static func position(of target: ZoomTarget, in p: FacePoints) -> CGPoint? {
//        switch target {
//        case .leftEye: p.leftEye
//        case .rightEye: p.rightEye
//        case .lips: p.lips
//        default: nil
//        }
//    }
//}
