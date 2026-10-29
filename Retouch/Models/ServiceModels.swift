import Foundation

enum CameraState: Equatable {
    case idle
    case notDetermined
    case permissionDenied
    case starting
    case running
    case reconnecting
    case failed
}

// dark < 300 lux, medium 300–750, bright > 750.
enum LightCondition: String {
    case dark, medium, bright
}

/// Colour the user can pick instead of automatic colour (PRD Epic 5).
enum ManualColorChoice: String, CaseIterable {
    case warm, natural, cool

    /// Colour temperature the face is shown as if lit by, in Kelvin.
    var appearanceKelvin: Double {
        switch self {
        case .warm: 4500
        case .natural: 6500
        case .cool: 8500
        }
    }
}

struct WhiteBalance: Equatable {
    var temperature: Double
    var tint: Double
    
    func rendered(asIfLitBy kelvin: Double) -> WhiteBalance {
        let naturalMired = 1e6 / ManualColorChoice.natural.appearanceKelvin
        let mired = 1e6 / temperature - 1e6 / kelvin + naturalMired
        return WhiteBalance(temperature: 1e6 / max(mired, 1), tint: tint)
    }
}
