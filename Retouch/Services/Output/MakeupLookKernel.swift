import Metal

final class MakeupLook {
    static let vibrance: Float = 0.20
    static let clarity: Float = 0.35
    static let clarityLevel: Float = 2.5

    private let device: MTLDevice
    private let pipeline: MTLComputePipelineState
    private var targets: [MTLTexture] = []
    private var targetIndex = 0
    private var targetSize = (width: 0, height: 0)

    init?(device: MTLDevice) {
        guard let library = try? device.makeLibrary(source: Self.source, options: nil),
              let function = library.makeFunction(name: "makeupLook"),
              let pipeline = try? device.makeComputePipelineState(function: function) else { return nil }
        self.device = device
        self.pipeline = pipeline
    }

    func nextTarget(width: Int, height: Int) -> MTLTexture? {
        if targetSize.width != width || targetSize.height != height {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: width,
                                                                      height: height, mipmapped: true)
            descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
            descriptor.storageMode = .private
            targets = (0..<2).compactMap { _ in device.makeTexture(descriptor: descriptor) }
            targetSize = (width, height)
            targetIndex = 0
        }
        guard targets.count == 2 else { return nil }
        defer { targetIndex = 1 - targetIndex }
        return targets[targetIndex]
    }

    func encode(source: MTLTexture, into destination: MTLTexture, commandBuffer: MTLCommandBuffer) -> Bool {
        guard let blit = commandBuffer.makeBlitCommandEncoder() else { return false }
        blit.generateMipmaps(for: source)
        blit.endEncoding()

        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return false }
        var uniforms = SIMD3<Float>(Self.vibrance, Self.clarity, Self.clarityLevel)
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(source, index: 0)
        encoder.setTexture(destination, index: 1)
        encoder.setBytes(&uniforms, length: MemoryLayout<SIMD3<Float>>.stride, index: 0)
        encoder.dispatchThreads(MTLSize(width: destination.width, height: destination.height, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
        encoder.endEncoding()
        return true
    }

    private static let source = #"""
    #include <metal_stdlib>
    using namespace metal;

    // Display P3 memakai kurva gamma sRGB: decode ke linear, encode kembali.
    static float3 decodeGamma(float3 c) {
        return select(pow((c + 0.055) / 1.055, 2.4), c / 12.92, c <= 0.04045);
    }
    static float3 encodeGamma(float3 c) {
        return select(1.055 * pow(c, 1.0 / 2.4) - 0.055, c * 12.92, c <= 0.0031308);
    }

    // Linear Display P3 <-> linear sRGB (OKLab didefinisikan dari linear sRGB).
    static float3 p3ToSrgb(float3 c) {
        return float3(dot(c, float3( 1.2249401, -0.2249404, 0.0)),
                      dot(c, float3(-0.0420569,  1.0420571, 0.0)),
                      dot(c, float3(-0.0196376, -0.0786361, 1.0982735)));
    }
    static float3 srgbToP3(float3 c) {
        return float3(dot(c, float3(0.8224621, 0.1775380, 0.0)),
                      dot(c, float3(0.0331941, 0.9668058, 0.0)),
                      dot(c, float3(0.0170827, 0.0723974, 0.9105199)));
    }
    static float cbrtSigned(float x) { return sign(x) * pow(abs(x), 1.0 / 3.0); }

    // OKLab (Björn Ottosson): ruang warna perseptual, chroma bisa diubah tanpa menggeser hue.
    static float3 toOklab(float3 c) {
        float l = cbrtSigned(dot(c, float3(0.4122214708, 0.5363325363, 0.0514459929)));
        float m = cbrtSigned(dot(c, float3(0.2119034982, 0.6806995451, 0.1073969566)));
        float s = cbrtSigned(dot(c, float3(0.0883024619, 0.2817188376, 0.6299787005)));
        return float3(0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                      1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                      0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s);
    }
    static float3 fromOklab(float3 lab) {
        float l = lab.x + 0.3963377774 * lab.y + 0.2158037573 * lab.z;
        float m = lab.x - 0.1055613458 * lab.y - 0.0638541728 * lab.z;
        float s = lab.x - 0.0894841775 * lab.y - 1.2914855480 * lab.z;
        l = l * l * l; m = m * m * m; s = s * s * s;
        return float3( 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                      -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                      -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s);
    }

    kernel void makeupLook(texture2d<half, access::sample> source [[texture(0)]],
                           texture2d<half, access::write> output [[texture(1)]],
                           constant float3 &u [[buffer(0)]],
                           uint2 gid [[thread_position_in_grid]]) {
        uint width = output.get_width(), height = output.get_height();
        if (gid.x >= width || gid.y >= height) return;
        float vibrance = u.x;
        float clarity = u.y;
        float blurLevel = u.z;

        float4 pixel = float4(source.read(gid, 0));
        float3 lab = toOklab(p3ToSrgb(decodeGamma(saturate(pixel.rgb))));
        float L = lab.x;
        float C = length(lab.yz);
        float hue = atan2(lab.z, lab.y);                       

        // 1. Bobot kulit: hue dekat 42° (±15° penuh, hilang di ±25°) dan chroma rendah-sedang.
        float d = abs(hue - 0.733);
        d = min(d, 6.2831853 - d);
        float skinHue = 1.0 - smoothstep(0.262, 0.436, d);
        float skin = skinHue * (1.0 - smoothstep(0.10, 0.13, C));

        // 2. Boost chroma: makeup penuh, kulit seperempat; warna pekat & abu-abu tidak ditambah.
        float boost = 1.0 + vibrance * mix(1.0, 0.25, skin);
        boost = mix(boost, 1.0, smoothstep(0.22, 0.32, C));
        boost = mix(1.0, boost, smoothstep(0.005, 0.02, C));
        lab.yz *= boost;

        // 3. Kurva S lembut (±2% di L = 0.25 / 0.75, ujung 0 dan 1 tetap).
        float toned = L + 0.48 * (L - 0.5) * L * (1.0 - L);

        // 4. Clarity: blur dari mipmap (5 sampel supaya halus, tanpa pola kotak).
        constexpr sampler mip(filter::linear, mip_filter::linear, address::clamp_to_edge);
        float2 size = float2(width, height);
        float2 uv = (float2(gid) + 0.5) / size;
        float2 o = 6.0 / size;
        float3 blurred = float3(source.sample(mip, uv, level(blurLevel)).rgb) * 0.4
                       + float3(source.sample(mip, uv + float2( o.x,  o.y), level(blurLevel)).rgb) * 0.15
                       + float3(source.sample(mip, uv + float2(-o.x,  o.y), level(blurLevel)).rgb) * 0.15
                       + float3(source.sample(mip, uv + float2( o.x, -o.y), level(blurLevel)).rgb) * 0.15
                       + float3(source.sample(mip, uv + float2(-o.x, -o.y), level(blurLevel)).rgb) * 0.15;
        float blurL = toOklab(p3ToSrgb(decodeGamma(saturate(blurred)))).x;
        float detail = L - blurL;
        float cored = sign(detail) * max(abs(detail) - 0.008, 0.0);
        float guard = 1.0 - smoothstep(0.85, 1.0, L);
        lab.x = clamp(toned + clarity * cored * (1.0 - 0.6 * skin) * guard, 0.0, 1.0);

        float3 rgb = encodeGamma(saturate(srgbToP3(fromOklab(lab))));
        output.write(half4(half3(rgb), 1.0h), gid);
    }
    """#
}
