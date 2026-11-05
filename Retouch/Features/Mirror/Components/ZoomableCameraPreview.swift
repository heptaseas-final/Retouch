import SwiftUI

struct ZoomableCameraPreview: View {
    let viewModel: MirrorViewModel

    var body: some View {
        GeometryReader { geo in
            MirrorPreview(detector: viewModel.detector)
                .frame(width: geo.size.width, height: geo.size.height)
                .scaleEffect(viewModel.zoomState.scale)
                .offset(viewModel.zoomState.offset)
                .onAppear { viewModel.setViewSize(geo.size) }
                .onChange(of: geo.size) { _, size in viewModel.setViewSize(size) }
        }
        .ignoresSafeArea()
        .gesture(
            MagnifyGesture()
                .onChanged { viewModel.pinchChanged($0.magnification) }
                .onEnded { _ in viewModel.pinchEnded() }
        )
    }
}
