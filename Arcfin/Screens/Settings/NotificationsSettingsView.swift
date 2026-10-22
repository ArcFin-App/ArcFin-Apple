// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

struct NotificationsSettingsView: View {
    @Environment(AuthManager.self) private var authManager
    @AppStorage("notifyNewContent") private var notifyNewContent = true
    @AppStorage("notifyDownload")   private var notifyDownload   = true
    @AppStorage("notifyRequestUpdates") private var notifyRequestUpdates = true
    @AppStorage("notifyWatchlistAvailable") private var notifyWatchlistAvailable = true

    var body: some View {
        List {
            Section {
                Toggle(isOn: $notifyNewContent) {
                    TVRowLabelText(title: "New Content Added")
                }
                .tvListRow()
                .syncLocked("notifyNewContent", authManager)
                Toggle("Request Updates", isOn: $notifyRequestUpdates)
                    .syncLocked("notifyRequestUpdates", authManager)
                Toggle("Watchlist Available", isOn: $notifyWatchlistAvailable)
                    .syncLocked("notifyWatchlistAvailable", authManager)
                // No downloads on macOS — nothing would ever trigger this notification there.
                #if !os(tvOS)
                Toggle("Download Complete", isOn: $notifyDownload)
                    .syncLocked("notifyDownload", authManager)
                #endif
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge("Notifications")
        .onChange(of: notifyNewContent) { _, isOn in if isOn { Task { await NotificationManager.requestAuthorizationIfNeeded() } } }
        .onChange(of: notifyRequestUpdates) { _, isOn in if isOn { Task { await NotificationManager.requestAuthorizationIfNeeded() } } }
        .onChange(of: notifyWatchlistAvailable) { _, isOn in if isOn { Task { await NotificationManager.requestAuthorizationIfNeeded() } } }
    }
}

#Preview {
    NavigationStack { NotificationsSettingsView() }
        .environment(AuthManager())
}
