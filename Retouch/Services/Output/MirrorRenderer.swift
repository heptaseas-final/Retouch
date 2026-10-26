import CoreImage
import CoreImage.CIFilterBuiltins
import Metal
import QuartzCore

final class MirrorRenderer {
    var targetLevel: Double {
        get { lock.withLock { _targetLevel } }
        set { lock.withLock { _targetLevel = min(max(newValue, 0), 1) } }
    }

    var flashColor: CIColor {
        get { lock.withLock { _flashColor } }
        set { lock.withLock { _flashColor = newValue } }
    }

    var maxFlashAlpha = 1.0
    var flashOnEasing = 0.4
    var flashOffEasing = 0.12
    var clearWidthFactor: CGFloat = 1.45
    var clearHeightFactor: CGFloat = 1.8
    var flashFeather: CGFloat = 0.35
    var clearAreaEasing: CGFloat = 0.3
    var faceDetectionInterval = 3

    private let device: MTLDevice?
    private let queue: MTLCommandQueue?
    private let context: CIContext?
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private let faceTracker: FaceTracker

    private let lock = NSLock()
    private var _targetLevel = 0.0
    private var _flashColor = CIColor(red: 1, green: 1, blue: 1)
    private var layer: CAMetalLayer?
    private var drawableSize: CGSize = .zero
    private var frameCount = 0
    private var flash = 0.0
    private var clearArea: CGRect?

    init(faceTracker: FaceTracker) {
        self.faceTracker = faceTracker
        device = MTLCreateSystemDefaultDevice()
        queue = device?.makeCommandQueue()
        context = device.map { CIContext(mtlDevice: $0, options: [.cacheIntermediates: false]) }
    }

    func attach(_ layer: CAMetalLayer, drawableSize: CGSize) {
        layer.device = device
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = false
        layer.drawableSize = drawableSize
        lock.withLock {
            self.layer = layer
            self.drawableSize = drawableSize
        }
    }

    func render(_ pixelBuffer: CVPixelBuffer) {
        let frame = Self.uprightMirror(CIImage(cvPixelBuffer: pixelBuffer))
        frameCount += 1
        if frameCount % faceDetectionInterval == 0 { faceTracker.submit(frame) }

        let (layer, size, target, color) = lock.withLock { (self.layer, drawableSize, _targetLevel, _flashColor) }
        guard let layer, let queue, let context, size.width > 0,
              let drawable = layer.nextDrawable(),
              let commandBuffer = queue.makeCommandBuffer() else { return }

        let fill = Self.aspectFillTransform(from: frame.extent, to: size)
        var image = frame
            .transformed(by: fill)
            .cropped(to: CGRect(origin: .zero, size: size))

        let flashTarget = target * maxFlashAlpha
        flash += (flashTarget - flash) * (flashTarget > flash ? flashOnEasing : flashOffEasing)
        if abs(flashTarget - flash) < 0.01 { flash = flashTarget }
        if flash > 0 {
            let area = updateClearArea(face: faceTracker.face.map { Self.displayRect($0, in: frame.extent, fill) },
                                       size: size)
            image = screenFlash(size: size, clearArea: area, alpha: flash, color: color).composited(over: image)
        } else {
            clearArea = nil
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

    private func updateClearArea(face: CGRect?, size: CGSize) -> CGRect {
        let target: CGRect
        if let face {
            let w = face.width * clearWidthFactor, h = face.height * clearHeightFactor
            target = CGRect(x: face.midX - w / 2, y: face.midY - h / 2 + face.height * 0.12, width: w, height: h)
        } else {
            let w = size.width * 0.78, h = size.height * 0.56
            target = CGRect(x: (size.width - w) / 2, y: size.height * 0.45 - h / 2, width: w, height: h)
        }
        guard let current = clearArea else { clearArea = target; return target }
        let k = clearAreaEasing
        let next = CGRect(x: current.minX + (target.minX - current.minX) * k,
                          y: current.minY + (target.minY - current.minY) * k,
                          width: current.width + (target.width - current.width) * k,
                          height: current.height + (target.height - current.height) * k)
        clearArea = next
        return next
    }

    private func screenFlash(size: CGSize, clearArea: CGRect, alpha: Double, color: CIColor) -> CIImage {
        let radius = clearArea.width / 2
        let gradient = CIFilter.radialGradient()
        gradient.center = .zero
        gradient.radius0 = Float(radius)
        gradient.radius1 = Float(radius * (1 + flashFeather))
        gradient.color0 = CIColor(red: color.red, green: color.green, blue: color.blue, alpha: 0)
        gradient.color1 = CIColor(red: color.red, green: color.green, blue: color.blue, alpha: alpha)
        let stretch = CGAffineTransform(scaleX: 1, y: clearArea.height / clearArea.width)
            .concatenating(CGAffineTransform(translationX: clearArea.midX, y: clearArea.midY))
        return (gradient.outputImage ?? CIImage.empty())
            .transformed(by: stretch)
            .cropped(to: CGRect(origin: .zero, size: size))
    }

    private static func displayRect(_ normalized: CGRect, in extent: CGRect, _ fill: CGAffineTransform) -> CGRect {
        CGRect(x: extent.minX + normalized.minX * extent.width,
               y: extent.minY + normalized.minY * extent.height,
               width: normalized.width * extent.width,
               height: normalized.height * extent.height)
            .applying(fill)
    }

    private static func aspectFillTransform(from extent: CGRect, to size: CGSize) -> CGAffineTransform {
        let scale = max(size.width / extent.width, size.height / extent.height)
        let dx = (size.width - extent.width * scale) / 2 - extent.minX * scale
        let dy = (size.height - extent.height * scale) / 2 - extent.minY * scale
        return CGAffineTransform(scaleX: scale, y: scale).concatenating(.init(translationX: dx, y: dy))
    }
}
