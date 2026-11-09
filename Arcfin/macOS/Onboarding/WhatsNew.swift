// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// This version's news, biggest first, written to the person reading it. Rewritten with each
/// raise of `AppIntroduction.whatsNewVersion`, here and in the other platforms' copies.
enum WhatsNew {
    static var items: [WhatsNewItem] {
        [
            WhatsNewItem(icon: "paintpalette",
                         title: "A New Look",
                         detail: "Arcfin has a new coral colour and a new app icon, in light and dark appearance."),
            WhatsNewItem(icon: "sparkles.rectangle.stack",
                         title: "A Fuller Discover",
                         detail: "Discover mixes big cards with rows of what's trending, titles like your last watch, what's popular on your streaming services, genres and what's coming soon. Titles you've already requested now say so."),
            WhatsNewItem(icon: "person.text.rectangle",
                         title: "Your Profile",
                         detail: "Settings › Your Profile shows your account, the libraries you can see, parental controls and what you're allowed to do."),
            WhatsNewItem(icon: "number.square",
                         title: "Quick Connect in Settings",
                         detail: "Type a Quick Connect code under your profile in Settings › General to sign another device in with your account."),
            WhatsNewItem(icon: "macwindow",
                         title: "Next Episode, Same Window",
                         detail: "The next episode starts in the main window's player, and title and collection pages no longer stretch the window."),
            WhatsNewItem(icon: "exclamationmark.bubble",
                         title: "Clearer Playback Problems",
                         detail: "If a video stops partway, Arcfin tells you instead of leaving a black screen, and the VLC engine now moves on to Up Next at the end."),
            WhatsNewItem(icon: "square.grid.2x2",
                         title: "Library Counts",
                         detail: "Each library in Browse shows how many titles it holds."),
            WhatsNewItem(icon: "person.2",
                         title: "Cast & Characters",
                         detail: "X-Ray in the player is now called Cast & Characters."),
        ]
    }
}
