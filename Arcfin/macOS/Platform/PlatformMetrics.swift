// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// The design tokens that differ on this platform; `DT` reads them.
enum PlatformMetrics {
    static let pagePad: CGFloat = 28
    static let shelfGap: CGFloat = 16
    // Seen from further away than a phone, in a window several times wider.
    static let posterCard = CGSize(width: 150, height: 225)
    static let backdropCard = CGSize(width: 320, height: 180)
    static let wideCard = CGSize(width: 280, height: 158)
    static let fontScale: CGFloat = 1.0
    /// The player can tell when its sound is turned all the way down.
    static let detectsMutedSound = true

    /// The point size `scaledFont(size:)` starts from.
    static func scaledFontSize(_ size: CGFloat) -> CGFloat {
        size * DT.Scale.font
    }
}
