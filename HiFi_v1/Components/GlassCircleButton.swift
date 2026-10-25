//
//  GlassCircleButton.swift
//  HiFi_v1
//
//  Created by Davin P on 25/10/26.
//
import SwiftUI

struct GlassCircleButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title3.weight(.medium))
                .foregroundStyle(.black)
                .frame(width: 44, height: 44)
                .glassStyle(in: Circle())
        }
        .buttonStyle(.plain)
    }
}
