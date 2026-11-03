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
                // Border light: saudara dari preview, bukan di dalamnya, jadi tidak ikut zoom
                EdgeLightOverlay(level: viewModel.detector.edgeLightLevel, color: edgeColor)
                    .ignoresSafeArea()
                    .animation(.easeInOut(duration: 0.25), value: viewModel.detector.edgeLightLevel)
                cameraStateOverlay
//                luxLabel
                if GestureDebug.isEnabledGestureDebug {
                    GestureDebugOverlay(viewModel: viewModel)
                    GestureDebugDots(viewModel: viewModel)
                }
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
        .onChange(of: viewModel.cameraState) { old, new in
            viewModel.cameraStateDidChange(from: old, to: new)
        }
        .onChange(of: viewModel.isLightingSheetPresented) { _, presented in
            viewModel.lightingSheetDidChange(presented)
        }
    }

    /// Warna border sesuai pilihan di sheet; putih kalau belum memilih.
    private var edgeColor: Color {
        switch viewModel.detector.filterColor {
        case .warm: Color(hex: 0xFFECBB)
        case .cool: Color(hex: 0xD7F8FF)
        default: .white
        }
    }

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
