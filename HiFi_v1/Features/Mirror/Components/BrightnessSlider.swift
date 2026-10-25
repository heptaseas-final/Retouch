//
//  BrightnessSlider.swift
//  HiFi_v1
//
//  Created by Davin P on 25/10/26.
//


import SwiftUI

struct BrightnessSlider: View {
    let value: Double
    let onChange: (Double) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bolt.slash.fill").foregroundStyle(.gray)
            Slider(value: Binding(get: { value }, set: onChange), in: 0...3, step: 1)
                .overlay(alignment: .bottom) { dots }
            Image(systemName: "bolt.fill").foregroundStyle(.gray)
        }
    }

    private var dots: some View {
        HStack {
            ForEach(0..<4, id: \.self) { index in
                Circle().fill(.gray.opacity(0.5)).frame(width: 5, height: 5)
                if index < 3 { Spacer() }
            }
        }
        .padding(.horizontal, 14)
        .offset(y: 16)
    }
}