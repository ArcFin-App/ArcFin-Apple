// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// This version's news, biggest first, written to the person reading it. Rewritten with each
/// raise of `AppIntroduction.whatsNewVersion`, here and in the other platforms' copies.
enum WhatsNew {
    static var items: [WhatsNewItem] {
        [
            WhatsNewItem(icon: "arrow.triangle.2.circlepath",
                         title: "Devices & Sync",
                         detail: "With Arcfin Sync 0.4 on your server, Settings › Server › Devices & Sync names this device and lists your others. Send this device's settings to all of them, or use another one's here."),
            WhatsNewItem(icon: "questionmark.bubble",
                         title: "Sync Your Way",
                         detail: "Choose how each device syncs its settings: automatically, Ask First to check with you before using changes from another device, or Off."),
            WhatsNewItem(icon: "person.2",
                         title: "Who's Watching",
                         detail: "With two or more profiles, turn on Always Ask Who's Watching in Settings › Profiles, and Apple TV asks when it opens and when you come back after a while."),
            WhatsNewItem(icon: "person.2.badge.gearshape",
                         title: "Settings for Everyone",
                         detail: "If you run the server, choose defaults and lock settings for everyone or for one person, in Settings › Server › Arcfin for Everyone. Needs Arcfin Sync 0.4."),
            WhatsNewItem(icon: "magnifyingglass",
                         title: "Search Your Music",
                         detail: "Every Music section has its own search: favourites, playlists, artists, albums, songs and genres."),
            WhatsNewItem(icon: "forward.end",
                         title: "Skip from the Controls",
                         detail: "Skip Intro and Skip Credits sit with the player's controls while they're showing, instead of floating over them."),
        ]
    }
}
