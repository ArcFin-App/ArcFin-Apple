// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// This version's news, biggest first, written to the person reading it. Rewritten with each
/// raise of `AppIntroduction.whatsNewVersion`, here and in the other platforms' copies.
enum WhatsNew {
    static var items: [WhatsNewItem] {
        [
            WhatsNewItem(icon: "music.note",
                         title: "Music",
                         detail: "Your Jellyfin music library has its own tab: albums, artists, playlists and Made for You mixes, with lyrics, a queue, shuffle and repeat, and gapless playback."),
            WhatsNewItem(icon: "arrow.down.to.line",
                         title: "Music Offline",
                         detail: "Download songs, albums, playlists or everything by an artist, and keep favourites downloaded automatically."),
            WhatsNewItem(icon: "shareplay",
                         title: "Listen Together",
                         detail: "On a FaceTime call, choose SharePlay in Now Playing and everyone hears the same song at the same time, each from their own account."),
            WhatsNewItem(icon: "car",
                         title: "CarPlay and Apple Watch",
                         detail: "Play your music in CarPlay, and control what's playing from your Apple Watch."),
            WhatsNewItem(icon: "appletv",
                         title: "Set Up Apple TV with Your iPhone",
                         detail: "Open Arcfin on an Apple TV and your iPhone offers to sign it in, no typing needed."),
            WhatsNewItem(icon: "tv",
                         title: "Live TV",
                         detail: "Watch your server's channels, browse the guide, and set recordings from a programme's details."),
            WhatsNewItem(icon: "gearshape.2",
                         title: "Admin Tools",
                         detail: "If you run the server, the Admin tab shows who's watching, and lets you manage users, libraries, scheduled tasks and backups."),
            WhatsNewItem(icon: "checkmark.seal",
                         title: "Approve Requests",
                         detail: "Seerr admins can approve or decline requests from the request's page."),
            WhatsNewItem(icon: "arrow.down.circle",
                         title: "Better Downloads",
                         detail: "Choose the audio tracks and subtitles to download, and Arcfin keeps your queue and progress if the app is closed mid-download."),
            WhatsNewItem(icon: "sparkles",
                         title: "Polished Everywhere",
                         detail: "Hundreds of fixes: much more of Arcfin now follows your language, VoiceOver reads more, new-episode alerts arrive in the background, and the player and downloads are sturdier."),
        ]
    }
}
