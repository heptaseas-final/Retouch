//
//  ActionButtonRow.swift
//  Retouch
//
//  Created by Davin P on 25/10/26.
//
import SwiftUI

struct ActionButtonRow: View {
    let isZoomBarVisible: Bool
    let onLighting: () -> Void
    let onZoom: () -> Void
    let onMic: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            GlassIconButton(systemName: "bolt.fill", action: onLighting)
            GlassIconButton(systemName: "arrow.up.left.and.down.right.magnifyingglass",
                            color: isZoomBarVisible ? .appInactive : .appMagenta,
                            action: onZoom)
//            GlassIconButton(systemName: "microphone.fill", action: onMic)
        }
    }
}
