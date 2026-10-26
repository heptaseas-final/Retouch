//
//  ZoomDebugInfo.swift
//  HiFi_v1
//
//  Created by Davin P on 26/10/26.
//
import CoreGraphics

nonisolated struct ZoomDebugInfo: Equatable {
    var target = "full face"
    var distLeftEye: CGFloat?       // jarak ujung brush ke tiap fitur, rasio tinggi layar
    var distRightEye: CGFloat?
    var distLips: CGFloat?
    var handsSeen = 0               // tangan yang terlihat Vision
    var gripCount = 0               // tangan yang lolos sebagai "menjepit"
    var pinchRatio: CGFloat?        // makin kecil makin rapat; lolos kalau di bawah 0.5
    var handConfidence: Float = 0
    var yaw = 0.0
    var down = 0.0
    var ratio = 0.0
    var baseline = 0.0
    var faceAspect = 0.0
    var headState = "-"
    var idleTime = 0.0
    var exitHold = 2.0
    var fps = 0
    var handFps = 0
    var gripPoint: CGPoint?         // koordinat layar
    var tipPoint: CGPoint?
    var targetPoint: CGPoint?
}

nonisolated extension ZoomTarget {
    var debugName: String {
        switch self {
        case .fullFace: "full face"
        case .leftEye: "mata L"
        case .rightEye: "mata R"
        case .lips: "bibir"
        case .forehead: "dahi"
        case .faceSide(let side): side == .left ? "sisi kiri" : "sisi kanan"
        }
    }
}
