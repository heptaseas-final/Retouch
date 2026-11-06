import CoreImage
import CoreImage.CIFilterBuiltins
import Metal
import QuartzCore

final class MirrorRenderer {
    var zoom: ZoomState {
        get { lock.withLock { _zoom } }
        set { lock.withLock { _zoom = newValue } }
    }
    
    var isReady: Bool {
        lock.withLock { layer != nil && drawableSize.width > 0 && drawableSize.height > 0 }
    }
    
    var frameShift: FrameShiftProvider? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _frameShift
        }
        set {
            lock.lock()
            _frameShift = newValue
            lock.unlock()
        }
    }
    
    typealias FrameShiftProvider = @Sendable (CGFloat) -> CGSize
    
    private let device: MTLDevice?
    private let context: CIContext?
    private let makeupLook: MakeupLook?
    private let colorSpace = CGColorSpace(name: CGColorSpace.displayP3)!
    
    private let lock = NSLock()
    private var layer: CAMetalLayer?
    private var drawableSize: CGSize = .zero
    private var pointScale: CGFloat = 1
    private var _zoom = ZoomState()
    private var _frameShift: FrameShiftProvider?
    
    init(device: MTLDevice?) {
        self.device = device
        makeupLook = device.flatMap { MakeupLook(device: $0) }
        context = device.map { [colorSpace] in
            CIContext(mtlDevice: $0, options: [.cacheIntermediates: false,
                                               .workingColorSpace: colorSpace,
                                               .outputColorSpace: colorSpace])
        }
    }
    
    func attach(_ layer: CAMetalLayer, drawableSize: CGSize) {
        layer.device = device
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = false
        layer.maximumDrawableCount = 2
        layer.colorspace = colorSpace
        layer.drawableSize = drawableSize
        lock.withLock {
            self.layer = layer
            self.drawableSize = drawableSize
            self.pointScale = layer.contentsScale
        }
    }
    
    /// Lepas layer yang sudah keluar dari layar, supaya frame tidak dikirim ke layer yang tidak terlihat.
    func detach(_ layer: CAMetalLayer) {
        lock.withLock {
            guard self.layer === layer else { return }
            self.layer = nil
            self.drawableSize = .zero
        }
    }

    func render(_ frame: CIImage, zoom: ZoomState, commandBuffer: MTLCommandBuffer) {
        let (layer, size, pointScale) = lock.withLock { (self.layer, drawableSize, self.pointScale) }
        guard let layer, let context, size.width > 0, size.height > 0 else {
            commandBuffer.commit()
            return
        }
        var image = compose(Self.uprightMirror(frame), size: size, zoom: zoom, pointScale: pointScale)
        if let provider = frameShift {
            let shift = provider(size.width)
            if shift.width != 0 || shift.height != 0 {
                let moved = image.transformed(by: CGAffineTransform(translationX: shift.width, y: -shift.height))
                image = moved.clampedToExtent().cropped(to: CGRect(origin: .zero, size: CGSize(width: size.width, height: size.height)))
            }
        }
        
        if let makeupLook,
           let target = makeupLook.nextTarget(width: Int(size.width), height: Int(size.height)) {
            let destination = CIRenderDestination(mtlTexture: target, commandBuffer: commandBuffer)
            destination.isFlipped = true
            destination.colorSpace = colorSpace
            _ = try? context.startTask(toRender: image, to: destination)
            guard let drawable = layer.nextDrawable(),
                  makeupLook.encode(source: target, into: drawable.texture, commandBuffer: commandBuffer) else {
                commandBuffer.commit()
                return
            }
            commandBuffer.present(drawable)
            commandBuffer.commit()
            return
        }
        
        guard let drawable = layer.nextDrawable() else {
            commandBuffer.commit()
            return
        }
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
        let extent = frame.extent
        let outputRect = CGRect(origin: .zero, size: size)
        let black = CIImage(color: .black).cropped(to: outputRect)
        
        let fill = max(size.width / extent.width, size.height / extent.height)
        let total = fill * max(zoom.scale, 0.01)
        let origin = CGPoint(x: size.width / 2 + zoom.offset.width * pointScale,
                             y: size.height / 2 - zoom.offset.height * pointScale)
        let center = CGPoint(x: extent.midX, y: extent.midY)
        
        let visible = CGRect(x: center.x - origin.x / total, y: center.y - origin.y / total,
                             width: size.width / total, height: size.height / total)
        let source = visible.insetBy(dx: -4, dy: -4).intersection(extent)
        guard !source.isNull, !source.isEmpty else { return black }
        
        var image = frame.cropped(to: source)
            .transformed(by: CGAffineTransform(translationX: -source.minX, y: -source.minY))
        if total < 0.99 {
            let lanczos = CIFilter.lanczosScaleTransform()
            lanczos.inputImage = image
            lanczos.scale = Float(total)
            lanczos.aspectRatio = 1
            image = lanczos.outputImage ?? image.transformed(by: CGAffineTransform(scaleX: total, y: total))
        } else if total > 1.01 {
            image = image.transformed(by: CGAffineTransform(scaleX: total, y: total))
        }
        
        let placed = CGPoint(x: (source.minX - center.x) * total + origin.x,
                             y: (source.minY - center.y) * total + origin.y)
        return image.transformed(by: CGAffineTransform(translationX: placed.x, y: placed.y))
            .composited(over: black)
            .cropped(to: outputRect)
    }
}
