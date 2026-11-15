// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// The design tokens that differ on this platform; `DT` reads them.
enum PlatformMetrics {
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
