// SPDX-License-Identifier: AGPL-3.0-or-later

import AppIntents
import SwiftUI
import WidgetKit

// Controls for Control Center, the Lock Screen and the Action button. Their intents live in
// Arcfin/Intents/ControlIntents.swift, shared with the app, which performs them.

struct ResumeWatchingControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.psmattas.arcfin.control.resume") {
            ControlWidgetButton(action: ResumeWatchingIntent()) {
                Label("Resume Watching", systemImage: "play.fill")
            }
        }
        .displayName("Resume Watching")
        .description("Plays whatever you were watching last.")
    }
}

struct DownloadsControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.psmattas.arcfin.control.downloads") {
            ControlWidgetButton(action: OpenDownloadsIntent()) {
                Label("Downloads", systemImage: "arrow.down.circle")
            }
        }
        .displayName("Downloads")
        .description("Opens your downloads, for watching offline.")
    }
}

struct DiscoverControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.psmattas.arcfin.control.discover") {
            ControlWidgetButton(action: OpenDiscoverIntent()) {
                Label("Discover", systemImage: "sparkle.magnifyingglass")
            }
        }
        .displayName("Discover & Request")
        .description("Find something new and request it.")
    }
}
