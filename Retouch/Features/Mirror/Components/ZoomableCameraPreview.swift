import SwiftUI

struct ZoomableCameraPreview: View {
    let viewModel: MirrorViewModel

    var body: some View {
        GeometryReader { geo in
            MirrorPreview(detector: viewModel.detector, zoom: viewModel.zoomState)
                .frame(width: geo.size.width, height: geo.size.height)
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
