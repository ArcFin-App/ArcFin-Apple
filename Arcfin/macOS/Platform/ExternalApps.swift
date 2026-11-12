// SPDX-License-Identifier: AGPL-3.0-or-later

import AppKit

/// Handing a stream to another app, opened with the stream's URL.
enum ExternalApps {
    static func canOpen(_ player: ExternalPlayer) -> Bool {
        appURL(player) != nil
    }

    static func open(_ player: ExternalPlayer, stream: URL) {
        guard let app = appURL(player) else { return }
        NSWorkspace.shared.open([stream], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    static let canCopy = true

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private static func appURL(_ player: ExternalPlayer) -> URL? {
        player.macBundleID.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
    }
}
