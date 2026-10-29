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
