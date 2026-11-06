import SwiftUI

/// Hijau = mata, oranye = bibir. Solid = trigger, putus-putus = hold. Garis kuning = batas mata/bibir.
struct ZoneRadiusOverlay: View {
    let viewModel: MirrorViewModel

    var body: some View {
        GeometryReader { geo in
            let zoom = viewModel.zoomState
            let zones = viewModel.debugInfo.zones
            Canvas { ctx, size in
                guard let z = zones else { return }

                func map(_ p: CGPoint) -> CGPoint {
                    CGPoint(x: size.width / 2 + zoom.scale * (p.x - size.width / 2) + zoom.offset.width,
                            y: size.height / 2 + zoom.scale * (p.y - size.height / 2) + zoom.offset.height)
                }
                func ring(_ center: CGPoint, _ radius: CGFloat, _ color: Color, dashed: Bool) {
                    let c = map(center)
                    let r = radius * zoom.scale
                    let rect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
                    ctx.stroke(Path(ellipseIn: rect), with: .color(color),
                               style: StrokeStyle(lineWidth: 1.5, dash: dashed ? [6, 4] : []))
                }

                for eye in [z.leftEye, z.rightEye] {
                    ring(eye, z.eyeTriggerRadius, .green, dashed: false)
                    ring(eye, z.eyeHoldRadius, .green.opacity(0.6), dashed: true)
                }
                if let lips = z.lips, let t = z.lipsTriggerRadius, let h = z.lipsHoldRadius {
                    ring(lips, t, .orange, dashed: false)
                    ring(lips, h, .orange.opacity(0.6), dashed: true)
                }
                if let a = z.lipsBoundaryA, let b = z.lipsBoundaryB {
                    var path = Path()
                    path.move(to: map(a))
                    path.addLine(to: map(b))
                    ctx.stroke(path, with: .color(.yellow.opacity(0.8)),
                               style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
