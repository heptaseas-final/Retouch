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
    private(set) var selectedPart: ZoomPart = .face
    private(set) var isGestureEnabled = true
    private(set) var zoomState = ZoomState()
    var isLightingSheetPresented = false

    let lighting = LightingViewModel()
    private let camera: CameraServicing
    private let zoomGesture: ZoomGestureServicing

    var session: AVCaptureSession { camera.session }
    /// Bar zoom manual muncul saat gesture dimatikan
    var isZoomBarVisible: Bool { !isGestureEnabled }

    init(camera: CameraServicing = CameraService(),
         zoomGesture: ZoomGestureServicing = ZoomGestureService()) {
        self.camera = camera
        self.zoomGesture = zoomGesture
        self.permission = camera.permissionStatus()
        camera.frameHandler = { [zoomGesture] buffer in zoomGesture.process(buffer) }
        zoomGesture.onZoomChange = { [weak self] state in
            Task { @MainActor in self?.zoomState = state }
        }
    }

    // MARK: - Kamera
    func start() async {
        if permission == .notDetermined {
            permission = await camera.requestPermission() ? .granted : .denied
        }
        if permission == .granted {
            camera.start()
            zoomGesture.start()
        }
    }

    func stop() {
        camera.stop()
        zoomGesture.stop()
    }

    /// Dipanggil saat app aktif lagi, misalnya setelah dari Settings.
    func refresh() {
        guard permission != .notDetermined else { return }
        permission = camera.permissionStatus()
        if permission == .granted {
            camera.start()
            zoomGesture.start()
        }
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Zoom
    func toggleGesture() {
        isGestureEnabled.toggle()
        selectedPart = .face
        zoomGesture.setGestureEnabled(isGestureEnabled)
    }

    func select(_ part: ZoomPart) {
        selectedPart = part
        zoomGesture.setManualTarget(part.target)
    }

    func setViewSize(_ size: CGSize) { zoomGesture.setViewSize(size) }
    func pinchChanged(_ magnification: CGFloat) { zoomGesture.pinchChanged(magnification) }
    func pinchEnded() { zoomGesture.pinchEnded() }

    // MARK: - Lighting
    func showLighting() { isLightingSheetPresented = true }
}
