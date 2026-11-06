import CoreGraphics

nonisolated struct ZoomDebugInfo: Equatable {
    var target = "full face"
    var distLeftEye: CGFloat?       // jarak ujung brush ke tiap fitur, satuan jarak antar mata
    var distRightEye: CGFloat?
    var distLips: CGFloat?
    var handsSeen = 0               // tangan yang terlihat Vision
    var gripCount = 0               // tangan yang lolos sebagai "menjepit"
    var pinchRatio: CGFloat?        // makin kecil makin rapat; lolos kalau di bawah 0.5
    var handConfidence: Float = 0
    var yaw = 0.0                   // derajat, 0 kalau wajah tidak terbaca
    var yawBaseline = 0.0           // derajat, posisi "lurus" hasil belajar
    var turnPeak = 0.0              // derajat, puncak noleh hasil belajar (0 = belum belajar)
    var eyeSpan: CGFloat = 0        // jarak antar mata di layar (px), penggaris semua jarak
    var faceAspect = 0.0
    var headState = "-"
    var idleTime = 0.0
    var exitHold = 1.2
    var fps = 0
    var handFps = 0
    var gripPoint: CGPoint?         // koordinat layar
    var tipPoint: CGPoint?
    var targetPoint: CGPoint?
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
