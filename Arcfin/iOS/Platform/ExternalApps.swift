// SPDX-License-Identifier: AGPL-3.0-or-later

import UIKit

/// Handing a stream to another app, by its URL scheme.
enum ExternalApps {
    static func canOpen(_ player: ExternalPlayer) -> Bool {
        guard let probe = player.schemeLink?(URL(string: "https://example.com")!) else { return false }
        return UIApplication.shared.canOpenURL(probe)
    }

    static func open(_ player: ExternalPlayer, stream: URL) {
        guard let link = player.schemeLink?(stream) else { return }
        UIApplication.shared.open(link)
    }

    static let canCopy = true

    static func copy(_ text: String) {
        UIPasteboard.general.string = text
    }
}
