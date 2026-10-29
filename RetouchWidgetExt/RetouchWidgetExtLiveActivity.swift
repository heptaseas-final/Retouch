//
//  RetouchWidgetExtLiveActivity.swift
//  RetouchWidgetExt
//
//  Created by Alif Tito Shiddiq ArRosyid on 29/10/26.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct RetouchWidgetExtAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct RetouchWidgetExtLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RetouchWidgetExtAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension RetouchWidgetExtAttributes {
    fileprivate static var preview: RetouchWidgetExtAttributes {
        RetouchWidgetExtAttributes(name: "World")
    }
}

extension RetouchWidgetExtAttributes.ContentState {
    fileprivate static var smiley: RetouchWidgetExtAttributes.ContentState {
        RetouchWidgetExtAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: RetouchWidgetExtAttributes.ContentState {
         RetouchWidgetExtAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: RetouchWidgetExtAttributes.preview) {
   RetouchWidgetExtLiveActivity()
} contentStates: {
    RetouchWidgetExtAttributes.ContentState.smiley
    RetouchWidgetExtAttributes.ContentState.starEyes
}
