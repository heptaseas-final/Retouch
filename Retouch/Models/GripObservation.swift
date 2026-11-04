import CoreGraphics

nonisolated struct GripObservation {
    var grip: CGPoint            // titik jepit
    var tip: CGPoint             // perkiraan ujung brush
    var twoFinger = false        // jempol + telunjuk merapat
    var threeFinger = false      // jempol + telunjuk + jari tengah merapat
}

nonisolated struct HandScan {
    var grips: [GripObservation] = []
    var fingertips: [CGPoint] = []   // ujung jari semua tangan, tanpa syarat pose (ruang gambar 0...1)
    var handsSeen = 0
    var pinchRatio: CGFloat?         // rasio jepit 3 jari terkecil
    var pinchRatio2: CGFloat?        // rasio jepit 2 jari terkecil
    var confidence: Float = 0

    /// Jalur mata hanya boleh melihat pose 3 jari, sama seperti sebelumnya.
    var threeFingerGrips: [GripObservation] { grips.filter { $0.threeFinger } }
}
