// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// This version's news, biggest first, written to the person reading it. Rewritten with each
/// raise of `AppIntroduction.whatsNewVersion`, here and in the other platforms' copies.
enum WhatsNew {
    static var items: [WhatsNewItem] {
        [
            WhatsNewItem(icon: "music.note",
                         title: "Your Music",
                         detail: "Albums, artists, songs, playlists and genres, with Made for You, lyrics, a visualizer, crossfade, an equalizer and a sleep timer. Every section has its own search."),
            WhatsNewItem(icon: "arrow.down.circle",
                         title: "Music Offline",
                         detail: "Download songs, albums, playlists or everything by an artist. Smart downloads keep your favourites ready, within a storage limit you set."),
            WhatsNewItem(icon: "waveform",
                         title: "ListenBrainz and Year in Music",
                         detail: "Send your listens and loves to ListenBrainz, import your listening history and look back with Year in Music."),
            WhatsNewItem(icon: "chart.bar",
                         title: "Stats for Music Too",
                         detail: "Stats has All, Movies & Shows and Music tabs, with listening from ListenBrainz or your server, and a card to share."),
            WhatsNewItem(icon: "tv",
                         title: "Live TV",
                         detail: "Channels and the guide by category, pause and rewind, recordings and reminders, radio, and your channels on Home."),
            WhatsNewItem(icon: "gearshape.2",
                         title: "Admin",
                         detail: "If you run the server: its dashboard, sessions, libraries, users, devices, plugins, backups, settings and a metadata editor, in the Admin tab."),
            WhatsNewItem(icon: "arrow.triangle.2.circlepath",
                         title: "Devices & Sync",
                         detail: "With Arcfin Sync 0.4 on your server, your settings follow you to your other devices: automatically, after asking first, or not at all. Find it in Settings › Server."),
            WhatsNewItem(icon: "person.2.badge.gearshape",
                         title: "Settings for Everyone",
                         detail: "Admins can set defaults and lock settings for everyone or for one person, in Admin › Arcfin for Everyone. A locked setting says it's set by your server's admin."),
            WhatsNewItem(icon: "iphone.and.arrow.forward",
                         title: "Sign In from Your iPhone",
                         detail: "Your iPhone can sign this Mac in, with every profile you pick, using Set Up Nearby Device in its Settings."),
            WhatsNewItem(icon: "sparkle.magnifyingglass",
                         title: "Seerr in One Tap",
                         detail: "Connect Seerr through Quick Connect, approve and decline requests, and request a whole collection."),
            WhatsNewItem(icon: "play.rectangle",
                         title: "A Better Player",
                         detail: "Skip ad breaks in recordings, raise quiet audio, Skip Intro in the controls, and AV1 where your Mac can play it. Downloads and your own files play in it too."),
            WhatsNewItem(icon: "square.and.arrow.down",
                         title: "Smarter Downloads",
                         detail: "Pick the audio and subtitle tracks and a smaller HEVC or AV1 quality. A download that fails stays in the list with the reason and Retry."),
            WhatsNewItem(icon: "house",
                         title: "Home and Library",
                         detail: "Search inside Movies, Shows, Collections and Playlists, See All pages through the whole shelf, and collections your admin features show on Home."),
            WhatsNewItem(icon: "gearshape",
                         title: "Settings in Its Own Window",
                         detail: "Settings opens in a window of its own, with only what applies to the Mac."),
            WhatsNewItem(icon: "bell.badge",
                         title: "Notifications",
                         detail: "New episodes, new films and server events, with Quiet Hours."),
        ]
    }
}
