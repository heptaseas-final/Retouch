import Foundation

/// Noleh kanan/kiri dan menunduk. Kepala lurus mengembalikan nil.
/// Sudut diperkirakan dari landmark, jadi angkanya perkiraan dan perlu di-tuning.
nonisolated struct HeadPoseRecognizer {
    var turnEnter = 15.0
    var turnExit = 7.0
    var downEnter = 0.05          // kenaikan rasio hidung-mata dari posisi lurus
    var downExit = 0.04
    var enterDwell: TimeInterval = 0.25
    var downDwell: TimeInterval = 0.5
    var smoothing = 0.3
    var yawSign = 1.0             // ganti -1 kalau zoom noleh ke sisi yang salah
    var pitchSign = -1.0           // ganti -1 kalau menunduk tidak terdeteksi

    private(set) var current: ZoomTarget?
    private var pending: (target: ZoomTarget, since: Date)?
    private var baseline: Double?
    private var smoothed: Double?
    private var samples = 0

    mutating func update(face: FaceObservation?, now: Date) -> ZoomTarget? {
        guard let face, face.pitchRatio.isFinite else {
            current = nil
            pending = nil
            smoothed = nil
            return nil
        }
        let ratio = smoothed.map { $0 + smoothing * (face.pitchRatio - $0) } ?? face.pitchRatio
        smoothed = ratio

        // Posisi "lurus" dipelajari otomatis saat kepala tidak noleh atau menunduk
        if current == nil, abs(face.yaw) < turnExit { learnBaseline(ratio) }
        let down = (ratio - (baseline ?? ratio)) * pitchSign

        guard let raw = classify(yaw: face.yaw * yawSign, down: down) else {
            current = nil
            pending = nil
            return nil
        }
        if raw == current {
            pending = nil
            return current
        }
        if pending?.target != raw { pending = (raw, now) }
        let dwell = raw == .forehead ? downDwell : enterDwell
        if let p = pending, now.timeIntervalSince(p.since) >= dwell {
            current = raw
            pending = nil
        }
        return current
    }

    private mutating func learnBaseline(_ value: Double) {
        guard let b = baseline else {
            baseline = value
            return
        }
        let alpha = samples < 30 ? 0.1 : 0.01
        samples += 1
        baseline = b + (value - b) * alpha
    }

    private func classify(yaw: Double, down: Double) -> ZoomTarget? {
        var turnLimit = turnEnter
        if case .faceSide(_)? = current { turnLimit = turnExit }
        let downLimit = current == .forehead ? downExit : downEnter

        if abs(yaw) >= turnLimit {
            // Zoom ke sisi wajah yang menghadap kamera (berlawanan dengan arah hidung)
            return .faceSide(yaw > 0 ? .left : .right)
        }
        if down >= downLimit { return .forehead }
        return nil
    }
}
