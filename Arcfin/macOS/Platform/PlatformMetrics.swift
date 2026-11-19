// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

/// The design tokens that differ on this platform; `DT` reads them.
enum PlatformMetrics {
    /// Whether the app tells Now Playing if it's playing. Only the Mac takes it; elsewhere the
    /// system works it out from the audio session and logs a missing entitlement instead.
    static let setsNowPlayingState = true
    /// How wide a title's description may run. The window sets it here; it's resized at will.
    /// Which platform's components the Licenses screen lists.
    /// The sign-in pages: two columns across the screen (what to do, and what to do it with),
    /// or one readable column.
    static let loginSideBySide = false
    /// Can be set up from Arcfin on an iPhone or iPad on the same network while signed out
    /// (#481): Apple TV, iPad and Mac.
    static let hostsNearbySetup = true
    /// What's Playing? with ShazamKit, and Apple Music for songs not on the server. The Mac
    /// would need a microphone entitlement, and its MusicKit can't play the catalog.
    static let identifiesSongs = false
    static let playsAppleMusic = false
    /// What it says it is to the phone setting it up.
    static let nearbySetupKind = DeviceSetup.DeviceKind.mac
    /// Offers to set up a signed-out Apple TV, iPad or Mac on the same network (#481).
    static let setsUpNearbyDevices = false
    /// Sheets with a lot in them lay it out in two columns across the screen (TVs are landscape).
    static let sheetsSideBySide = false
    /// Acts as a remote for Arcfin (or another Jellyfin app) playing elsewhere (#457).
    static let controlsOtherDevices = false
    static let licensePlatform = "macOS"
    static let descriptionMaxWidth: CGFloat = .infinity
    static let pagePad: CGFloat = 28
    static let shelfGap: CGFloat = 16
    // Seen from further away than a phone, in a window several times wider.
    static let posterCard = CGSize(width: 150, height: 225)
    static let backdropCard = CGSize(width: 320, height: 180)
    static let wideCard = CGSize(width: 280, height: 158)
    static let fontScale: CGFloat = 1.0
    /// The player can tell when its sound is turned all the way down.
    static let detectsMutedSound = true
    /// How to hold playback at speed here, for Settings › Playback › Hold Speed.
    static let holdSpeedHint: LocalizedStringKey = "Hold the right arrow key to play at this speed until you let go."

    /// The point size `scaledFont(size:)` starts from.
    static func scaledFontSize(_ size: CGFloat) -> CGFloat {
        size * DT.Scale.font
    }

    /// Browsing text (shelves, cards, title pages) one step up from the Mac's own text styles,
    /// which are sized for forms and lists: a caption is 10 pt there, too small beside posters
    /// in a wide window. Forms keep the system styles.
    static func contentFont(_ style: Font.TextStyle, design: Font.Design?, weight: Font.Weight?) -> Font {
        let size: CGFloat = switch style {
        case .caption2: 11
        case .caption, .footnote: 12
        case .subheadline: 13
        case .callout, .body: 14
        case .headline: 15
        case .title3: 17
        case .title2: 20
        case .title: 26
        case .largeTitle: 30
        default: 14
        }
        return .system(size: size, weight: weight ?? (style == .headline ? .semibold : .regular), design: design ?? .default)
    }
}
