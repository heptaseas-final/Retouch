//
//  RetouchWidgetExtLiveActivity.swift
//  RetouchWidgetExt
//
//  Created by Alif Tito Shiddiq ArRosyid on 29/10/26.
//

import AppIntents

struct OpenRetouchIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Retouch"
    static var supportedModes: IntentModes { .foreground }

    func perform() async throws -> some IntentResult { .result() }
}
