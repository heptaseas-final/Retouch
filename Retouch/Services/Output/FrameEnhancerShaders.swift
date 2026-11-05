import Foundation

enum FrameEnhancerShaders {

    static let source = #"""
    #include <metal_stdlib>
    using namespace metal;

    struct EnhanceUniforms {
        float spatial;
        float noise;
        float chroma;
        float sharpen;
        float coring;
    };

    kernel void enhance(
        texture2d<float, access::read> input [[texture(0)]],
        texture2d<float, access::write> output [[texture(1)]],
        constant EnhanceUniforms &u [[buffer(0)]],
        uint2 gid [[thread_position_in_grid]]
    ) {

        uint width = output.get_width();
        uint height = output.get_height();

        if (gid.x >= width || gid.y >= height) {
            return;
        }

        float4 center = input.read(gid);

        if (u.spatial <= 0.001 &&
            u.chroma <= 0.001 &&
            u.sharpen <= 0.001) {

            output.write(center, gid);
            return;
        }

        float3 original = center.rgb;

        float3 gaussianSum = float3(0.0);
        float gaussianWeightSum = 0.0;

        float3 bilateralSum = float3(0.0);
        float bilateralWeightSum = 0.0;

        int2 maxPosition = int2(
            int(width) - 1,
            int(height) - 1
        );

        float sigma = 0.025 + 0.08 * u.noise;
        float sigmaSquared = 2.0 * sigma * sigma;

        for (int dy = -1; dy <= 1; dy++) {
            for (int dx = -1; dx <= 1; dx++) {

                int2 position = clamp(
                    int2(gid) + int2(dx, dy),
                    int2(0),
                    maxPosition
                );

                float3 sampleColor = input.read(
                    uint2(position)
                ).rgb;

                float distanceSquared = float(
                    dx * dx + dy * dy
                );

                float spatialWeight = exp(
                    -distanceSquared / 2.0
                );

                float3 difference = sampleColor - original;

                float colorDistance = dot(
                    difference,
                    difference
                );

                float rangeWeight = exp(
                    -colorDistance / sigmaSquared
                );

                float bilateralWeight =
                    spatialWeight * rangeWeight;

                gaussianSum += sampleColor * spatialWeight;
                gaussianWeightSum += spatialWeight;

                bilateralSum += sampleColor * bilateralWeight;
                bilateralWeightSum += bilateralWeight;
            }
        }

        float3 gaussian = gaussianSum /
            max(gaussianWeightSum, 0.0001);

        float3 bilateral = bilateralSum /
            max(bilateralWeightSum, 0.0001);

        const float3 kLuma = float3(0.2126, 0.7152, 0.0722);

        float3 denoised = mix(original, bilateral, u.spatial);
        float y = dot(denoised, kLuma);

        float3 chroma = denoised - y;
        float3 chromaGaussian = gaussian - dot(gaussian, kLuma);
        float3 result = y + mix(chroma, chromaGaussian, u.chroma);

        if (u.sharpen > 0.001) {
            float detail = dot(original, kLuma) - dot(gaussian, kLuma);
            float thresholdedDetail = sign(detail) * max(abs(detail) - u.coring, 0.0);

            float brightest = max(original.r, max(original.g, original.b));
            float highlightGuard = 1.0 - smoothstep(0.85, 1.0, brightest);

            result += thresholdedDetail * u.sharpen * highlightGuard;
        }

        result = clamp(result, 0.0, 1.0);

        output.write(
            float4(result, center.a),
            gid
        );
    }
    """#
}
