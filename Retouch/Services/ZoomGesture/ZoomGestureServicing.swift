import AVFoundation

nonisolated protocol ZoomGestureServicing: AnyObject, Sendable {
    var onZoomChange: (@Sendable (ZoomState) -> Void)? { get set }
    var onDebugInfo: (@Sendable (ZoomDebugInfo) -> Void)? { get set }
    var onTracking: (@Sendable (ZoomTracking) -> Void)? { get set }
    func start()
    func stop()
    func setViewSize(_ size: CGSize)
    func process(_ pixelBuffer: CVPixelBuffer)
    func setGestureEnabled(_ isEnabled: Bool)
    func setManualTarget(_ target: ZoomTarget)
    func pinchChanged(_ magnification: CGFloat)
    func pinchEnded()
    func resetSession()
    func setLearningPaused(_ paused: Bool)
    func resetLearning()
    func zoomLogSummary() -> ZoomLogSummary
    func zoomLogText() -> String
    func clearZoomLog()
}
