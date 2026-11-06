//
//  CameraControls.swift
//  Retouch
//

import SwiftUI

enum ControlEmphasis: Equatable {
    case normal
    case dimmed
    case highlighted(Color)
}

struct CameraControls: View {
    @Binding var part: FacePart
    @Binding var lightMode: LightMode
    var nextLightMode: (LightMode) -> LightMode = { $0.next }
    var onLightTap: ((LightMode) -> Void)? = nil
    var onLightLongPress: (() -> Void)? = nil
    var pickerEmphasis: ControlEmphasis = .normal
    var flashEmphasis: ControlEmphasis = .normal

    var height: CGFloat = 46
    var pickerWidth: CGFloat = 220

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            LightModeButton(mode: $lightMode, onChange: onLightTap, nextMode: nextLightMode,
                            size: height, onLongPress: onLightLongPress)
                .emphasis(flashEmphasis)
                .frame(maxWidth: .infinity)

            HorizontalPicker(items: FacePart.allCases, selection: $part, itemWidth: 80, height: height,
                             indicatorWidth: 88, indicatorInset: 4) { part, isSelected in
                PickerSymbol(systemName: part.systemImage, label: part.label, isSelected: isSelected)
                    .accessibilityLabel(part.title)
            }
            .frame(width: pickerWidth, height: height)
            .emphasis(pickerEmphasis)

            // Penyeimbang sisi kanan supaya picker tetap di tengah layar.
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: height)
        }
    }
}

private extension View {
    @ViewBuilder
    func emphasis(_ emphasis: ControlEmphasis) -> some View {
        switch emphasis {
        case .normal:
            self
        case .dimmed:
            self.opacity(0.5).allowsHitTesting(false)
        case .highlighted(let color):
            self.onboardingHighlight(true, color: color)
        }
    }
}
