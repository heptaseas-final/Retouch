import CoreImage
import CoreImage.CIFilterBuiltins
import QuartzCore

final class MirrorRenderer {
    var zoom: ZoomState {
        get { lock.withLock { _zoom } }
        set { lock.withLock { _zoom = newValue } }
    }

    private let device: MTLDevice?
    private let queue: MTLCommandQueue?
    private let context: CIContext?
    private let pipeline: FramePipeline?
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    private let lock = NSLock()
    private var layer: CAMetalLayer?
    private var drawableSize: CGSize = .zero
    private var pointScale: CGFloat = 1
    private var _zoom = ZoomState()

    init() {
        device = MTLCreateSystemDefaultDevice()
        queue = device?.makeCommandQueue()
        context = device.map {
            CIContext(mtlDevice: $0, options: [.cacheIntermediates: false])
        }
        pipeline = device.flatMap { FramePipeline(device: $0) }
    }

    func attach(_ layer: CAMetalLayer, drawableSize: CGSize) {
        layer.device = device
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = false
        layer.maximumDrawableCount = 2
        layer.drawableSize = drawableSize
        lock.withLock {
            self.layer = layer
            self.drawableSize = drawableSize
            self.pointScale = layer.contentsScale
        }
    }

    func render(_ pixelBuffer: CVPixelBuffer, params input: FramePipeline.Parameters) {
        let original = CIImage(cvPixelBuffer: pixelBuffer)
        let (layer, size, zoom, pointScale) = lock.withLock { (self.layer, drawableSize, _zoom, self.pointScale) }
        guard let layer, let queue, let context, size.width > 0,
              let drawable = layer.nextDrawable(),
              let commandBuffer = queue.makeCommandBuffer() else { return }

        var params = input
        let zoomDenoise = 0.4 * smoothstep(1.3, 2.5, Float(zoom.scale))
        if zoomDenoise > 0.01 {
            params.spatial = max(params.spatial, zoomDenoise)
            params.noise = max(params.noise, 0.3)
        }
        let processed = params.needsProcessing
            ? pipeline?.encode(pixelBuffer, params, colorSpace: original.colorSpace, into: commandBuffer)
            : nil

        let image = compose(Self.uprightMirror(processed ?? original), size: size, zoom: zoom,
                            pointScale: pointScale)
        let destination = CIRenderDestination(mtlTexture: drawable.texture, commandBuffer: commandBuffer)
        destination.isFlipped = true
        destination.colorSpace = colorSpace
        _ = try? context.startTask(toRender: image, to: destination)
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    private static func uprightMirror(_ frame: CIImage) -> CIImage {
        guard frame.extent.width > frame.extent.height else { return frame.oriented(.upMirrored) }
        return frame.oriented(.leftMirrored)
    }

    private func compose(_ frame: CIImage, size: CGSize, zoom: ZoomState, pointScale: CGFloat) -> CIImage {
        let ext = frame.extent
        let outRect = CGRect(origin: .zero, size: size)
        let black = CIImage(color: .black).cropped(to: outRect)

        let fill = max(size.width / ext.width, size.height / ext.height)
        let total = fill * max(zoom.scale, 0.01)
        let origin = CGPoint(x: size.width / 2 + zoom.offset.width * pointScale,
                             y: size.height / 2 - zoom.offset.height * pointScale)
        let center = CGPoint(x: ext.midX, y: ext.midY)

        let visible = CGRect(x: center.x - origin.x / total, y: center.y - origin.y / total,
                             width: size.width / total, height: size.height / total)
        let source = visible.insetBy(dx: -4, dy: -4).intersection(ext)
        guard !source.isNull, !source.isEmpty else { return black }

        var img = frame.cropped(to: source)
            .transformed(by: CGAffineTransform(translationX: -source.minX, y: -source.minY))
        if total < 0.99 {
            let lanczos = CIFilter.lanczosScaleTransform()
            lanczos.inputImage = img
            lanczos.scale = Float(total)
            lanczos.aspectRatio = 1
            img = lanczos.outputImage ?? img.transformed(by: CGAffineTransform(scaleX: total, y: total))
        } else if total > 1.01 {
            img = img.transformed(by: CGAffineTransform(scaleX: total, y: total))
        }
        let placed = CGPoint(x: (source.minX - center.x) * total + origin.x,
                             y: (source.minY - center.y) * total + origin.y)
        return img.transformed(by: CGAffineTransform(translationX: placed.x, y: placed.y))
            .composited(over: black)
            .cropped(to: outRect)
    }
}
