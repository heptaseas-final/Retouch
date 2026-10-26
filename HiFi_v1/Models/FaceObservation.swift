//
//  FaceObservation.swift
//  HiFi_v1
//
//  Created by Davin P on 25/10/26.
//


import CoreGraphics

nonisolated struct FaceObservation {
    var leftEye: CGPoint?    // mata yang tampil di kiri layar
    var rightEye: CGPoint?   // mata yang tampil di kanan layar
    var lips: CGPoint?
    var forehead: CGPoint?
    var center: CGPoint
    var width: CGFloat
    var yaw: Double          // derajat
    var pitchRatio: Double   // derajat
}
