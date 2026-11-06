//
//  InstructionBubble.swift
//  Retouch
//
//  Created by Gabriella Angelina Widjaja on 06/11/26.
//


import SwiftUI

struct InstructionBubble: View {
    let text: String

    private let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)

    var body: some View {
        Text(text)
            .font(.body)
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .frame(maxWidth: 300)
            .background {
                shape
                    .fill(.ultraThinMaterial)
                    .overlay(shape.fill(Color.black.opacity(0.35)))
                    .overlay(shape.strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
            }
            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            .accessibilityAddTraits(.isStaticText)
    }
}

#Preview {
    ZStack {
        Color.gray
        VStack(spacing: 16) {
            InstructionBubble(text: "Place your hand or makeup product near the area you want to retouch.")
            InstructionBubble(text: "Tap to see warm light.")
        }
    }
}
