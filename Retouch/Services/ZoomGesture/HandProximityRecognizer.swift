import CoreGraphics
import Foundation

/// Tangan / brush dekat mata atau mulut. Semua jarak dalam satuan lebar wajah (FacePoints.width).
nonisolated struct HandProximityRecognizer {
    var enterDistance: CGFloat = 0.6
    var exitDistance: CGFloat = 0.9
    var switchRatio: CGFloat = 0.85
    var switchMargin: CGFloat = 0.08
    var switchHold: TimeInterval = 0.0
    var maxIntentSpeed: CGFloat = 2.5   // lebar wajah/detik; lebih cepat dari ini = tangan cuma lewat
    var jumpDistance: CGFloat = 0.9     // loncatan posisi tangan (lebar wajah) dianggap tangan baru
    var farDistance: CGFloat = 1.8             // jarak-antar-mata; lebih jauh dari semua fitur = tangan menjauh
    

    private var filterX = OneEuroFilter()
    private var filterY = OneEuroFilter()
    private var lastHandTime: TimeInterval = 0
    private var prevHand: CGPoint?
    private var switchPending: (target: ZoomTarget, since: Date)?
    private var enterVotes: [Bool] = []
    private var holdVotes: [Bool] = []
    private(set) var current: ZoomTarget?
    private(set) var speed: CGFloat = 0   // lebar wajah/detik, sudah dihaluskan
    private(set) var lastDistance: CGFloat = .infinity

    /// Pilih tangan paling dekat ke wajah (tangan di paha diabaikan), haluskan, dan ukur kecepatannya.
    /// `H` hanya dipakai untuk normalisasi filter, bukan untuk jarak.
    
    init(profile: HandProfile = HandProfile()) { apply(profile) }

    /// Ubah sensitivitas tanpa menghapus state tracking.
    mutating func apply(_ profile: HandProfile) {
        enterDistance = CGFloat(profile.enterDistance)
        exitDistance = enterDistance * 1.5
        maxIntentSpeed = CGFloat(profile.maxIntentSpeed)
    }
    
    mutating func trackHand(_ candidates: [CGPoint], points: FacePoints,
                            viewHeight H: CGFloat, now: Date) -> CGPoint? {
        let W = points.width
        guard !candidates.isEmpty, W > 0 else {
            prevHand = nil
            return nil
        }
        let anchors = points.handTargets.map { $0.1 }
        var chosen = candidates[0]
        if !anchors.isEmpty {
            var best = CGFloat.infinity
            for c in candidates {
                let d = anchors.map { hypot(c.x - $0.x, c.y - $0.y) }.min() ?? .infinity
                if d < best {
                    best = d
                    chosen = c
                }
            }
        }
        let t = now.timeIntervalSinceReferenceDate
        let dt = max(t - lastHandTime, 0.001)
        var jumped = true
        if let prev = prevHand, dt <= 0.3,
           hypot(chosen.x - prev.x, chosen.y - prev.y) / W <= jumpDistance {
            jumped = false
        }
        if jumped {
            filterX.reset()
            filterY.reset()
        }
        lastHandTime = t

        let nx = filterX.filter(Double(chosen.x / H), t: t)
        let ny = filterY.filter(Double(chosen.y / H), t: t)
        let p = CGPoint(x: CGFloat(nx) * H, y: CGFloat(ny) * H)
        lastDistance = (anchors.map { hypot(p.x - $0.x, p.y - $0.y) }.min() ?? .infinity) / W

        if jumped {
            speed = maxIntentSpeed * 2   // tangan baru muncul: tahan sampai kecepatannya terukur
        } else if let prev = prevHand {
            let instant = hypot(p.x - prev.x, p.y - prev.y) / W / CGFloat(dt)
            speed += 0.3 * (instant - speed)
        }
        prevHand = p
        return p
    }
    
    /// Tangan sudah menjauh. Kalau tangan hilang di dekat fitur, itu dianggap deteksi putus (misalnya
    /// terhalang), bukan tangan pergi, jadi tidak memicu zoom out cepat.
    func isFar(hand: CGPoint?, points: FacePoints) -> Bool {
        guard points.scale > 0 else { return false }
        guard let h = hand else { return lastDistance > exitDistance * 1.1 }
        let nearest = points.handTargets
            .map { hypot(h.x - $0.1.x, h.y - $0.1.y) }
            .min() ?? .infinity
        return nearest / points.scale > farDistance
    }

    /// Tangan di dekat wajah, posisinya dikunci.
    func isCovering(hand: CGPoint?, points: FacePoints) -> Bool {
        guard let h = hand, points.width > 0 else { return false }
        return points.handTargets.contains {
            hypot(h.x - $0.1.x, h.y - $0.1.y) / points.width < exitDistance * 1.5
        }
    }

    mutating func update(hand: CGPoint?, points: FacePoints, now: Date) -> ZoomTarget? {
        let W = points.width
        var best: (target: ZoomTarget, dist: CGFloat)?
        if let h = hand, W > 0 {
            for (target, p) in points.handTargets {
                let d = hypot(h.x - p.x, h.y - p.y) / W
                if d < (best?.dist ?? .infinity) { best = (target, d) }
            }
        }
        let dist = best?.dist ?? .infinity

        var holdDist = dist
        if let cur = current, let h = hand, W > 0, let p = Self.position(of: cur, in: points) {
            holdDist = hypot(h.x - p.x, h.y - p.y) / W
        }
        // Masuk hanya kalau gerakan pelan (niat menggores). Bertahan tidak butuh syarat kecepatan.
        Self.push(&enterVotes, dist < enterDistance && speed < maxIntentSpeed)
        Self.push(&holdVotes, holdDist < exitDistance)
        let enterOK = enterVotes.filter { $0 }.count >= 3
        let holdOK = holdVotes.contains(true)

        guard let cur = current else {
            if enterOK { current = best?.target }
            return current
        }
        if !holdOK {
            current = nil
            switchPending = nil
            enterVotes = []
            holdVotes = []
            return current
        }
        var wantsSwitch = false
        if enterOK, let b = best, b.target != cur, let h = hand, W > 0,
           let cp = Self.position(of: cur, in: points) {
            let curDist = hypot(h.x - cp.x, h.y - cp.y) / W
            wantsSwitch = b.dist < switchRatio * curDist && curDist - b.dist >= switchMargin
        }
        if wantsSwitch, let b = best {
            if switchPending?.target != b.target { switchPending = (b.target, now) }
            let bothEyes = (cur == .leftEye || cur == .rightEye) && (b.target == .leftEye || b.target == .rightEye)
            if let p = switchPending, now.timeIntervalSince(p.since) >= (bothEyes ? 0 : switchHold) {
                current = b.target
                holdVotes = [true]
                switchPending = nil
            }
        } else {
            switchPending = nil
        }
        return current
    }

    private static func position(of target: ZoomTarget, in p: FacePoints) -> CGPoint? {
        switch target {
        case .leftEye: p.leftEye
        case .rightEye: p.rightEye
        case .lips: p.lips
        default: nil
        }
    }

    private static func push(_ arr: inout [Bool], _ value: Bool) {
        arr.append(value)
        if arr.count > 5 { arr.removeFirst(arr.count - 5) }
    }
}
