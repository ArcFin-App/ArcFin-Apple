// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// This version's news, biggest first, written to the person reading it. Rewritten with each
/// raise of `AppIntroduction.whatsNewVersion`, here and in the other platforms' copies.
enum WhatsNew {
    static var items: [WhatsNewItem] {
        [
            WhatsNewItem(icon: "forward.end",
                         title: "Skip Intros in Downloads",
                         detail: "Downloaded movies and episodes now offer to skip the recap, intro, credits and preview, just like streaming, and skip them for you if you've turned that on."),
            WhatsNewItem(icon: "play.tv",
                         title: "Trailers on Home",
                         detail: "The featured title's trailer now plays all the way through while the details fade away. For sound, turn on Hero Trailer Sound in Settings › Appearance."),
            WhatsNewItem(icon: "textformat.abc",
                         title: "Jump to a Letter",
                         detail: "In a library sorted by name, pick a letter under Filter & Sort to jump straight to it."),
            WhatsNewItem(icon: "wand.and.rays",
                         title: "Help for Videos That Won't Play",
                         detail: "If a video won't play, or HDR or Dolby Vision looks dim or off-colour, new switches in Settings › Playback › Codec Compatibility have your server convert it."),
            WhatsNewItem(icon: "checkmark.circle",
                         title: "Already in Your Library",
                         detail: "Discover, Search and Seerr pages show which titles you already have, so you won't request them twice."),
            WhatsNewItem(icon: "hand.draw",
                         title: "Scrub with the Touch Surface",
                         detail: "Glide across the Siri Remote's touch surface to move freely through a movie or episode, then click to jump there."),
            WhatsNewItem(icon: "person.badge.key",
                         title: "Signing In and Out",
                         detail: "If your server stops accepting your sign-in, Arcfin asks you to sign in again instead of showing empty pages. Signing out of your last profile asks first and removes your sign-ins from this device. Downloads stay."),
            WhatsNewItem(icon: "server.rack",
                         title: "Clearer Server Setup",
                         detail: "When an address doesn't work, setup tells you why, and servers that redirect to another address now play reliably."),
            WhatsNewItem(icon: "clock.arrow.circlepath",
                         title: "Progress That Keeps Up",
                         detail: "Title pages show where you stopped as soon as you close the player."),
            WhatsNewItem(icon: "tv",
                         title: "Tidier Apple TV Pages",
                         detail: "Home, title pages, Stats and Settings are evenly spaced, easier to read and simpler to get around with the remote."),
            WhatsNewItem(icon: "sparkles",
                         title: "A Tour of Arcfin",
                         detail: "New to Arcfin, or want a refresher? Take the tour any time from Settings."),
        ]
    }
}
