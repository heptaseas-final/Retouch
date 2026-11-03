import CoreGraphics
import Foundation

nonisolated struct FacePointTracker {
    var smoothing: CGFloat = 0.25
    var scaleSmoothing: CGFloat = 0.05
    var maxScaleYaw = 30.0
    private(set) var points = FacePoints()

    mutating func update(face: FaceObservation?, covering: Bool, converter: CoordinateConverter) -> FacePoints {
        guard let face, !covering else { return points }
        points.leftEye = smooth(points.leftEye, face.leftEye.map(converter.toView))
        points.rightEye = smooth(points.rightEye, face.rightEye.map(converter.toView))
        points.lips = smooth(points.lips, face.lips.map(converter.toView))
        points.center = smooth(points.center, converter.toView(face.center))
        points.width = converter.width(face.width)
        learnScale(face: face, converter: converter)
        return points
    }

    private mutating func learnScale(face: FaceObservation, converter: CoordinateConverter) {
        guard abs(face.yaw) < maxScaleYaw,
              let l = face.leftEye.map(converter.toView),
              let r = face.rightEye.map(converter.toView) else { return }
        let cosYaw = CGFloat(max(cos(face.yaw * .pi / 180), 0.6))
        let sample = hypot(l.x - r.x, l.y - r.y) / cosYaw
        points.scale = points.scale == 0
            ? sample
            : points.scale + (sample - points.scale) * scaleSmoothing
    }

    private func smooth(_ old: CGPoint?, _ new: CGPoint?) -> CGPoint? {
        guard let new else { return old }
        guard let old else { return new }
        return CGPoint(x: old.x + (new.x - old.x) * smoothing,
                       y: old.y + (new.y - old.y) * smoothing)
    }
}
