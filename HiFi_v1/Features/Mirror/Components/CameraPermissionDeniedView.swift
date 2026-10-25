import SwiftUI

struct CameraPermissionDeniedView: View {
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Turn on the camera permission")
                .foregroundStyle(.white)
            Button("Open Settings", action: onOpenSettings)
                .buttonStyle(.borderedProminent)
        }
    }
}