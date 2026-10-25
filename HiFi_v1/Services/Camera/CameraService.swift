//
//  CameraService.swift
//  HiFi_v1
//
//  Created by Davin P on 25/10/26.
//

import AVFoundation

nonisolated final class CameraService: CameraServicing, @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "camera.session")
    private var isConfigured = false

    func permissionStatus() -> CameraPermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    func requestPermission() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    func start() {
        queue.async { [self] in
            configureIfNeeded()
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func configureIfNeeded() {
        guard !isConfigured else { return }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .high
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)
        isConfigured = true
    }
}
