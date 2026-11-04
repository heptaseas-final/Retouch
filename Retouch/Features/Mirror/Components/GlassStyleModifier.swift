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
        if #available(iOS 26, *) {
            content.glassEffect(glass, in: shape)
        } else {
            content.background {
                shape.fill(.ultraThinMaterial)
                if GlassConfig.variant == .white {
                    shape.fill(.white.opacity(0.25))
                }
            }
        }
    }

    @available(iOS 26, *)
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
