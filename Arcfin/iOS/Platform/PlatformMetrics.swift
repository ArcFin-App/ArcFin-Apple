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
    static let loginSideBySide = false
    /// Can be set up from Arcfin on an iPhone or iPad on the same network while signed out
    /// (#481): Apple TV, iPad and Mac.
    static var hostsNearbySetup: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    /// What's Playing? with ShazamKit, and Apple Music for songs not on the server. The Mac
    /// would need a microphone entitlement, and its MusicKit can't play the catalog.
    static let identifiesSongs = true
    static let playsAppleMusic = true
    /// What it says it is to the phone setting it up.
    /// How tall a music page's hero art goes: here, the full square across the screen.
    static let musicHeroMaxHeight: CGFloat = .infinity
    static let nearbySetupKind = DeviceSetup.DeviceKind.iPad
    /// Where Local Network is turned on for the app, for setup from a phone.
    static let localNetworkSettings = URL(string: UIApplication.openSettingsURLString)
    /// Offers to set up a signed-out Apple TV, iPad or Mac on the same network (#481).
    static let setsUpNearbyDevices = true
    /// Sheets with a lot in them lay it out in two columns across the screen (TVs are landscape).
    static let sheetsSideBySide = false
    /// Acts as a remote for Arcfin (or another Jellyfin app) playing elsewhere (#457).
    static let controlsOtherDevices = true
    static let licensePlatform = "iOS"
    static let descriptionMaxWidth: CGFloat = 720
    static let pagePad: CGFloat = 20
    static let shelfGap: CGFloat = 12
    static let posterCard = CGSize(width: 110, height: 165)
    static let backdropCard = CGSize(width: 240, height: 135)
    static let wideCard = CGSize(width: 200, height: 113)
    static let fontScale: CGFloat = 1.0
    /// The player can tell when its sound is turned all the way down.
    static let detectsMutedSound = true
    /// How to hold playback at speed here, for Settings › Playback › Hold Speed.
    static let holdSpeedHint: LocalizedStringKey = "Touch and hold the video to play at this speed until you let go."

    /// The point size `scaledFont(size:)` starts from.
    static func scaledFontSize(_ size: CGFloat) -> CGFloat {
        size * DT.Scale.font
    }

    /// Browsing text (shelves, cards, title pages): the system text style, with Dynamic Type.
    static func contentFont(_ style: Font.TextStyle, design: Font.Design?, weight: Font.Weight?) -> Font {
        .system(style, design: design, weight: weight)
    }
}
