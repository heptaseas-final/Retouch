import CoreImage
import CoreVideo
import Metal


final class FramePipeline {
    let renderer: MirrorRenderer
    let vision = FrameForwarder()

    private let lighting: LightingEngine
    private let enhancer: FrameEnhancer?
    private let queue: MTLCommandQueue?
    private let fallbackColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    init(lighting: LightingEngine) {
        let device = MTLCreateSystemDefaultDevice()
        self.lighting = lighting
        renderer = MirrorRenderer(device: device)
        queue = device?.makeCommandQueue()
        enhancer = device.flatMap { FrameEnhancer(device: $0) }
    }

    func process(_ frame: CameraFrame) {
        vision.send(frame.pixelBuffer)

        var parameters = lighting.process(frame)

        guard renderer.isReady, let queue, let commandBuffer = queue.makeCommandBuffer() else { return }
        let zoom = renderer.zoom
        parameters.addZoomDenoise(scale: Float(zoom.scale))
        let source = CIImage(cvPixelBuffer: frame.pixelBuffer)
        let colorSpace = source.colorSpace ?? fallbackColorSpace
        let enhanced = parameters.needsProcessing
            ? enhancer?.encode(frame.pixelBuffer, parameters, colorSpace: colorSpace, into: commandBuffer)
            : nil

        renderer.render(enhanced ?? source, zoom: zoom, commandBuffer: commandBuffer)
    }
}

private extension FrameEnhancer.Parameters {
    mutating func addZoomDenoise(scale: Float) {
        let zoom = smoothstep(1.3, 2.5, scale)
        guard zoom > 0.01 else { return }
        spatial = max(spatial, 0.4 * zoom * smoothstep(0.15, 0.6, noise))
        edgeSharpen = max(edgeSharpen, 0.5 * zoom)
        coring = max(coring, 0.01)
    }
}
