import SwiftUI

struct ActionButtonRow: View {
    let isZoomActive: Bool
    let onLighting: () -> Void
    let onZoom: () -> Void
    let onMic: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            GlassIconButton(systemName: "bolt.fill", action: onLighting)
            GlassIconButton(systemName: "arrow.up.left.and.down.right.magnifyingglass",
                            color: isZoomActive ? .appMagenta : .appInactive,
                            action: onZoom)
            GlassIconButton(systemName: "mic", action: onMic)
        }
    }
}