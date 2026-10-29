//
//  GlassStyleModifier.swift
//  Retouch
//
//  Created by Davin P on 25/10/26.
//
import SwiftUI

struct GlassStyleModifier<S: Shape>: ViewModifier {
    let shape: S

    func body(content: Content) -> some View {
        content.glassEffect(glass, in: shape)
    }

    private var glass: Glass {
        switch GlassConfig.variant {
        case .white: .regular.tint(.white.opacity(0.5))
        case .transparent: .clear
        }
    }
}

extension View {
    func glassStyle<S: Shape>(in shape: S) -> some View {
        modifier(GlassStyleModifier(shape: shape))
    }
}
