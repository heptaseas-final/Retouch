//
//  LightingViewModel.swift
//  HiFi_v1
//
//  Created by Davin P on 25/10/26.
//


import Observation

@MainActor
@Observable
final class LightingViewModel {
    static let defaultBrightness = 0.0

    // [FITUR] detector dipakai untuk menerapkan pilihan user ke light filter (edge light)
    @ObservationIgnored private let detector: AutoLightDetector

    private(set) var selectedColor: LightColor = .white

    init(detector: AutoLightDetector) {
        self.detector = detector
    }

    /// Auto = user belum mengambil alih strength maupun warna light filter.
    var isAutoBrightness: Bool {
        detector.manualBrightness == nil && detector.filterColor == nil
    }

    /// 0...1 = brightness layar yang sebenarnya. Saat auto, slider ikut brightness HP user
    /// (naik ke full hanya saat low light).
    var brightness: Double {
        detector.manualBrightness ?? detector.appliedBrightness
    }

    func setAuto(_ isOn: Bool) {
        if isOn {
            selectedColor = .white                       // default warna kembali putih
            detector.resetToAuto()
        } else {
            freezeBrightness()
            freezeColor()
        }
    }

    func setBrightness(_ value: Double) {
        freezeColor()                                    // aksi manual apa pun mematikan auto
        detector.setManualBrightness(value)
    }

    func select(_ color: LightColor) {
        selectedColor = color
        freezeBrightness()                               // pilih warna -> auto brightness mati
        detector.setFilterColor(color.manualChoice)
    }

    /// Bekukan level yang sedang aktif jika belum manual.
    private func freezeBrightness() {
        if detector.manualBrightness == nil {
            detector.setManualBrightness(detector.appliedBrightness)
        }
    }

    private func freezeColor() {
        if detector.filterColor == nil {
            detector.setFilterColor(selectedColor.manualChoice)
        }
    }
}

// [FITUR] mapping ke ManualColorChoice (warm / natural / cool).
extension LightColor {
    var manualChoice: ManualColorChoice {
        switch self {
        case .white: .natural
        case .warm: .warm
        case .cool: .cool
        }
    }
}
