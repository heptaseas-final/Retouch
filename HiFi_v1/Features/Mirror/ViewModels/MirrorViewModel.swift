//
//  MirrorViewModel.swift
//  HiFi_v1
//
//  Created by Davin P on 25/10/26.
//

import SwiftUI
import AVFoundation
import Combine
import Observation

@MainActor
@Observable
final class MirrorViewModel {
    private(set) var permission: CameraPermissionStatus
    private let camera: CameraServicing
    private(set) var isZoomBarVisible = false
    private(set) var selectedPart: ZoomPart = .face

    var isZoomActive: Bool { selectedPart != .face }
    var session: AVCaptureSession { camera.session }
    
    func toggleZoomBar() { isZoomBarVisible.toggle() }
    func select(_ part: ZoomPart) { selectedPart = part }

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

    /// dipanggil saat app active lagi, semisal setelah dari Settings
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
