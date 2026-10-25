//
//  MirrorViewModel.swift
//  HiFi_v1
//
//  Created by Davin P on 25/10/26.
//


import SwiftUI
import AVFoundation
import Combine

@MainActor
final class MirrorViewModel: ObservableObject {
    @Published private(set) var permission: CameraPermissionStatus
    private let camera: CameraServicing

    var session: AVCaptureSession { camera.session }

    init(camera: CameraServicing = CameraService()) {
        self.camera = camera
        self.permission = camera.permissionStatus()
    }

    func start() async {
        if permission == .notDetermined {
            permission = await camera.requestPermission() ? .granted : .denied
        }
        if permission == .granted { camera.start() }
    }

    func stop() { camera.stop() }

    /// Dipanggil saat app aktif lagi, misalnya kembali dari Settings.
    func refresh() {
        guard permission != .notDetermined else { return }
        permission = camera.permissionStatus()
        if permission == .granted { camera.start() }
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}