//
//  GlassIconButton.swift
//  HiFi_v1
//
//  Created by Davin P on 25/10/26.
//

import SwiftUI

struct GlassIconButton: View {
    let systemName: String
    var color: Color = .appMagenta
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title2)
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, minHeight: 56)
                .glassStyle(in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
