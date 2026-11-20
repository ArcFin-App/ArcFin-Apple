// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

/// The design tokens that differ on this platform; `DT` reads them.
enum PlatformMetrics {
    /// Whether the app tells Now Playing if it's playing. Only the Mac takes it; elsewhere the
    /// system works it out from the audio session and logs a missing entitlement instead.
    static let setsNowPlayingState = false
    /// How wide a title's description may run: lines across a whole iPad are too long to read.
    /// Which platform's components the Licenses screen lists.
    /// The sign-in pages: two columns across the screen (what to do, and what to do it with),
    /// or one readable column.
    static let loginSideBySide = true
    /// Can be set up from Arcfin on an iPhone or iPad on the same network while signed out
    /// (#481): Apple TV, iPad and Mac.
    static let hostsNearbySetup = true
    /// What's Playing? with ShazamKit, and Apple Music for songs not on the server. The Mac
    /// would need a microphone entitlement, and its MusicKit can't play the catalog.
    static let identifiesSongs = false
    static let playsAppleMusic = false
    /// What it says it is to the phone setting it up.
    static let nearbySetupKind = DeviceSetup.DeviceKind.appleTV
    /// Apple TV has no settings link; the hint says where to look.
    static let localNetworkSettings: URL? = nil
    /// Offers to set up a signed-out Apple TV, iPad or Mac on the same network (#481).
    static let setsUpNearbyDevices = false
    /// Sheets with a lot in them lay it out in two columns across the screen (TVs are landscape).
    static let sheetsSideBySide = true
    /// Acts as a remote for Arcfin (or another Jellyfin app) playing elsewhere (#457).
    static let controlsOtherDevices = false
    static let licensePlatform = "tvOS"
    static let descriptionMaxWidth: CGFloat = 720
    static let pagePad: CGFloat = 20
    static let shelfGap: CGFloat = 12
    static let posterCard = CGSize(width: 320, height: 180)
    static let backdropCard = CGSize(width: 240, height: 135)
    static let wideCard = CGSize(width: 200, height: 113)
    static let fontScale: CGFloat = 2.0
    /// The player can tell when its sound is turned all the way down.
    static let detectsMutedSound = false
    /// How to hold playback at speed here, for Settings › Playback › Hold Speed.
    static let holdSpeedHint: LocalizedStringKey = "Press and hold the clickpad to play at this speed until you let go."

    /// The point size `scaledFont(size:)` starts from.
    static func scaledFontSize(_ size: CGFloat) -> CGFloat {
        // 23 pt is tvOS's smallest text style; anything under it is unreadable from the couch.
        max(size * DT.Scale.font, 23)
    }

    /// Browsing text (shelves, cards, title pages): the system text style, with Dynamic Type.
    static func contentFont(_ style: Font.TextStyle, design: Font.Design?, weight: Font.Weight?) -> Font {
        .system(style, design: design, weight: weight)
    }
}
