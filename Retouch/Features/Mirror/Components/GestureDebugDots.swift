//
//  GestureDebugDots.swift
//  HiFi_v1
//
//  Created by Davin P on 26/10/26.
//


import SwiftUI

/// Titik debug: merah = titik jepit, hijau = perkiraan ujung brush, biru = titik fokus zoom.
struct GestureDebugDots: View {
    let viewModel: MirrorViewModel

    var body: some View {
        GeometryReader { geo in
            let zoom = viewModel.zoomState
            let info = viewModel.debugInfo
            ZStack {
                dot(info.gripPoint, .red, zoom, geo.size)
                dot(info.tipPoint, .green, zoom, geo.size)
                dot(info.targetPoint, .blue, zoom, geo.size)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func dot(_ p: CGPoint?, _ color: Color, _ zoom: ZoomState, _ size: CGSize) -> some View {
        if let p {
            Circle()
                .stroke(color, lineWidth: 3)
                .frame(width: 18, height: 18)
                .position(x: size.width / 2 + zoom.scale * (p.x - size.width / 2) + zoom.offset.width,
                          y: size.height / 2 + zoom.scale * (p.y - size.height / 2) + zoom.offset.height)
        }
    }
}