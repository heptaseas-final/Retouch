//
//  LightingSheetView.swift
//  HiFi_v1
//
//  Created by Davin P on 25/10/26.
//


import SwiftUI

struct LightingSheetView: View {
    let lighting: LightingViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            HStack {
                sectionTitle("Auto Brightness")
                Spacer()
                Toggle("Auto Brightness",
                       isOn: Binding(get: { lighting.isAutoBrightness }, set: lighting.setAuto))
                    .labelsHidden()
            }
            Divider()
            sectionTitle("Adjust Color")
            HStack(spacing: 16) {
                ForEach(LightColor.allCases) { item in
                    LightColorSwatch(lightColor: item,
                                     isSelected: lighting.selectedColor == item) {
                        lighting.select(item)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            
            Divider()
            sectionTitle("Adjust Brightness")
            BrightnessSlider(value: lighting.brightness, onChange: lighting.setBrightness)
                .padding(.bottom, 12)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
    }

    private var header: some View {
        ZStack {
            Text("Adjust Lighting")
                .font(.headline)
                .foregroundStyle(Color.appTitle)
            HStack {
                GlassCircleButton(systemName: "xmark") { dismiss() }
                Spacer()
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text).foregroundStyle(Color.appMagenta)
    }
}
