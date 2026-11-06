//
//  LightModeButton.swift
//  Retouch
//
//  Created by Gabriella Angelina Widjaja on 06/11/26.
//


import SwiftUI

struct LightModeButton: View {
    @Binding var mode: LightMode
    var onChange: ((LightMode) -> Void)? = nil
    var nextMode: (LightMode) -> LightMode = { $0.next }

    var size: CGFloat = 46
    var onLongPress: (() -> Void)? = nil

    private let accent = Color(red: 0.55, green: 0.23, blue: 0.35)
    private let inset: CGFloat = 4
    private var circleSize: CGFloat { size - inset * 2 }

    var body: some View {
        VStack(spacing: inset * 2) {
            if let lightColor = mode.lightColor {
                indicator(for: lightColor)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
            flashButton
        }
        .padding(inset)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().fill(Color.white.opacity(0.6)))
                .overlay(Capsule().strokeBorder(Color.black.opacity(0.1), lineWidth: 1))
                .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
        )
        .animation(.snappy, value: mode)
    }

    private func indicator(for lightColor: LightColor) -> some View {
        Circle()
            .fill(lightColor.color)
            .overlay(Circle().strokeBorder(Color.black.opacity(0.2), lineWidth: 1.5))
            .frame(width: circleSize, height: circleSize)
            .shadow(color: lightColor.color.opacity(0.6), radius: 10)
    }

    private var flashFace: some View {
        Image(systemName: mode.isOn ? "bolt.fill" : "bolt.slash.fill")
            .font(.system(size: circleSize * 0.45, weight: .semibold))
            .foregroundStyle(mode.isOn ? accent : Color(white: 0.25))
            .contentTransition(.symbolEffect(.replace))
            .frame(width: circleSize, height: circleSize)
            .background(Circle().fill(buttonFill))
            .overlay(Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: 1))
    }

    private var buttonFill: LinearGradient {
        LinearGradient(colors: [.white, Color(white: 0.94)], startPoint: .top, endPoint: .bottom)
    }

    private var flashButton: some View {
        flashFace
            .contentShape(Circle())
            .onTapGesture(perform: tap)
            .onLongPressGesture(minimumDuration: 0.5) { onLongPress?() }
            .sensoryFeedback(.impact(weight: .light), trigger: mode)
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Light mode")
            .accessibilityValue(mode.label)
            .accessibilityAction { tap() }
    }

    private func tap() {
        mode = nextMode(mode)
        onChange?(mode)
    }
}

// MARK: - Preview

#Preview {
    struct Demo: View {
        @State private var mode: LightMode = .off
        var body: some View {
            HStack(alignment: .bottom) {
                LightModeButton(mode: $mode) { print("Mode:", $0.label) }
                Spacer()
            }
            .padding()
        }
    }
    return Demo()
}
