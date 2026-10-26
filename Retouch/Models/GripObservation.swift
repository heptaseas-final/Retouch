//
//  GripObservation.swift
//  HiFi_v1
//
//  Created by Davin P on 26/10/26.
//


import CoreGraphics

nonisolated struct GripObservation {
    var grip: CGPoint   // titik jepit (tengah jempol, telunjuk, jari tengah)
    var tip: CGPoint    // perkiraan ujung brush
}

nonisolated struct HandScan {
    var grips: [GripObservation] = []
    var handsSeen = 0
    var pinchRatio: CGFloat?     // rasio jepit terkecil dari semua tangan
    var confidence: Float = 0    // keyakinan terendah dari 3 ujung jari pada tangan itu
}
