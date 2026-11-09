// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// This version's news, biggest first, written to the person reading it. Rewritten with each
/// raise of `AppIntroduction.whatsNewVersion`, here and in the other platforms' copies.
enum WhatsNew {
    static var items: [WhatsNewItem] {
        [
            WhatsNewItem(icon: "paintpalette",
                         title: "A New Look",
                         detail: "Arcfin has a new coral colour and a new app icon."),
            WhatsNewItem(icon: "play.tv",
                         title: "Spotlight Home",
                         detail: "Home opens on the featured title with its trailer, and Up and Down move through the rows one at a time."),
            WhatsNewItem(icon: "rectangle.stack",
                         title: "A Richer Top Shelf",
                         detail: "Put Arcfin in the top row of your Apple TV to see what you're watching, with logos and progress, plus Next Up."),
            WhatsNewItem(icon: "speedometer",
                         title: "Smoother Title Pages",
                         detail: "Title pages no longer slow your Apple TV down, they show when a title would end, and sheets open in a wider panel that fits what's in them."),
            WhatsNewItem(icon: "person.text.rectangle",
                         title: "Your Profile",
                         detail: "Settings › Your Profile shows your account, the libraries you can see, parental controls and what you're allowed to do."),
            WhatsNewItem(icon: "exclamationmark.bubble",
                         title: "Clearer Playback Problems",
                         detail: "If a video stops partway, Arcfin tells you instead of leaving a black screen, and the VLC engine now moves on to Up Next at the end."),
            WhatsNewItem(icon: "person.2",
                         title: "Cast & Characters",
                         detail: "X-Ray in the player is now called Cast & Characters."),
        ]
    }
}
