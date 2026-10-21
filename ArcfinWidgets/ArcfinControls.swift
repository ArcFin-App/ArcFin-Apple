// SPDX-License-Identifier: AGPL-3.0-or-later

import AppIntents
import SwiftUI
import WidgetKit

// Controls for Control Center, the Lock Screen and the Action button. Each opens the app at
// one of its own arcfin:// links, which ContentView routes.

private func arcfinURL(_ path: String) -> URL {
    URL(string: "arcfin://\(path)")!
}

struct ResumeWatchingControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.psmattas.arcfin.control.resume") {
            ControlWidgetButton(action: OpenURLIntent(arcfinURL("resume"))) {
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
            ControlWidgetButton(action: OpenURLIntent(arcfinURL("downloads"))) {
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
            ControlWidgetButton(action: OpenURLIntent(arcfinURL("discover"))) {
                Label("Discover", systemImage: "sparkle.magnifyingglass")
            }
        }
        .displayName("Discover & Request")
        .description("Find something new and request it.")
    }
}
