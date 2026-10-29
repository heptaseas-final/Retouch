//
//  Color+App.swift
//  Retouch
//
//  Created by Davin P on 25/10/26.
//

import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
    static let appMagenta = Color(hex: 0x963C60)
    static let appInactive = Color(hex: 0x454546)
    static let appTitle = Color(hex: 0x5A0A28)
}
