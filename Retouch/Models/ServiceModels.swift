import Foundation

/// Camera lifecycle as the UI sees it (PRD Epic 1, SDD §4.1). Plain values, so
/// the UI layer needs no AVFoundation types.
enum CameraState: Equatable {
    /// Not started yet, or stopped by the host.
    case idle
    /// Waiting for the user to answer the permission prompt.
    case notDetermined
    /// UI shows "turn on the camera permission" with a Settings button.
    case permissionDenied
    case starting
    case running
    /// Interrupted or in background; all adjustments are paused.
    case reconnecting
    /// Setup failed; UI shows "camera is not opened" with "try again".
    case failed
}

/// Room lighting class (PRD Epic 2): dark < 300 lux, medium 300–750, bright > 750.
enum LightCondition: String {
    case dark, medium, bright
}

/// Colour the user can pick instead of automatic colour (PRD Epic 5).
enum ManualColorChoice: String, CaseIterable {
    case warm, natural, cool

    /// Colour temperature the face is shown as if lit by, in Kelvin.
    /// Natural is a full correction to the display's white point (D65), so
    /// skin looks the same whatever colour the room light is.
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

    /// Camera white balance that, in a room lit by `self`, shows the scene as
    /// if lit by `kelvin`. Works in mired (10⁶ / K), where colour shifts add up.
    /// Lit by `ManualColorChoice.natural` it returns `self`: a full correction.
    func rendered(asIfLitBy kelvin: Double) -> WhiteBalance {
        let naturalMired = 1e6 / ManualColorChoice.natural.appearanceKelvin
        let mired = 1e6 / temperature - 1e6 / kelvin + naturalMired
        return WhiteBalance(temperature: 1e6 / max(mired, 1), tint: tint)
    }
}
