import CoreGraphics

nonisolated struct ZoomDebugInfo: Equatable {
    var target = "full face"
    var distLeftEye: CGFloat?
    var distRightEye: CGFloat?
    var distLips: CGFloat?
    var handsSeen = 0
    var gripCount = 0
    var pinchRatio: CGFloat?
    var handConfidence: Float = 0
    var yaw = 0.0
    var yawBaseline = 0.0           
    var turnPeak = 0.0
    var eyeSpan: CGFloat = 0
    var faceAspect = 0.0
    var headState = "-"
    var idleTime = 0.0
    var exitHold = 1.2
    var fps = 0
    var handFps = 0
    var gripPoint: CGPoint?
    var tipPoint: CGPoint?
    var targetPoint: CGPoint?
    var zones: ZoneOverlayData?
}

nonisolated struct ZoneOverlayData: Equatable {
    var leftEye: CGPoint
    var rightEye: CGPoint
    var lips: CGPoint?
    var eyeTriggerRadius: CGFloat
    var eyeHoldRadius: CGFloat
    var lipsTriggerRadius: CGFloat?
    var lipsHoldRadius: CGFloat?
    var lipsBoundaryA: CGPoint?
    var lipsBoundaryB: CGPoint?
}

nonisolated extension ZoomTarget {
    var debugName: String {
        switch self {
        case .fullFace: "full face"
        case .leftEye: "mata L"
        case .rightEye: "mata R"
        case .lips: "bibir"
        case .faceSide(let side): side == .left ? "sisi kiri" : "sisi kanan"
        }
    }
}
