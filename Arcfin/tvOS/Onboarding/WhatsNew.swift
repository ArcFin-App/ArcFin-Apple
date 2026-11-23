// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// This version's news, biggest first, written to the person reading it. Rewritten with each
/// raise of `AppIntroduction.whatsNewVersion`, here and in the other platforms' copies.
enum WhatsNew {
    static var items: [WhatsNewItem] {
        [
            WhatsNewItem(icon: "music.note",
                         title: "Your Music",
                         detail: "Albums, artists, songs, playlists and genres, with lyrics, Made for You and a Now Playing tab while music plays. Every section has its own search."),
            WhatsNewItem(icon: "tv",
                         title: "Live TV",
                         detail: "Channels and the guide by category, pause and rewind, recordings and reminders, radio, and your channels on Home and in the Top Shelf."),
            WhatsNewItem(icon: "qrcode",
                         title: "Sign In from Your Phone",
                         detail: "Scan the code on screen with your phone, or set this Apple TV up from your iPhone or iPad with every profile you pick."),
            WhatsNewItem(icon: "person.2",
                         title: "Who's Watching",
                         detail: "With two or more profiles, turn on Always Ask Who's Watching in Settings › Profiles, and Apple TV asks when it opens and when you come back after a while."),
            WhatsNewItem(icon: "rectangle.on.rectangle",
                         title: "Top Shelf Trailers",
                         detail: "Rest on a title in the Top Shelf and its trailer plays, when your server has one."),
            WhatsNewItem(icon: "mic",
                         title: "Siri",
                         detail: "Ask Siri to \"Play … in Arcfin\" for music, movies and shows from the remote."),
            WhatsNewItem(icon: "chart.bar",
                         title: "Stats for Music Too",
                         detail: "Stats has All, Movies & Shows and Music tabs, with listening from ListenBrainz or your server."),
            WhatsNewItem(icon: "arrow.triangle.2.circlepath",
                         title: "Devices & Sync",
                         detail: "With Arcfin Sync 0.4 on your server, your settings follow you to your other devices: automatically, after asking first, or not at all. Find it in Settings › Server."),
            WhatsNewItem(icon: "person.2.badge.gearshape",
                         title: "Settings for Everyone",
                         detail: "If you run the server, set defaults and lock settings for everyone or for one person, in Settings › Server › Arcfin for Everyone."),
            WhatsNewItem(icon: "sparkle.magnifyingglass",
                         title: "Seerr in One Tap",
                         detail: "Connect Seerr through Quick Connect, and request a whole collection."),
            WhatsNewItem(icon: "play.rectangle",
                         title: "A Better Player",
                         detail: "Skip ad breaks in recordings, raise quiet audio, Skip Intro in the controls, and the TV stays in the video's mode between episodes."),
            WhatsNewItem(icon: "square.grid.2x2",
                         title: "Home and Library",
                         detail: "Search inside Movies, Shows, Collections and Playlists, the A–Z index down the right side, and a quicker Home as you move around it."),
        ]
    }
}
