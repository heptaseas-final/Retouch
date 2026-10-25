//
//  CameraServicing.swift
//  HiFi_v1
//
//  Created by Davin P on 25/10/26.
//

import AVFoundation

nonisolated protocol CameraServicing: AnyObject, Sendable {
    var session: AVCaptureSession { get }
    var frameHandler: (@Sendable (CVPixelBuffer) -> Void)? { get set }
    func permissionStatus() -> CameraPermissionStatus
    func requestPermission() async -> Bool
    func start()
    func stop()
}
