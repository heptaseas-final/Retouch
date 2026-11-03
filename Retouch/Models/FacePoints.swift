//
//  FacePoints.swift
//  Retouch
//
//  Created by Davin P on 25/10/26.
//

import CoreGraphics

nonisolated struct FacePoints {
    var leftEye: CGPoint?
    var rightEye: CGPoint?
    var lips: CGPoint?
    var center: CGPoint?
    var width: CGFloat = 0
    /// Jarak antar mata di layar, dipelajari dari landmark. Penggaris semua jarak gesture.
    var scale: CGFloat = 0

    var handTargets: [(ZoomTarget, CGPoint)] {
        var result: [(ZoomTarget, CGPoint)] = []
        if let p = leftEye { result.append((.leftEye, p)) }
        if let p = rightEye { result.append((.rightEye, p)) }
        if let p = lips { result.append((.lips, p)) }
        return result
    }
}
