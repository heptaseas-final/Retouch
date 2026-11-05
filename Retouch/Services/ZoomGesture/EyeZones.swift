import CoreGraphics

nonisolated enum EyeSide { case left, right }

nonisolated struct EyeZones {
    private let leftEye: CGPoint
    private let rightEye: CGPoint
    private let mid: CGPoint
    private let u: CGPoint
    private let v: CGPoint
    private let d: CGFloat
    private let lipsT: CGFloat?
    
    var triggerScale: CGFloat = 1

    init?(points: FacePoints) {
        guard let l = points.leftEye, let r = points.rightEye, points.scale > 0 else { return nil }
        let len = hypot(r.x - l.x, r.y - l.y)
        guard len > 0 else { return nil }
        leftEye = l
        rightEye = r
        d = points.scale
        mid = CGPoint(x: (l.x + r.x) / 2, y: (l.y + r.y) / 2)
        u = CGPoint(x: (r.x - l.x) / len, y: (r.y - l.y) / len)
        v = CGPoint(x: -u.y, y: u.x)
        if let lips = points.lips {
            lipsT = ((lips.x - mid.x) * v.x + (lips.y - mid.y) * v.y) / points.scale
        } else {
            lipsT = nil
        }
    }

    func s(_ p: CGPoint) -> CGFloat { ((p.x - mid.x) * u.x + (p.y - mid.y) * u.y) / d }

    func t(_ p: CGPoint) -> CGFloat { ((p.x - mid.x) * v.x + (p.y - mid.y) * v.y) / d }

    func isLipsSide(_ p: CGPoint) -> Bool {
        guard let lt = lipsT, lt > 0 else { return false }
        return t(p) > lt * 0.5
    }

    private func eye(_ side: EyeSide) -> CGPoint { side == .left ? leftEye : rightEye }

    func distance(_ p: CGPoint, to side: EyeSide) -> CGFloat {
        let e = eye(side)
        return hypot(p.x - e.x, p.y - e.y) / d
    }

    func triggerEye(at p: CGPoint) -> EyeSide? {
        guard !isLipsSide(p) else { return nil }
        let dl = distance(p, to: .left), dr = distance(p, to: .right)
        let r = ZoomTuning.eyeZoneTrigger * triggerScale
        // Dengan d yang benar lingkaran tidak overlap; kalau d meleset sedikit, yang lebih dekat menang
        if dl <= r, dl <= dr { return .left }
        if dr <= r { return .right }
        return nil
    }

    func holds(_ side: EyeSide, at p: CGPoint) -> Bool {
        guard !isLipsSide(p), distance(p, to: side) <= ZoomTuning.eyeZoneHold else { return false }
        let x = s(p)
        let dead = ZoomTuning.eyeZoneDead
        return side == .left ? x <= dead : x >= -dead
    }
}
