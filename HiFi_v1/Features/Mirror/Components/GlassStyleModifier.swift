//
//  GlassStyleModifier.swift
//  HiFi_v1
//
//  Created by Davin P on 25/10/26.
//


import SwiftUI

struct GlassStyleModifier<S: Shape>: ViewModifier {
    let shape: S

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26, *), GlassConfig.mode == .automatic {
            content.glassEffect(liquidGlass, in: shape)
        } else {
            content
                .background(shape.fill(materialTint))
                .background(shape.fill(.ultraThinMaterial))
                .overlay(shape.stroke(.white.opacity(0.4), lineWidth: 1))
        }
    }

    @available(iOS 26, *)
    private var liquidGlass: Glass {
        switch GlassConfig.variant {
        case .white: .regular.tint(.white.opacity(0.5))
        case .transparent: .regular
        }
    }

    private var materialTint: Color {
        GlassConfig.variant == .white ? .white.opacity(0.5) : .clear
    }
}

extension View {
    func glassStyle<S: Shape>(in shape: S) -> some View {
        modifier(GlassStyleModifier(shape: shape))
    }
}