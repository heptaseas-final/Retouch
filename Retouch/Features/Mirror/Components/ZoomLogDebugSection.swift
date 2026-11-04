import SwiftUI
import UIKit
internal import Combine

/// Bagian debug overlay: ringkasan log, salin log, reset profil belajar. Tempelkan ke overlay yang sudah ada.
struct ZoomLogDebugSection: View {
    let summary: () -> ZoomLogSummary
    let exportText: () -> String
    let resetLearning: () -> Void
    let clearLog: () -> Void

    @State private var current = ZoomLogSummary()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(current.text)
                .font(.system(size: 11, design: .monospaced))
            HStack(spacing: 8) {
                Button("Salin log") { UIPasteboard.general.string = exportText() }
                Button("Hapus log") { clearLog(); current = summary() }
                Button("Reset profil") { resetLearning() }
            }
            .font(.system(size: 11, weight: .semibold))
            .buttonStyle(.bordered)
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            current = summary()
        }
    }
}
