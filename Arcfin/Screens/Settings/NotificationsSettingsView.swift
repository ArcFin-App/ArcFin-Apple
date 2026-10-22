// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

struct NotificationsSettingsView: View {
    @Environment(AuthManager.self) private var authManager
    @AppStorage("notifyNewContent") private var notifyNewContent = true
    @AppStorage("notifyDownload")   private var notifyDownload   = true
    @AppStorage("notifyRequestUpdates") private var notifyRequestUpdates = true
    @AppStorage("notifyWatchlistAvailable") private var notifyWatchlistAvailable = true
    @AppStorage(QuietHours.enabledKey) private var quietHoursEnabled = false
    @AppStorage(QuietHours.startKey) private var quietStart = QuietHours.defaultStart
    @AppStorage(QuietHours.endKey) private var quietEnd = QuietHours.defaultEnd

    #if !os(tvOS)
    /// A time picker over minutes after midnight.
    private func time(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: minutes.wrappedValue / 60, minute: minutes.wrappedValue % 60, second: 0, of: Date()) ?? Date() },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                minutes.wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }
    #endif

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

            #if !os(tvOS)
            Section {
                Toggle("Quiet Hours", isOn: $quietHoursEnabled)
                    .syncLocked(QuietHours.enabledKey, authManager)
                if quietHoursEnabled {
                    DatePicker("From", selection: time($quietStart), displayedComponents: .hourAndMinute)
                    DatePicker("To", selection: time($quietEnd), displayedComponents: .hourAndMinute)
                }
            } footer: {
                Text("Notifications that arrive during quiet hours go straight to Notification Center, without a sound or banner.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }
            #endif
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
