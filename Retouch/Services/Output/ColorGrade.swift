import Foundation
import simd

struct ColorGrade: Hashable {
    var contrast = 0.0    // 0...1  menggelapkan bayangan; highlight TIDAK dinaikkan (cegah kilap makin terang)
    var vibrance = 0.0    // 0...1
    var lift = 0.0        // 0...~0.15  mengangkat shadow-midtone (titik hitam & putih tetap) — buat face light
    var shine = 0.0       // 0...1  meredam highlight (soft knee) — buat kilap/pantulan di wajah

    static let dimension = 33

    var isIdentity: Bool { contrast < 0.01 && vibrance < 0.01 && lift < 0.005 && shine < 0.01 }

    /// Dibulatkan (0.05; lift 0.01) supaya perubahan kecil (EV yang bergeser pelan) tidak memicu
    /// pembangunan ulang LUT tiap frame.
    func quantized() -> ColorGrade {
        func q(_ v: Double) -> Double { (v * 20).rounded() / 20 }
        // lift nilainya kecil (≤ ~0.05), jadi kuantisasinya lebih halus.
        return ColorGrade(contrast: q(contrast), vibrance: q(vibrance),
                          lift: (lift * 100).rounded() / 100, shine: q(shine))
    }

    func makeCubeData() -> Data {
        let n = Self.dimension
        var cube = [Float](repeating: 0, count: n * n * n * 4)
        let inv = 1 / Float(n - 1)
        var i = 0
        // Urutan wajib CIColorCube: R paling cepat berubah, lalu G, lalu B.
        for b in 0..<n {
            for g in 0..<n {
                for r in 0..<n {
                    let out = grade(SIMD3<Float>(Float(r), Float(g), Float(b)) * inv)
                    cube[i] = out.x
                    cube[i + 1] = out.y
                    cube[i + 2] = out.z
                    cube[i + 3] = 1
                    i += 4
                }
            }
        }
        return cube.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    // MARK: - Per-warna

    private static let lumaWeights = SIMD3<Float>(0.2126, 0.7152, 0.0722)

    private func grade(_ input: SIMD3<Float>) -> SIMD3<Float> {
        var c = input

        // 1. Kurva luminance: kontras + lift + shine dalam satu langkah.
        let k = Float(min(max(contrast, 0), 1))
        let lf = Float(max(lift, 0))
        let sh = Float(min(max(shine, 0), 1))
        if k > 0 || lf > 0 || sh > 0 {
            let y = simd_dot(c, Self.lumaWeights)
            var y2 = y

            if k > 0 {
                // S-curve (smoothstep), tapi di atas abu-abu menengah pengaruhnya dipudarkan ke nol:
                // bayangan jadi lebih dalam (warna lebih pekat), highlight kulit tidak ikut naik.
                var delta = k * (y * y * (3 - 2 * y) - y)
                if y > 0.5 { delta *= 1 - Self.smooth(0.5, 0.9, y) }
                y2 += delta
            }
            if lf > 0 {
                // Bump yang puncaknya di y≈0.33 dan nol di 0 & 1: bayangan/midtone naik,
                // hitam dan putih tidak bergeser.
                y2 += lf * 6.75 * y * (1 - y) * (1 - y)
            }
            if sh > 0 {
                // Soft knee: di atas 0.62 highlight dikompres halus (kemiringan tetap > 0 -> monoton).
                let knee: Float = 0.62
                if y2 > knee {
                    let d = y2 - knee
                    y2 -= sh * 0.7 * d * d / (2 * (1 - knee))
                }
            }
            c += SIMD3<Float>(repeating: y2 - y)
            c = simd_clamp(c, .zero, .one)
        }

        // 2. Vibrance: dorong chroma, tapi
        //    - makin jenuh sebuah warna, makin kecil dorongannya (tidak "neon")
        //    - netral (putih/abu) tidak tersentuh
        //    - rentang hue kulit (oranye-merah) dan chroma sedang dijaga lebih lembut
        let v = Float(min(max(vibrance, 0), 1))
        if v > 0 {
            let mx = max(c.x, c.y, c.z), mn = min(c.x, c.y, c.z)
            let chroma = mx - mn
            if chroma > 1e-4 {
                var hue: Float
                if mx == c.x {
                    hue = 60 * ((c.y - c.z) / chroma)
                } else if mx == c.y {
                    hue = 60 * ((c.z - c.x) / chroma + 2)
                } else {
                    hue = 60 * ((c.x - c.y) / chroma + 4)
                }
                if hue < 0 { hue += 360 }

                let skinHue = Self.bump(hue, 2, 12, 40, 55)
                let skinChroma = 1 - Self.smooth(0.35, 0.6, chroma)   // chroma tinggi (lipstik) tidak dianggap kulit
                let skin = skinHue * skinChroma

                let amount = v * 0.9 * (1 - chroma) * (1 - 0.85 * skin)
                let l = simd_dot(c, Self.lumaWeights)
                let gray = SIMD3<Float>(repeating: l)
                c = simd_clamp(gray + (c - gray) * (1 + amount), .zero, .one)
            }
        }
        return c
    }

    private static func smooth(_ e0: Float, _ e1: Float, _ x: Float) -> Float {
        let t = min(max((x - e0) / (e1 - e0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// 0 di luar [a, d], 1 di dalam [b, c], transisi halus di antaranya.
    private static func bump(_ x: Float, _ a: Float, _ b: Float, _ c: Float, _ d: Float) -> Float {
        smooth(a, b, x) * (1 - smooth(c, d, x))
    }
}
