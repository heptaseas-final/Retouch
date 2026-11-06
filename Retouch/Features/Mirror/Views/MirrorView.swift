import SwiftUI

struct MirrorView: View {
    @State private var viewModel: MirrorViewModel
    @Environment(\.scenePhase) private var scenePhase
    private let showsControls: Bool

    init(session: MirrorSession, showsControls: Bool = true) {
        _viewModel = State(initialValue: MirrorViewModel(session: session))
        self.showsControls = showsControls
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if viewModel.permission == .denied {
                CameraPermissionDeniedView(onOpenSettings: viewModel.openSettings)
            } else {
                ZoomableCameraPreview(viewModel: viewModel)
                RingLightPanels(level: viewModel.detector.ringLightLevel, color: edgeColor,
                                maxSideFraction: CGFloat(viewModel.detector.config.ringLightWidth),
                                softness: viewModel.detector.config.ringLightSoftness)
                    .ignoresSafeArea()
                cameraStateOverlay
                if showsControls {
                    if GestureDebug.isEnabledGestureDebug {
                        GestureDebugOverlay(viewModel: viewModel)
                        GestureDebugDots(viewModel: viewModel)
                    }
                    controls
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut, value: showsControls)
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

    private var controls: some View {
        VStack {
            Spacer()
            CameraControls(
                part: Binding(get: { viewModel.selectedPart }, set: viewModel.select),
                lightMode: Binding(get: { viewModel.lightMode }, set: viewModel.setLightMode),
                onLightLongPress: viewModel.showLighting
            )
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var edgeColor: Color {
        switch viewModel.detector.filterColor {
        case .warm: Color(hex: 0xFFECBB)
        case .cool: Color(hex: 0xD7F8FF)
        default: .white
        }
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
