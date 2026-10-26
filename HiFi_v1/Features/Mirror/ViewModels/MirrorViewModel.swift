import SwiftUI
import Observation

@MainActor
@Observable
final class MirrorViewModel {
    // Kamera dimiliki AutoLightDetector, karena dua AVCaptureSession tidak bisa jalan bareng
    let detector: AutoLightDetector
    let lighting: LightingViewModel
    private let zoomGesture: ZoomGestureServicing

    private(set) var selectedPart: ZoomPart = .face
    private(set) var isGestureEnabled = true
    private(set) var zoomState = ZoomState()
    var isLightingSheetPresented = false

    /// Bar zoom manual muncul saat gesture dimatikan
    var isZoomBarVisible: Bool { !isGestureEnabled }

    /// Dipetakan dari cameraState detector, supaya MirrorView tetap pakai `permission`
    var permission: CameraPermissionStatus {
        detector.cameraState == .permissionDenied ? .denied : .granted
    }

    var cameraState: CameraState { detector.cameraState }
    func retryCamera() { detector.retryCameraSetup() }

    /// Lux ruangan (cahaya layar sudah dikeluarkan), untuk label di pojok kanan atas
    var luxText: String {
        detector.roomLux.map { "\(Int($0.rounded())) lux" } ?? "– lux"
    }

    init(zoomGesture: ZoomGestureServicing = ZoomGestureService()) {
        let detector = AutoLightDetector()
        self.detector = detector
        self.lighting = LightingViewModel(detector: detector)
        self.zoomGesture = zoomGesture
        zoomGesture.onZoomChange = { [weak self] state in
            Task { @MainActor in self?.zoomState = state }
        }
        detector.frameForwarder.setHandler { [zoomGesture] buffer in
            zoomGesture.process(buffer)
        }
    }

    // MARK: - Kamera
    func start() async {
        detector.start()
        zoomGesture.start()
    }

    func stop() {
        // Setiap app keluar atau ditutup, pengaturan manual dibuang: buka lagi mulai dari auto
        lighting.setAuto(true)
        detector.stop()
        zoomGesture.stop()
    }

    /// Dipanggil saat app aktif lagi, misalnya setelah dari Settings
    func refresh() {
        detector.start()
        zoomGesture.start()
    }

    func openSettings() { detector.openSystemSettings() }

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