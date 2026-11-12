// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// The design tokens that differ on this platform; `DT` reads them.
enum PlatformMetrics {
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
}
