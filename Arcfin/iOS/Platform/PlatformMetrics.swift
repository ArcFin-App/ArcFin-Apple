// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// The design tokens that differ on this platform; `DT` reads them.
enum PlatformMetrics {
    /// How wide a title's description may run: lines across a whole iPad are too long to read.
    /// Which platform's components the Licenses screen lists.
    /// Quick Connect's sign-in page: steps beside a QR code across the screen, or one column.
    static let quickConnectSideBySide = false
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
