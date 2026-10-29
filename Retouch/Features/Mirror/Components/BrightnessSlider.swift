//
//  BrightnessSlider.swift
//  Retouch
//
//  Created by Davin P on 25/10/26.
//

import SwiftUI

struct BrightnessSlider: View {
    let value: Double
    let onChange: (Double) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bolt.slash.fill").foregroundStyle(.black)
            Slider(value: Binding(get: { value }, set: onChange), in: 0...1)
            Image(systemName: "bolt.fill").foregroundStyle(.black)
        }
    }
}
