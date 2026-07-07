//
//  RegenWidgetLiveActivity.swift
//  RegenWidget
//
//  Created by Sascha Libricht on 07.07.26.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct RegenWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct RegenWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RegenWidgetAttributes.self) { context in
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

extension RegenWidgetAttributes {
    fileprivate static var preview: RegenWidgetAttributes {
        RegenWidgetAttributes(name: "World")
    }
}

extension RegenWidgetAttributes.ContentState {
    fileprivate static var smiley: RegenWidgetAttributes.ContentState {
        RegenWidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: RegenWidgetAttributes.ContentState {
         RegenWidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: RegenWidgetAttributes.preview) {
   RegenWidgetLiveActivity()
} contentStates: {
    RegenWidgetAttributes.ContentState.smiley
    RegenWidgetAttributes.ContentState.starEyes
}
