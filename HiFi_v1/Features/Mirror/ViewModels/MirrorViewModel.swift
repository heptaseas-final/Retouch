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
    // [FITUR] kamera sekarang dimiliki AutoLightDetector (menggantikan CameraServicing),
    // karena dua AVCaptureSession tidak bisa jalan bareng di front camera.
    let detector: AutoLightDetector
    let lighting: LightingViewModel

    private(set) var isZoomBarVisible = false
    private(set) var selectedPart: ZoomPart = .face
    var isLightingSheetPresented = false

    /// [FITUR] dipetakan dari cameraState detector, supaya MirrorView tetap pakai `permission`.
    var permission: CameraPermissionStatus {
        detector.cameraState == .permissionDenied ? .denied : .granted
    }

    /// [FITUR] untuk overlay .failed / .reconnecting di MirrorView
    var cameraState: CameraState { detector.cameraState }
    func retryCamera() { detector.retryCameraSetup() }

    /// [FITUR] lux ruangan (cahaya layar sudah dikeluarkan), untuk label di pojok kanan atas
    var luxText: String {
        detector.roomLux.map { "\(Int($0.rounded())) lux" } ?? "– lux"
    }

    func showLighting() {
        print("bolt tapped")
        isLightingSheetPresented = true
    }

    func toggleZoomBar() { isZoomBarVisible.toggle() }
    func select(_ part: ZoomPart) { selectedPart = part }

    init() {
        let detector = AutoLightDetector()
        self.detector = detector
        self.lighting = LightingViewModel(detector: detector)
    }

    func start() async {
        detector.start()
    }

    func stop() {
        // [FITUR] setiap app keluar/ditutup, pengaturan manual dibuang: buka lagi selalu mulai dari auto
        lighting.setAuto(true)
        detector.stop()
    }

    /// dipanggil saat app active lagi, semisal setelah dari Settings
    func refresh() {
        detector.start()
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
