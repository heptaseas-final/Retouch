//
//  ZoomTracking.swift
//  Retouch
//

import CoreGraphics

nonisolated struct ZoomTracking: Sendable {
    var target: ZoomTarget = .fullFace
    var face = FacePoints()
    var viewSize: CGSize = .zero
}
