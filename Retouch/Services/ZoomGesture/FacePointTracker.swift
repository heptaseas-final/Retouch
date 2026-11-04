import CoreGraphics
import Foundation

nonisolated struct FacePointTracker {
    var pointTau: CGFloat = ZoomTuning.pointTau     // detik, penghalus titik wajah
    var scaleTau: CGFloat = ZoomTuning.scaleTau     // detik, penghalus skala wajah
    var maxScaleYaw = 30.0
    private(set) var points = FacePoints()
    private var lastTime: Date?

    /// `now` = cap waktu hasil deteksi wajah, dipakai untuk penghalus berbasis waktu.
    mutating func update(face: FaceObservation?, covering: Bool, converter: CoordinateConverter,
                         now: Date) -> FacePoints {
        guard let face, !covering else { return points }
        let dt = min(max(lastTime.map { now.timeIntervalSince($0) } ?? ZoomTuning.nominalStep, 0.001),
                     ZoomTuning.maxStep)
        lastTime = now
        let alpha = CGFloat(1 - exp(-dt / Double(pointTau)))
        points.leftEye = smooth(points.leftEye, face.leftEye.map(converter.toView), alpha)
        points.rightEye = smooth(points.rightEye, face.rightEye.map(converter.toView), alpha)
        points.lips = smooth(points.lips, face.lips.map(converter.toView), alpha)
        points.center = smooth(points.center, converter.toView(face.center), alpha)
        learnWidth(face: face, converter: converter, dt: dt)
        learnScale(face: face, converter: converter, dt: dt)
        return points
    }

    /// Lebar wajah = satuan jarak tangan. Dihaluskan pelan dan dibekukan saat kepala menoleh
    /// (lebar kotak wajah mengecil saat noleh), supaya ambang tangan tidak bergeser.
    private mutating func learnWidth(face: FaceObservation, converter: CoordinateConverter, dt: TimeInterval) {
        let raw = converter.width(face.width)
        guard points.width > 0 else {
            points.width = raw
            return
        }
        guard abs(face.yaw) < maxScaleYaw else { return }
        let alpha = CGFloat(1 - exp(-dt / Double(ZoomTuning.widthTau)))
        points.width += (raw - points.width) * alpha
    }

    private mutating func learnScale(face: FaceObservation, converter: CoordinateConverter, dt: TimeInterval) {
        guard abs(face.yaw) < maxScaleYaw,
              let l = face.leftEye.map(converter.toView),
              let r = face.rightEye.map(converter.toView) else { return }
        let cosYaw = CGFloat(max(cos(face.yaw * .pi / 180), 0.6))
        let sample = hypot(l.x - r.x, l.y - r.y) / cosYaw
        let alpha = CGFloat(1 - exp(-dt / Double(scaleTau)))
        points.scale = points.scale == 0
            ? sample
            : points.scale + (sample - points.scale) * alpha
    }

    private func smooth(_ old: CGPoint?, _ new: CGPoint?, _ alpha: CGFloat) -> CGPoint? {
        guard let new else { return old }
        guard let old else { return new }
        return CGPoint(x: old.x + (new.x - old.x) * alpha,
                       y: old.y + (new.y - old.y) * alpha)
    }
}
