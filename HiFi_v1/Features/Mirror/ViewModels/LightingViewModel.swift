//
//  LightingViewModel.swift
//  HiFi_v1
//
//  Created by Davin P on 25/10/26.
//


import Observation

@MainActor
@Observable
final class LightingViewModel {
    static let defaultBrightness = 1.0

    private(set) var isAutoBrightness = true
    private(set) var selectedColor: LightColor = .white
    private(set) var brightness = LightingViewModel.defaultBrightness  // 0...3, titik berhenti

    func setAuto(_ isOn: Bool) {
        isAutoBrightness = isOn
        if isOn { brightness = Self.defaultBrightness }
    }

    func setBrightness(_ value: Double) {
        brightness = value
        isAutoBrightness = false
    }

    func select(_ color: LightColor) {
        selectedColor = color
    }
}