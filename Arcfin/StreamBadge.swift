// SPDX-License-Identifier: AGPL-3.0-or-later

#if !os(tvOS)
import Foundation
import JellyfinAPI

/// Settings › Notifications › Show Active Streams on App Icon (admins, off by default): the
/// app icon's badge counts what's playing on the server. Kept current every half minute while
/// Arcfin is open, and at each background refresh.
nonisolated enum StreamBadge {
    static let key = "showStreamsOnAppIcon"

    /// Counts the server's playing sessions onto the badge; clears it when the setting is off
    /// or the profile can't see the server's sessions.
    static func refresh() async {
        guard UserDefaults.standard.bool(forKey: key), let credential = IntentSession.credential() else {
            await NotificationManager.setBadge(0)
            return
        }
        let header = IntentSession.authHeader(for: credential)
        guard let sessions = try? await JellyfinMediaClient().getActiveSessions(credential: credential, authHeader: header)
        else { return }
        await NotificationManager.setBadge(sessions.filter { $0.nowPlayingItemName != nil }.count)
    }

    /// While the app is open; ends when the calling task is cancelled.
    static func keepCurrent() async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: .seconds(30))
        }
    }
}
#endif
