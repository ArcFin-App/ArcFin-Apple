// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// This version's news, biggest first, written to the person reading it. Rewritten with each
/// raise of `AppIntroduction.whatsNewVersion`, here and in the other platforms' copies.
enum WhatsNew {
    static var items: [WhatsNewItem] {
        [
            WhatsNewItem(icon: "music.note",
                         title: "Music",
                         detail: "Your Jellyfin music on the big screen: albums, artists and playlists, with lyrics and the queue beside Now Playing. Press Play/Pause on the remote to jump back to it."),
            WhatsNewItem(icon: "iphone",
                         title: "Sign In with Your iPhone",
                         detail: "Your iPhone offers to sign this Apple TV in when it's nearby, or scan the code on screen."),
            WhatsNewItem(icon: "tv",
                         title: "Live TV",
                         detail: "Watch your server's channels, browse the guide, and set recordings from a programme's details."),
            WhatsNewItem(icon: "tv.badge.wifi",
                         title: "Steadier Picture",
                         detail: "The TV stays in the video's mode between episodes, and the player's menus no longer flicker."),
            WhatsNewItem(icon: "checkmark.seal",
                         title: "Approve Requests",
                         detail: "Seerr admins can approve or decline requests from the request's page."),
            WhatsNewItem(icon: "sparkles",
                         title: "Polished Everywhere",
                         detail: "Hundreds of fixes: much more of Arcfin now follows your language, VoiceOver reads more, new-episode alerts arrive in the background, and the player and downloads are sturdier."),
        ]
    }
}
