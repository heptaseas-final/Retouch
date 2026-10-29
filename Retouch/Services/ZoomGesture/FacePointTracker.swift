//
//  FacePointTracker.swift
//  Retouch
//
//  Created by Davin P on 25/10/26.
//


import CoreGraphics

nonisolated struct FacePointTracker {
    var smoothing: CGFloat = 0.25
    private(set) var points = FacePoints()

    mutating func update(face: FaceObservation?, covering: Bool, converter: CoordinateConverter) -> FacePoints {
        guard let face, !covering else { return points }
        points.leftEye = smooth(points.leftEye, face.leftEye.map(converter.toView))
        points.rightEye = smooth(points.rightEye, face.rightEye.map(converter.toView))
        points.lips = smooth(points.lips, face.lips.map(converter.toView))
        points.forehead = smooth(points.forehead, face.forehead.map(converter.toView))
        points.center = smooth(points.center, converter.toView(face.center))
        points.width = converter.width(face.width)
        return points
    }

    private func smooth(_ old: CGPoint?, _ new: CGPoint?) -> CGPoint? {
        guard let new else { return old }
        guard let old else { return new }
        return CGPoint(x: old.x + (new.x - old.x) * smoothing,
                       y: old.y + (new.y - old.y) * smoothing)
    }
}
