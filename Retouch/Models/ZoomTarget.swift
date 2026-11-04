import CoreGraphics

nonisolated enum FaceSide { case left, right }

nonisolated enum ZoomTarget: Equatable {
    case fullFace, leftEye, rightEye, lips
    case faceSide(FaceSide)

    var zoomScale: CGFloat {
        switch self {
        case .fullFace: 1.1
        case .leftEye, .rightEye: 2.3
        case .lips: 2.0
        case .faceSide: ZoomTuning.sideZoom   // satu besar tetap, diatur di ZoomTuning
        }
    }
}
