//
//  RetouchWidgetExtControl.swift
//  RetouchWidgetExt
//
//  Created by Alif Tito Shiddiq ArRosyid on 29/10/26.
//

import WidgetKit
import SwiftUI
import AppIntents

struct RetouchWidgetExtControl: ControlWidget {
    static let kind = "bsd.iosda.Retouch.RetouchWidgetExt"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenRetouchIntent()) {
                Label("Retouch", systemImage: "face.smiling")
            }
        }
        .displayName("Open Retouch")
        .description("Open Retouch directly from your lock screen.")
    }
}
