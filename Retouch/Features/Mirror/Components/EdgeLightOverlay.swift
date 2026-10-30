import SwiftUI

/// Border light di pinggir layar. Digambar di atas preview, di luar transformasi zoom,
/// jadi tetap menempel di pinggir walau kamera di-zoom.
struct EdgeLightOverlay: View {
    let level: Double          // 0...1
    let color: Color
    var maxThicknessFraction: CGFloat = 0.12   // dari lebar layar
    var featherFraction: CGFloat = 0.4         // bagian yang memudar ke tengah

    var body: some View {
        GeometryReader { geo in
            let t = geo.size.width * maxThicknessFraction * CGFloat(level)
            let fade = Gradient(stops: [
                .init(color: color, location: 0),
                .init(color: color, location: 1 - featherFraction),
                .init(color: color.opacity(0), location: 1)
            ])
            ZStack {
                Rectangle()
                    .fill(LinearGradient(gradient: fade, startPoint: .top, endPoint: .bottom))
                    .frame(height: t)
                    .frame(maxHeight: .infinity, alignment: .top)
                Rectangle()
                    .fill(LinearGradient(gradient: fade, startPoint: .bottom, endPoint: .top))
                    .frame(height: t)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                Rectangle()
                    .fill(LinearGradient(gradient: fade, startPoint: .leading, endPoint: .trailing))
                    .frame(width: t)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Rectangle()
                    .fill(LinearGradient(gradient: fade, startPoint: .trailing, endPoint: .leading))
                    .frame(width: t)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .allowsHitTesting(false)
    }
}
