import SwiftUI

/// Ring light oval di sekeliling layar.
///
/// Koordinat dinormalisasi: tengah layar = 0, tepi kiri/kanan/atas/bawah = 1, sudut ≈ 1.42.
/// Area di dalam radius `clear` transparan (wajah), di luarnya menyala. Saat level naik,
/// `clear` bergerak dari sudut (1.42) ke dalam sampai 1 − ringWidth, jadi cahaya muncul dari
/// sudut lalu melingkar. Tepi dalam memudar sepanjang `ringWidth × softness` (smoothstep).
struct RingLightPanels: View {
    let level: Double
    let color: Color
    var maxSideFraction: CGFloat = 0.15
    var softness: Double = 0.35

    var body: some View {
        Canvas { context, size in
            let l = min(max(level, 0), 1)
            guard l > 0.001 else { return }
            context.translateBy(x: size.width / 2, y: size.height / 2)
            context.scaleBy(x: size.width / 2, y: size.height / 2)

            let ringWidth = 2 * Double(min(max(maxSideFraction, 0), 0.5))
            let fullClear = 1 - ringWidth
            let corner = 1.42
            let clear = corner + (fullClear - corner) * l
            let fade = ringWidth * min(max(softness, 0), 1)
            let solid = clear + fade
            let end = 1.5

            var stops: [Gradient.Stop] = [.init(color: color.opacity(0), location: 0),
                                          .init(color: color.opacity(0), location: clear / end)]
            let steps = 8
            for i in 1...steps where fade > 0 {
                let t = Double(i) / Double(steps)
                stops.append(.init(color: color.opacity(t * t * (3 - 2 * t)),
                                   location: min((clear + fade * t) / end, 1)))
            }
            stops.append(.init(color: color, location: min(solid / end, 1)))
            stops.append(.init(color: color, location: 1))

            context.fill(Path(CGRect(x: -end, y: -end, width: end * 2, height: end * 2)),
                         with: .radialGradient(Gradient(stops: stops), center: .zero,
                                               startRadius: 0, endRadius: end))
        }
        .allowsHitTesting(false)
    }
}
