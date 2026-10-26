import SwiftUI

/// Full-screen live mirror for the host UI to place. Frames are rotated,
/// mirrored and drawn, with the edge light, by `MirrorRenderer`.
struct MirrorPreview: UIViewRepresentable {
    let detector: AutoLightDetector

    func makeUIView(context: Context) -> MetalLayerView {
        let view = MetalLayerView()
        view.renderer = detector.renderer
        return view
    }

    func updateUIView(_ view: MetalLayerView, context: Context) {}

    final class MetalLayerView: UIView {
        override class var layerClass: AnyClass { CAMetalLayer.self }
        var renderer: MirrorRenderer?

        override func layoutSubviews() {
            super.layoutSubviews()
            let scale = window?.screen.scale ?? traitCollection.displayScale
            layer.contentsScale = scale
            renderer?.attach(layer as! CAMetalLayer,
                             drawableSize: CGSize(width: bounds.width * scale, height: bounds.height * scale))
        }
    }
}
