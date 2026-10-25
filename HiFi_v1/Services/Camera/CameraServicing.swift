//
//  CameraServicing.swift
//  HiFi_v1
//
//  Created by Davin P on 25/10/26.
//


import AVFoundation

protocol CameraServicing: AnyObject {
    var session: AVCaptureSession { get }
    func permissionStatus() -> CameraPermissionStatus
    func requestPermission() async -> Bool
    func start()
    func stop()
}