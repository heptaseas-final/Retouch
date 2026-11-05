import SwiftUI
import Observation

@MainActor
@Observable
final class MirrorViewModel {
    let detector: AutoLightDetector
    let lighting: LightingViewModel
    private let zoomGesture: ZoomGestureServicing

    private(set) var selectedPart: ZoomPart = .face
    private(set) var debugInfo = ZoomDebugInfo()
    private(set) var isGestureEnabled = true
    private(set) var zoomState = ZoomState()
    var isLightingSheetPresented = false

    var isZoomBarVisible: Bool { !isGestureEnabled }

    var permission: CameraPermissionStatus {
        detector.cameraState == .permissionDenied ? .denied : .granted
    }

    var cameraState: CameraState { detector.cameraState }
    func retryCamera() { detector.retryCameraSetup() }

    init(zoomGesture: ZoomGestureServicing = ZoomGestureService()) {
        let detector = AutoLightDetector()
        self.detector = detector
        self.lighting = LightingViewModel(detector: detector)
        self.zoomGesture = zoomGesture
        zoomGesture.onZoomChange = { [weak self] state in
            guard let self else { return }
            Task { @MainActor in self.zoomState = state }
        }
        zoomGesture.onDebugInfo = { [weak self] info in
            guard let self else { return }
            Task { @MainActor in self.debugInfo = info }
        }
        detector.frameForwarder.setHandler { [zoomGesture] buffer in
            zoomGesture.process(buffer)
        }
    }

    func start() async {
        detector.start()
        zoomGesture.start()
    }

    func stop() {
        lighting.setAuto(true)
        detector.stop()
        zoomGesture.stop()
    }

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

    func showLighting() { isLightingSheetPresented = true }
}
