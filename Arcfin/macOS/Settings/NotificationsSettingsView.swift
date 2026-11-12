// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

struct NotificationsSettingsView: View {
    @Environment(AuthManager.self) private var authManager
    /// Both start from the old single New Content Added setting.
    @AppStorage("notifyNewEpisodes") private var notifyNewEpisodes = UserDefaults.standard.object(forKey: "notifyNewContent") as? Bool ?? true
    @AppStorage("notifyNewFilms") private var notifyNewFilms = UserDefaults.standard.object(forKey: "notifyNewContent") as? Bool ?? true
    @AppStorage("notifyServerEvents") private var notifyServerEvents = false
    @AppStorage(StreamBadge.key) private var showsStreamBadge = false
    @AppStorage("notifyDownload")   private var notifyDownload   = true
    @AppStorage("notifyRequestUpdates") private var notifyRequestUpdates = true
    @AppStorage("notifyWatchlistAvailable") private var notifyWatchlistAvailable = true
    @AppStorage(QuietHours.enabledKey) private var quietHoursEnabled = false
    @AppStorage(QuietHours.startKey) private var quietStart = QuietHours.defaultStart
    @AppStorage(QuietHours.endKey) private var quietEnd = QuietHours.defaultEnd

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

    var body: some View {
        List {
            Section {
                Toggle(isOn: $notifyNewEpisodes) {
                    TVRowLabelText(title: "New Episodes", detail: "When a new episode arrives of a show in your Continue Watching or Next Up.")
                }
                .tvListRow()
                .syncLocked("notifyNewEpisodes", authManager)
                Toggle(isOn: $notifyNewFilms) {
                    TVRowLabelText(title: "New Films", detail: "When a new film lands in your libraries.")
                }
                .tvListRow()
                .syncLocked("notifyNewFilms", authManager)
                Toggle(isOn: $notifyRequestUpdates) {
                    TVRowLabelText(title: "Request Updates", detail: "When a Seerr request is approved, declined or available.")
                }
                .syncLocked("notifyRequestUpdates", authManager)
                Toggle(isOn: $notifyWatchlistAvailable) {
                    TVRowLabelText(title: "Watchlist Available", detail: "When a title on your watchlist arrives in your library.")
                }
                .syncLocked("notifyWatchlistAvailable", authManager)
                Toggle(isOn: $notifyDownload) {
                    TVRowLabelText(title: "Download Complete", detail: "When a download finishes.")
                }
                .syncLocked("notifyDownload", authManager)
            }

            if authManager.isAdmin {
                Section {
                    Toggle(isOn: $notifyServerEvents) {
                        TVRowLabelText(title: "Server Events", detail: "Failed tasks and sign-ins, warnings, and plugins installed or updated.")
                    }
                    .syncLocked("notifyServerEvents", authManager)
                    Toggle(isOn: $showsStreamBadge) {
                        TVRowLabelText(title: "Show Active Streams on App Icon", detail: "The app icon's badge counts what's playing on the server.")
                    }
                    .syncLocked(StreamBadge.key, authManager)
                } header: {
                    Text("Admin")
                } footer: {
                    Text("The badge updates every half minute while Arcfin is open. In the background, the system decides how often Arcfin checks: on iPhone and iPad usually a few times a day.")
                }
            }

            Section {
                Toggle(isOn: $quietHoursEnabled) {
                    TVRowLabelText(title: "Quiet Hours", detail: "Notifications in these hours go to Notification Center without a sound or banner.")
                }
                .syncLocked(QuietHours.enabledKey, authManager)
                if quietHoursEnabled {
                    DatePicker("From", selection: time($quietStart), displayedComponents: .hourAndMinute)
                    DatePicker("To", selection: time($quietEnd), displayedComponents: .hourAndMinute)
                }
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge("Notifications")
        .onChange(of: notifyNewEpisodes) { _, isOn in if isOn { Task { await NotificationManager.requestAuthorizationIfNeeded() } } }
        .onChange(of: notifyNewFilms) { _, isOn in if isOn { Task { await NotificationManager.requestAuthorizationIfNeeded() } } }
        .onChange(of: notifyServerEvents) { _, isOn in if isOn { Task { await NotificationManager.requestAuthorizationIfNeeded() } } }
        .onChange(of: showsStreamBadge) { _, isOn in
            Task {
                if isOn { await NotificationManager.requestAuthorizationIfNeeded() }
                await StreamBadge.refresh()
            }
        }
        .onChange(of: notifyRequestUpdates) { _, isOn in if isOn { Task { await NotificationManager.requestAuthorizationIfNeeded() } } }
        .onChange(of: notifyWatchlistAvailable) { _, isOn in if isOn { Task { await NotificationManager.requestAuthorizationIfNeeded() } } }
    }
}

#Preview {
    NavigationStack { NotificationsSettingsView() }
        .environment(AuthManager())
}
