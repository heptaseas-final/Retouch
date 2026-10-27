import CoreImage
import CoreImage.CIFilterBuiltins
import Metal
import QuartzCore

/// Nilai tuning tetap untuk mode Enhanced (tidak adaptif terhadap cahaya).
struct EnhanceTune {
    var detail = 0.18      // ketajaman halus (luminance only)
    var contrast = 0.25    // S-curve, hanya menggelapkan bayangan
    var vibrance = 0.40    // warna pucat diangkat, kulit dijaga
    var shine = 0.35       // redam kilap di area wajah
    var modeling = 0.35    // local contrast di wajah (kesan kedalaman)

    static let fixed = EnhanceTune()
}

final class MirrorRenderer {
    /// Edge light thickness the renderer eases toward (0 = off, 1 = thickest). Thread-safe.
    var targetLevel: Double {
        get { lock.withLock { _targetLevel } }
        set { lock.withLock { _targetLevel = min(max(newValue, 0), 1) } }
    }

    var flashColor: CIColor {
        get { lock.withLock { _flashColor } }
        set { lock.withLock { _flashColor = newValue } }
    }

    /// Mode Enhanced. OFF (default) = tampilan seperti sebelumnya. Thread-safe.
    var enhancementOn: Bool {
        get { lock.withLock { _enhancementOn } }
        set { lock.withLock { _enhancementOn = newValue } }
    }

    /// Opacity of the border at its outer edge.
    var maxFlashAlpha = 1.0
    var flashOnEasing = 0.4
    var flashOffEasing = 0.12
    /// [FITUR] Thickest border as a fraction of the screen width. Kept small so the
    /// camera view in the middle is never blocked.
    var maxThicknessFraction: CGFloat = 0.12
    /// [FITUR] Share of the border's thickness that fades out toward the centre.
    var featherFraction: CGFloat = 0.4
    var faceDetectionInterval = 3
    var tune = EnhanceTune.fixed

    private static let displayP3 = CGColorSpace(name: CGColorSpace.displayP3)!

    private let device: MTLDevice?
    private let queue: MTLCommandQueue?
    private let context: CIContext?
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private let faceTracker: FaceTracker

    private let lock = NSLock()
    private var _targetLevel = 0.0
    private var _flashColor = CIColor(red: 1, green: 1, blue: 1)
        private var _enhancementOn = false
    private var layer: CAMetalLayer?
    private var drawableSize: CGSize = .zero

    // Hanya diakses dari thread render (analysisQueue, serial).
    private var frameCount = 0
    private var flash = 0.0
    private var gradeCache: [ColorGrade: Data] = [:]
    private var smoothedFace: CGRect?     // ter-normalisasi (0...1) pada frame upright
    private var faceWeight = 0.0

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
        // Faces are tracked for occlusion AND for the face treatment in Enhanced mode.
        frameCount += 1
        if frameCount % faceDetectionInterval == 0 { faceTracker.submit(frame) }

        let (layer, size, target, color, enhanced) = lock.withLock {
            (self.layer, drawableSize, _targetLevel, _flashColor, _enhancementOn)
        }
        guard let layer, let queue, let context, size.width > 0,
              let drawable = layer.nextDrawable(),
              let commandBuffer = queue.makeCommandBuffer() else { return }

        var image = process(frame, size: size, enhanced: enhanced)

        let flashTarget = target
        flash += (flashTarget - flash) * (flashTarget > flash ? flashOnEasing : flashOffEasing)
        if abs(flashTarget - flash) < 0.01 { flash = flashTarget }
        if flash > 0 {
            // [FITUR] Border around the whole screen; thickness follows the level, and
            // it no longer follows the face.
            let thickness = size.width * maxThicknessFraction * flash
            image = edgeLight(size: size, thickness: thickness, color: color).composited(over: image)
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

    // MARK: - Enhancement pipeline

    private func process(_ frame: CIImage, size: CGSize, enhanced: Bool) -> CIImage {
        let ext = frame.extent
        let outRect = CGRect(origin: .zero, size: size)

        // 1. Aspect-fill (zoom ditangani tim lain di ZoomableCameraPreview, bukan di sini).
        let fill = max(size.width / ext.width, size.height / ext.height)
        let visW = size.width / fill
        let visH = size.height / fill
        let crop = CGRect(x: ext.minX + (ext.width - visW) / 2,
                          y: ext.minY + (ext.height - visH) / 2,
                          width: visW, height: visH)
        var img = frame.cropped(to: crop)
            .transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
        let scale = size.width / visW

        guard enhanced else {
            return img.transformed(by: CGAffineTransform(scaleX: scale, y: scale)).cropped(to: outRect)
        }

        // 2. Resample Lanczos ke ukuran layar (dilewati kalau ~1:1).
        if abs(scale - 1) > 0.01 {
            let f = CIFilter.lanczosScaleTransform()
            f.inputImage = img
            f.scale = Float(scale)
            f.aspectRatio = 1
            img = f.outputImage ?? img
        }
        img = img.cropped(to: outRect)

        // 3. Color grade global (kontras + vibrance) dalam satu pass LUT.
        img = applyGrade(ColorGrade(contrast: tune.contrast, vibrance: tune.vibrance).quantized(), to: img)

        // 4. Perlakuan wajah (shine control + modeling), hanya di area wajah.
        if let face = facePlan(frameExtent: ext) {
            let cx = (face.rect.midX - crop.minX) * scale
            let cy = (face.rect.midY - crop.minY) * scale
            let rx = max(face.rect.width * scale * 0.75, 1)
            let ry = max(face.rect.height * scale * 0.9, 1)

            var treated = applyGrade(ColorGrade(shine: tune.shine).quantized(), to: img)

            let hot = ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue
            if tune.modeling > 0.02 && !hot {
                let region = CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2)
                    .insetBy(dx: -30, dy: -30)
                    .intersection(img.extent)
                if !region.isEmpty {
                    let f = CIFilter.sharpenLuminance()
                    f.inputImage = treated.cropped(to: region)
                    f.radius = 15
                    f.sharpness = Float(tune.modeling * 0.5)
                    if let out = f.outputImage {
                        treated = out.cropped(to: region).composited(over: treated)
                    }
                }
            }

            let k = CGFloat(min(max(face.presence, 0), 1))
            let gradient = CIFilter.radialGradient()
            gradient.center = .zero
            gradient.radius0 = 0.4
            gradient.radius1 = 1.0
            gradient.color0 = CIColor(red: k, green: k, blue: k, alpha: k)
            gradient.color1 = CIColor(red: 0, green: 0, blue: 0, alpha: 0)

            if let g = gradient.outputImage {
                let mask = g
                    .transformed(by: CGAffineTransform(scaleX: rx, y: ry))
                    .transformed(by: CGAffineTransform(translationX: cx, y: cy))
                    .cropped(to: img.extent)
                let blend = CIFilter.blendWithMask()
                blend.inputImage = treated
                blend.backgroundImage = img
                blend.maskImage = mask
                img = blend.outputImage ?? img
            }
        }

        // 5. Ketajaman halus, luminance only.
        if tune.detail > 0.02 {
            let f = CIFilter.sharpenLuminance()
            f.inputImage = img
            f.radius = 1.6
            f.sharpness = Float(tune.detail)
            img = f.outputImage ?? img
        }
        return img.cropped(to: outRect)
    }

    /// Kotak wajah (piksel frame upright) + presence (fade masuk/keluar), dari FaceTracker.
    private func facePlan(frameExtent ext: CGRect) -> (rect: CGRect, presence: Double)? {
        let present = faceTracker.isFaceVisible
        if present, let box = faceTracker.face {
            if let old = smoothedFace {
                let a: CGFloat = 0.3   // haluskan supaya mask tidak bergetar
                smoothedFace = CGRect(x: old.minX + (box.minX - old.minX) * a,
                                      y: old.minY + (box.minY - old.minY) * a,
                                      width: old.width + (box.width - old.width) * a,
                                      height: old.height + (box.height - old.height) * a)
            } else {
                smoothedFace = box
            }
        }
        faceWeight += ((present ? 1.0 : 0.0) - faceWeight) * 0.15
        guard faceWeight > 0.02, let n = smoothedFace else { return nil }
        let rect = CGRect(x: ext.minX + n.minX * ext.width, y: ext.minY + n.minY * ext.height,
                          width: n.width * ext.width, height: n.height * ext.height)
        return (rect, faceWeight)
    }

    private func cubeData(for grade: ColorGrade) -> Data {
        if let d = gradeCache[grade] { return d }
        if gradeCache.count > 12 { gradeCache.removeAll() }
        let d = grade.makeCubeData()
        gradeCache[grade] = d
        return d
    }

    private func applyGrade(_ grade: ColorGrade, to img: CIImage) -> CIImage {
        guard !grade.isIdentity else { return img }
        let f = CIFilter.colorCubeWithColorSpace()
        f.inputImage = img
        f.cubeDimension = Float(ColorGrade.dimension)
        f.cubeData = cubeData(for: grade)
        f.colorSpace = Self.displayP3
        return f.outputImage ?? img
    }

    // MARK: - Edge light (tidak berubah)

    /// [FITUR] A border of `thickness` pixels along all four edges: solid on the outside,
    /// fading to clear on the inside, so the middle of the camera view stays untouched.
    private func edgeLight(size: CGSize, thickness t: CGFloat, color: CIColor) -> CIImage {
        guard t > 0.5 else { return CIImage.empty() }
        let solid = CIColor(red: color.red, green: color.green, blue: color.blue, alpha: maxFlashAlpha)
        let clear = CIColor(red: color.red, green: color.green, blue: color.blue, alpha: 0)
        let w = size.width, h = size.height
        let solidPart = t * (1 - featherFraction)

        func strip(edge: CGPoint, direction: CGVector, rect: CGRect) -> CIImage {
            let gradient = CIFilter.linearGradient()
            gradient.point0 = CGPoint(x: edge.x + direction.dx * solidPart, y: edge.y + direction.dy * solidPart)
            gradient.point1 = CGPoint(x: edge.x + direction.dx * t, y: edge.y + direction.dy * t)
            gradient.color0 = solid
            gradient.color1 = clear
            return (gradient.outputImage ?? CIImage.empty()).cropped(to: rect)
        }

        let bottom = strip(edge: CGPoint(x: 0, y: 0), direction: CGVector(dx: 0, dy: 1),
                           rect: CGRect(x: 0, y: 0, width: w, height: t))
        let top = strip(edge: CGPoint(x: 0, y: h), direction: CGVector(dx: 0, dy: -1),
                        rect: CGRect(x: 0, y: h - t, width: w, height: t))
        let left = strip(edge: CGPoint(x: 0, y: 0), direction: CGVector(dx: 1, dy: 0),
                         rect: CGRect(x: 0, y: 0, width: t, height: h))
        let right = strip(edge: CGPoint(x: w, y: 0), direction: CGVector(dx: -1, dy: 0),
                          rect: CGRect(x: w - t, y: 0, width: t, height: h))
        return [top, left, right].reduce(bottom) { $1.composited(over: $0) }
    }
}
