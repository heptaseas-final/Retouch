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

enum ManualColorChoice: String, CaseIterable {
    case warm, natural, cool
}
