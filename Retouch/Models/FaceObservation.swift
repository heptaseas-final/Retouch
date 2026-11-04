import CoreGraphics

nonisolated struct FaceObservation {
    var leftEye: CGPoint?    // mata yang tampil di kiri layar
    var rightEye: CGPoint?   // mata yang tampil di kanan layar
    var lips: CGPoint?
    var center: CGPoint
    var width: CGFloat
    var yaw: Double          // derajat; NaN kalau landmark tidak cukup / saling bertentangan
    var aspect: Double       // tinggi / lebar kotak wajah di ruang piksel
    var pitch: Double = .nan // derajat, positif = mendongak; NaN kalau landmark tidak cukup (Tahap 5)
    var mouthWidth: Double = .nan    // lebar bibir luar / jarak antar mata
    var mouthHeight: Double = .nan   // tinggi bibir luar / jarak antar mata
    var mouthGap: Double = .nan      // bukaan bibir dalam / jarak antar mata
}
