import Observation

@MainActor
@Observable
final class LightingViewModel {
    static let defaultBrightness = 0.0

    @ObservationIgnored private let detector: AutoLightDetector

    private(set) var selectedColor: LightColor = .white

    init(detector: AutoLightDetector) {
        self.detector = detector
    }

    /// Auto = brightness belum diambil alih user. Warna tidak ikut menentukan.
    var isAutoBrightness: Bool { detector.manualBrightness == nil }

    /// Brightness layar yang sebenarnya (0...1).
    var brightness: Double {
        detector.manualBrightness ?? detector.appliedBrightness
    }

    func setAuto(_ isOn: Bool) {
        if isOn {
            selectedColor = .white
            detector.resetToAuto()
        } else {
            detector.setManualBrightness(detector.appliedBrightness)
        }
    }

    func setBrightness(_ value: Double) {
        detector.setManualBrightness(value)
    }

    /// Hanya mengganti warna filter; auto brightness tetap jalan.
    func select(_ color: LightColor) {
        selectedColor = color
        detector.setFilterColor(color.manualChoice)
    }
}

extension LightColor {
    var manualChoice: ManualColorChoice {
        switch self {
        case .white: .natural
        case .warm: .warm
        case .cool: .cool
        }
    }
}
