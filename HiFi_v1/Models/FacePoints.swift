//
//  FacePoints.swift
//  HiFi_v1
//
//  Created by Davin P on 25/10/26.
//


import CoreGraphics

nonisolated struct FacePoints {
    var leftEye: CGPoint?
    var rightEye: CGPoint?
    var lips: CGPoint?
    var forehead: CGPoint?
    var center: CGPoint?
    var width: CGFloat = 0

    /// Fitur yang bisa didekati tangan
    var handTargets: [(ZoomTarget, CGPoint)] {
        var result: [(ZoomTarget, CGPoint)] = []
        if let p = leftEye { result.append((.leftEye, p)) }
        if let p = rightEye { result.append((.rightEye, p)) }
        if let p = lips { result.append((.lips, p)) }
        return result
    }
}