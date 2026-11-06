//
//  LightColor.swift
//  Retouch
//
//  Created by Davin P on 25/10/26.
//


import SwiftUI

enum LightColor: CaseIterable, Identifiable {
    case white, warm, cool

    var id: Self { self }

    var color: Color {
        switch self {
        case .white: Color(hex: 0xFFFFFF)
        case .warm: Color(hex: 0xFFECBB)
        case .cool: Color(hex: 0xD7F8FF)
        }
    }

    var label: String {
        switch self {
        case .white: "White light"
        case .warm: "Warm light"
        case .cool: "Cool light"
        }
    }
}

enum LightMode: Hashable, CaseIterable {
    case off
    case on(LightColor)

    static var allCases: [LightMode] {
        [.off] + LightColor.allCases.map { .on($0) }
    }

    var next: LightMode {
        let all = Self.allCases
        let index = all.firstIndex(of: self) ?? 0
        return all[(index + 1) % all.count]
    }

    var lightColor: LightColor? {
        switch self {
        case .off: return nil
        case .on(let color): return color
        }
    }

    var isOn: Bool { lightColor != nil }

    var label: String {
        lightColor?.label ?? "Light off"
    }
}
