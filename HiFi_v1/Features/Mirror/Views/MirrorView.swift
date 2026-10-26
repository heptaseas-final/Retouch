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
                cameraStateOverlay                          
                luxLabel                                   
                VStack(spacing: 12) {
                    Spacer()
                    if viewModel.isZoomBarVisible {
                        ZoomPartBar(selected: viewModel.selectedPart, onSelect: viewModel.select)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    ActionButtonRow(isZoomBarVisible: viewModel.isZoomBarVisible,
                                    onLighting: viewModel.showLighting,
                                    onZoom: viewModel.toggleGesture,
                                    onMic: {})
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

    // [FITUR] lux lingkungan, kecil di pojok kanan atas
    private var luxLabel: some View {
        VStack {
            HStack {
                Spacer()
                Text(viewModel.luxText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.5), in: Capsule())
            }
            Spacer()
        }
        .padding(.top, 8)
        .padding(.trailing, 16)
        .allowsHitTesting(false)
    }

    // [FITUR] state kamera dari detector (PRD Epic 1)
    @ViewBuilder
    private var cameraStateOverlay: some View {
        switch viewModel.cameraState {
        case .failed:
            VStack(spacing: 16) {
                Text("Camera is not opened")
                    .foregroundStyle(.white)
                Button("Try again", action: viewModel.retryCamera)
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
        case .reconnecting:
            VStack {
                Label("Reconnecting…", systemImage: "arrow.triangle.2.circlepath")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                Spacer()
            }
            .padding(.top)
        default:
            EmptyView()
        }
    }
}
