import CoreImage
import CoreImage.CIFilterBuiltins
import Metal
import QuartzCore

/// Draws camera frames to the screen through Core Image on the GPU as an
/// upright mirror, and in dark rooms adds the dim-light edge light (PRD Epic 3).
///
/// Edge light: like the front camera's flash, the screen turns white to light
/// the face, but an oval around the face (found by `FaceTracker`) stays clear,
/// with a soft edge, so the face is never covered. The white is neutral, so it
/// doesn't tint the face the way a screen showing only skin tones does.
///
/// Face pixels are always exactly what the camera captured; nothing
/// brightens or filters the image itself. Rendering runs on the camera's frame
/// queue, never the main thread, so the UI cannot stall the mirror.
final class MirrorRenderer {
    /// Edge light strength the renderer eases toward (0 = off, 1 = strongest). Thread-safe.
    var targetLevel: Double {
        get { lock.withLock { _targetLevel } }
        set { lock.withLock { _targetLevel = min(max(newValue, 0), 1) } }
    }

    /// Opacity of the white at level 1.
    var maxFlashAlpha = 1.0
    /// Per-frame easing of the edge light: quick on, like a camera flash; gentler off.
    var flashOnEasing = 0.4
    var flashOffEasing = 0.12
    /// Clear oval around the face, relative to the detected face box. Taller
    /// than the box and shifted up, to include forehead and hair.
    var clearWidthFactor: CGFloat = 1.45
    var clearHeightFactor: CGFloat = 1.8
    /// Width of the soft edge, as a fraction of the oval's radius.
    var flashFeather: CGFloat = 0.35
    /// Per-frame easing of the oval as the face moves.
    var clearAreaEasing: CGFloat = 0.3
    /// Faces are looked for on every nth frame (≈ 10×/s at 30 fps).
    var faceDetectionInterval = 3

    private let device: MTLDevice?
    private let queue: MTLCommandQueue?
    private let context: CIContext?
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private let faceTracker: FaceTracker

    private let lock = NSLock()
    private var _targetLevel = 0.0
    private var layer: CAMetalLayer?
    private var drawableSize: CGSize = .zero
    // Owned by the frame queue.
    private var frameCount = 0
    private var flash = 0.0
    private var clearArea: CGRect?

    init(faceTracker: FaceTracker) {
        self.faceTracker = faceTracker
        device = MTLCreateSystemDefaultDevice()
        queue = device?.makeCommandQueue()
        context = device.map { CIContext(mtlDevice: $0, options: [.cacheIntermediates: false]) }
    }

    /// Called from the view whenever it lays out.
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

    /// Renders one camera frame. Called on the camera's frame queue.
    func render(_ pixelBuffer: CVPixelBuffer) {
        let frame = Self.uprightMirror(CIImage(cvPixelBuffer: pixelBuffer))
        // Faces are tracked even without the edge light, for occlusion (PRD Epic 4).
        frameCount += 1
        if frameCount % faceDetectionInterval == 0 { faceTracker.submit(frame) }

        let (layer, size, target) = lock.withLock { (self.layer, drawableSize, _targetLevel) }
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
            image = screenFlash(size: size, clearArea: area, alpha: flash).composited(over: image)
        } else {
            clearArea = nil
        }
        let destination = CIRenderDestination(mtlTexture: drawable.texture, commandBuffer: commandBuffer)
        destination.isFlipped = true   // Core Image's origin is bottom-left, Metal's is top-left.
        destination.colorSpace = colorSpace
        _ = try? context.startTask(toRender: image, to: destination)
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    /// Turns a front-camera sensor frame into an upright mirror image for a
    /// portrait phone (PRD Epic 1: preview mirrored horizontally).
    ///
    /// The sensor delivers landscape frames. Rotated 90° clockwise (`.right`)
    /// they stand upright but show the scene as other people see it, not as a
    /// mirror (checked on device). Flipping that horizontally gives the
    /// mirror, and works out to `.leftMirrored`.
    private static func uprightMirror(_ frame: CIImage) -> CIImage {
        // Already portrait (rotated upstream): only flip it into a mirror.
        guard frame.extent.width > frame.extent.height else { return frame.oriented(.upMirrored) }
        return frame.oriented(.leftMirrored)
    }

    /// Eases the clear oval toward the face (display coordinates), or toward a
    /// default spot where a face usually is when none has been found.
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

    /// White light covering the screen except a soft-edged oval over the face.
    private func screenFlash(size: CGSize, clearArea: CGRect, alpha: Double) -> CIImage {
        // A circular gradient, clear inside `radius`, white past the feather,
        // then stretched into the oval.
        let radius = clearArea.width / 2
        let gradient = CIFilter.radialGradient()
        gradient.center = .zero
        gradient.radius0 = Float(radius)
        gradient.radius1 = Float(radius * (1 + flashFeather))
        gradient.color0 = CIColor(red: 1, green: 1, blue: 1, alpha: 0)
        gradient.color1 = CIColor(red: 1, green: 1, blue: 1, alpha: alpha)
        let stretch = CGAffineTransform(scaleX: 1, y: clearArea.height / clearArea.width)
            .concatenating(CGAffineTransform(translationX: clearArea.midX, y: clearArea.midY))
        return (gradient.outputImage ?? CIImage.empty())
            .transformed(by: stretch)
            .cropped(to: CGRect(origin: .zero, size: size))
    }

    /// Maps a normalised Vision rect in the frame to display coordinates.
    private static func displayRect(_ normalized: CGRect, in extent: CGRect, _ fill: CGAffineTransform) -> CGRect {
        CGRect(x: extent.minX + normalized.minX * extent.width,
               y: extent.minY + normalized.minY * extent.height,
               width: normalized.width * extent.width,
               height: normalized.height * extent.height)
            .applying(fill)
    }

    /// Scales and centres `extent` to fill `size`, cropping the overflow.
    private static func aspectFillTransform(from extent: CGRect, to size: CGSize) -> CGAffineTransform {
        let scale = max(size.width / extent.width, size.height / extent.height)
        let dx = (size.width - extent.width * scale) / 2 - extent.minX * scale
        let dy = (size.height - extent.height * scale) / 2 - extent.minY * scale
        return CGAffineTransform(scaleX: scale, y: scale).concatenating(.init(translationX: dx, y: dy))
    }
}
