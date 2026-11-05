import CoreGraphics
import CoreImage
import CoreVideo
import Metal

final class FramePipeline {
    struct Parameters {
        var noise: Float = 0
        var spatial: Float = 0
        var chromaDenoise: Float = 0
        var edgeSharpen: Float = 0
        var coring: Float = 0.01

        var needsProcessing: Bool { spatial > 0.01 || chromaDenoise > 0.01 || edgeSharpen > 0.01 }
    }

    private struct EnhanceUniforms {
        var spatial: Float
        var noise: Float
        var chroma: Float
        var sharpen: Float
        var coring: Float
    }

    private let device: MTLDevice
    private let pipeline: MTLComputePipelineState
    private let textureCache: CVMetalTextureCache

    private var size = (width: 0, height: 0)
    private var outputs: [MTLTexture] = []
    private var outputIndex = 0

    init?(device: MTLDevice) {
        guard let library = try? device.makeLibrary(source: FramePipelineShaders.source, options: nil),
              let function = library.makeFunction(name: "enhance"),
              let pipeline = try? device.makeComputePipelineState(function: function) else { return nil }
        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
        guard let cache else { return nil }
        self.device = device
        self.pipeline = pipeline
        self.textureCache = cache
    }

    func encode(_ input: CVPixelBuffer, _ p: Parameters, colorSpace: CGColorSpace?,
                into commandBuffer: MTLCommandBuffer) -> CIImage? {
        guard CVPixelBufferGetPixelFormatType(input) == kCVPixelFormatType_32BGRA else { return nil }
        let width = CVPixelBufferGetWidth(input), height = CVPixelBufferGetHeight(input)
        prepare(width: width, height: height)

        var cvTexture: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(nil, textureCache, input, nil, .bgra8Unorm,
                                                  width, height, 0, &cvTexture)
        guard let cvTexture, let inputTexture = CVMetalTextureGetTexture(cvTexture), outputs.count == 2,
              let encoder = commandBuffer.makeComputeCommandEncoder() else { return nil }
        commandBuffer.addCompletedHandler { _ in withExtendedLifetime(cvTexture) {} }

        let output = outputs[outputIndex]
        outputIndex = 1 - outputIndex
        var u = EnhanceUniforms(spatial: p.spatial, noise: p.noise, chroma: p.chromaDenoise,
                                sharpen: p.edgeSharpen, coring: p.coring)
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(inputTexture, index: 0)
        encoder.setTexture(output, index: 1)
        encoder.setBytes(&u, length: MemoryLayout<EnhanceUniforms>.stride, index: 0)
        encoder.dispatchThreads(MTLSize(width: width, height: height, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
        encoder.endEncoding()

        var options: [CIImageOption: Any] = [:]
        if let colorSpace { options[.colorSpace] = colorSpace }
        return CIImage(mtlTexture: output, options: options)?.oriented(.downMirrored)
    }

    private func prepare(width: Int, height: Int) {
        guard size.width != width || size.height != height else { return }
        size = (width, height)
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width,
                                                            height: height, mipmapped: false)
        desc.usage = [.shaderRead, .shaderWrite]
        desc.storageMode = .private
        outputs = (0..<2).compactMap { _ in device.makeTexture(descriptor: desc) }
    }
}
