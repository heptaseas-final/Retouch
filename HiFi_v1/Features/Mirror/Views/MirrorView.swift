//
//  MirrorView.swift
//  HiFi_v1
//
//  Created by Davin P on 25/10/26.
//


import SwiftUI

struct MirrorView: View {
    @StateObject private var viewModel = MirrorViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if viewModel.permission == .denied {
                CameraPermissionDeniedView(onOpenSettings: viewModel.openSettings)
            } else {
                CameraPreview(session: viewModel.session)
                    .ignoresSafeArea()
            }
        }
        .task { await viewModel.start() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: viewModel.refresh()
            case .background: viewModel.stop()
            default: break
            }
        }
    }
}