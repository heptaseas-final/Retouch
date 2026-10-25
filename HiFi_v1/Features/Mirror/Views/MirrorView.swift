//
//  MirrorView.swift
//  HiFi_v1
//
//  Created by Davin P on 25/10/26.
//

import SwiftUI

struct MirrorView: View {
    @State private var viewModel = MirrorViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if viewModel.permission == .denied {
                CameraPermissionDeniedView(onOpenSettings: viewModel.openSettings)
            } else {
                ZoomableCameraPreview(viewModel: viewModel)
                VStack(spacing: 12) {
                    Spacer()
                    if viewModel.isZoomBarVisible {
                        ZoomPartBar(selected: viewModel.selectedPart, onSelect: viewModel.select)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    ActionButtonRow(isZoomBarVisible: viewModel.isZoomBarVisible, onLighting: viewModel.showLighting, onZoom: viewModel.toggleGesture, onMic: {})
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
                .animation(.easeInOut(duration: 0.25), value: viewModel.isZoomBarVisible)
            }
        }
        .sheet(isPresented: Bindable(viewModel).isLightingSheetPresented) {
            LightingSheetView(lighting: viewModel.lighting)
                .presentationDetents([.fraction(0.42)])
                .presentationDragIndicator(.visible)
                .presentationBackground(.white.opacity(0.6))
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
