import SwiftUI

struct LightColorSwatch: View {
    let lightColor: LightColor
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            RoundedRectangle(cornerRadius: 8)
                .fill(lightColor.color)
                .frame(width: 80, height: 50)
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8).stroke(.gray, lineWidth: 3)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(lightColor.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}