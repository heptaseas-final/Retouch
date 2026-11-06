import SwiftUI
import Observation

@MainActor
@Observable
final class MirrorViewModel {
    let session: MirrorSession
    var detector: AutoLightDetector { session.detector }
    var lighting: LightingViewModel { session.lighting }
    var stabilizer: MotionStabilizer { session.stabilizer }
    private var zoomGesture: ZoomGestureServicing { session.zoomGesture }

    private(set) var selectedPart: FacePart = .face
    private(set) var lightMode: LightMode = .off
    var debugInfo: ZoomDebugInfo { session.debugInfo }
    var zoomState: ZoomState { session.zoomState }
    var isLightingSheetPresented = false

    var permission: CameraPermissionStatus {
        detector.cameraState == .permissionDenied ? .denied : .granted
    }

    var cameraState: CameraState { detector.cameraState }
    func retryCamera() { detector.retryCameraSetup() }

    init(session: MirrorSession) {
        self.session = session
    }

    func start() async { session.start() }
    func stop() { session.stop() }
    func refresh() { session.start() }

    func openSettings() { detector.openSystemSettings() }

    func select(_ part: FacePart) {
        selectedPart = part
        session.select(part)
    }

    func setLightMode(_ mode: LightMode) {
        lightMode = mode
        session.setLightMode(mode)
    }

    func setViewSize(_ size: CGSize) {
        zoomGesture.setViewSize(size)
        stabilizer.setViewSize(size)
    }
    func pinchChanged(_ magnification: CGFloat) { zoomGesture.pinchChanged(magnification) }
    func pinchEnded() { zoomGesture.pinchEnded() }
    
    func cameraStateDidChange(from old: CameraState, to new: CameraState) {
        if new == .running, old != .running {
            zoomGesture.resetSession()
        }
    }

    func lightingSheetDidChange(_ isPresented: Bool) {
        zoomGesture.setLearningPaused(isPresented)
    }

    func zoomLogSummary() -> ZoomLogSummary { zoomGesture.zoomLogSummary() }
    func zoomLogText() -> String { zoomGesture.zoomLogText() }
    func resetZoomLearning() { zoomGesture.resetLearning() }
    func clearZoomLog() { zoomGesture.clearZoomLog() }

    func showLighting() { isLightingSheetPresented = true }
}
