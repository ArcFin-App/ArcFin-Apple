// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

struct NotificationsSettingsView: View {
    @AppStorage("notifyNewContent") private var notifyNewContent = true
    @AppStorage("notifyDownload")   private var notifyDownload   = true

    var body: some View {
        List {
            Section {
                Toggle("New Content Added", isOn: $notifyNewContent)
                    .tvListRow()
                // No downloads on macOS — nothing would ever trigger this notification there.
                #if os(iOS)
                Toggle("Download Complete", isOn: $notifyDownload)
                #endif
            }
        }
        .arcfinListStyle()
        .background(DT.Color.backgroundPrimary)
        .arcfinNavTitleLarge("Notifications")
    }
}

#Preview {
    NavigationStack { NotificationsSettingsView() }
}
