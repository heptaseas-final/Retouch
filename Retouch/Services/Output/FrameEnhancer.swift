import CoreGraphics
import CoreImage
import CoreVideo
import Metal

final class FrameEnhancer {

    struct Parameters {
        var noise: Float = 0
        var spatial: Float = 0
        var chromaDenoise: Float = 0
        var edgeSharpen: Float = 0
        var coring: Float = 0.01

        var needsProcessing: Bool {
            spatial > 0.01 ||
            chromaDenoise > 0.01 ||
            edgeSharpen > 0.01
        }
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
        guard
            let library = try? device.makeLibrary(
                source: FrameEnhancerShaders.source,
                options: nil
            ),
            let function = library.makeFunction(name: "enhance"),
            let pipeline = try? device.makeComputePipelineState(
                function: function
            )
        else {
            return nil
        }

        var cache: CVMetalTextureCache?

        let status = CVMetalTextureCacheCreate(
            nil,
            nil,
            device,
            nil,
            &cache
        )

        guard status == kCVReturnSuccess, let cache else {
            return nil
        }

        self.device = device
        self.pipeline = pipeline
        self.textureCache = cache
    }

    func encode(
        _ input: CVPixelBuffer,
        _ parameters: Parameters,
        colorSpace: CGColorSpace?,
        into commandBuffer: MTLCommandBuffer
    ) -> CIImage? {

        guard CVPixelBufferGetPixelFormatType(input) ==
                kCVPixelFormatType_32BGRA
        else {
            return nil
        }

        let width = CVPixelBufferGetWidth(input)
        let height = CVPixelBufferGetHeight(input)

        guard width > 0, height > 0 else {
            return nil
        }

        guard prepare(width: width, height: height) else {
            return nil
        }

        var cvTexture: CVMetalTexture?

        let status = CVMetalTextureCacheCreateTextureFromImage(
            nil,
            textureCache,
            input,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &cvTexture
        )

        guard
            status == kCVReturnSuccess,
            let cvTexture,
            let inputTexture = CVMetalTextureGetTexture(cvTexture),
            outputs.count == 2,
            let encoder = commandBuffer.makeComputeCommandEncoder()
        else {
            return nil
        }

        commandBuffer.addCompletedHandler { _ in
            withExtendedLifetime(cvTexture) {}
        }

        let output = outputs[outputIndex]
        outputIndex = 1 - outputIndex

        var uniforms = EnhanceUniforms(
            spatial: min(max(parameters.spatial, 0), 1),
            noise: min(max(parameters.noise, 0), 1),
            chroma: min(max(parameters.chromaDenoise, 0), 1),
            sharpen: min(max(parameters.edgeSharpen, 0), 1),
            coring: max(parameters.coring, 0)
        )

        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(inputTexture, index: 0)
        encoder.setTexture(output, index: 1)

        encoder.setBytes(
            &uniforms,
            length: MemoryLayout<EnhanceUniforms>.stride,
            index: 0
        )

        let threadgroupSize = MTLSize(
            width: 16,
            height: 16,
            depth: 1
        )

        let gridSize = MTLSize(
            width: width,
            height: height,
            depth: 1
        )

        encoder.dispatchThreads(
            gridSize,
            threadsPerThreadgroup: threadgroupSize
        )

        encoder.endEncoding()

        var options: [CIImageOption: Any] = [:]

        if let colorSpace {
            options[.colorSpace] = colorSpace
        }

        return CIImage(
            mtlTexture: output,
            options: options
        )?.oriented(.downMirrored)
    }

    private func prepare(width: Int, height: Int) -> Bool {

        guard size.width != width || size.height != height else {
            return outputs.count == 2
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )

        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .private

        var newOutputs: [MTLTexture] = []

        for _ in 0..<2 {
            guard let texture = device.makeTexture(
                descriptor: descriptor
            ) else {
                outputs.removeAll()
                size = (width: 0, height: 0)
                return false
            }

            newOutputs.append(texture)
        }

        outputs = newOutputs
        size = (width: width, height: height)
        outputIndex = 0

        return true
    }
}
