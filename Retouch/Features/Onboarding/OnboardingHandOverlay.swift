//
//  OnboardingHandOverlay.swift
//  Retouch
//
//  Created by Gabriella Angelina Widjaja on 06/11/26.
//


import SwiftUI

struct OnboardingHandOverlay: View {
    var assetName: String = "hand-outline"
    var eyeAnchor: CGPoint?
    var tip: UnitPoint = UnitPoint(x: 0.08, y: 0.04)
    var width: CGFloat = 200

    @State private var isBreathing = false

    private var aspect: CGFloat {
        guard let size = UIImage(named: assetName)?.size, size.width > 0 else { return 1 }
        return size.height / size.width
    }

    var body: some View {
        GeometryReader { proxy in
            if let eyeAnchor {
                let w = width
                let h = width * aspect
                let point = CGPoint(
                    x: eyeAnchor.x * proxy.size.width,
                    y: eyeAnchor.y * proxy.size.height
                )

                Image(assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: w, height: h)
                    .position(
                        x: point.x - tip.x * w + w / 2,
                        y: point.y - tip.y * h + h / 2
                    )
                    // Bayangan supaya garis tetap terlihat di kulit/latar terang.
                    .shadow(color: .black.opacity(0.45), radius: 6, y: 2)
                    .scaleEffect(isBreathing ? 1.04 : 1, anchor: UnitPoint(x: tip.x, y: tip.y))
                    .opacity(isBreathing ? 1 : 0.8)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                isBreathing = true
            }
        }
    }
}

struct OnboardingHighlight: ViewModifier {
    let isActive: Bool
    let color: Color

    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .background {
                if isActive {
                    Capsule()
                        .fill(color.opacity(isPulsing ? 0.7 : 0.3))
                        .padding(-8)
                        .blur(radius: 12)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: isActive)
            .task(id: isActive) {
                isPulsing = false
                guard isActive else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    isPulsing = true
                }
            }
    }
}

extension View {
    func onboardingHighlight(_ isActive: Bool, color: Color) -> some View {
        modifier(OnboardingHighlight(isActive: isActive, color: color))
    }
}
