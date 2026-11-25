// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import UserNotifications

struct NotificationsSettingsView: View {
    @Environment(AuthManager.self) private var authManager
    /// Both start from the old single New Content Added setting.
    @AppStorage("notifyNewEpisodes") private var notifyNewEpisodes = UserDefaults.standard.object(forKey: "notifyNewContent") as? Bool ?? true
    @AppStorage("notifyNewFilms") private var notifyNewFilms = UserDefaults.standard.object(forKey: "notifyNewContent") as? Bool ?? true
    @AppStorage("notifyServerEvents") private var notifyServerEvents = false
    @AppStorage(StreamBadge.key) private var showsStreamBadge = false
    @AppStorage("notifyDownload")   private var notifyDownload   = true
    @AppStorage(MusicSettings.notifyDownloadsKey) private var notifyMusicDownloads = true
    @AppStorage("notifyRequestUpdates") private var notifyRequestUpdates = true
    @AppStorage("notifyWatchlistAvailable") private var notifyWatchlistAvailable = true
    @AppStorage(BackgroundRefresh.announcementsKey) private var notifyAnnouncements = true
    @AppStorage(BackgroundRefresh.requestsToApproveKey) private var notifyRequestsToApprove = true
    @AppStorage(BackgroundRefresh.issuesKey) private var notifyIssues = true
    @AppStorage(QuietHours.enabledKey) private var quietHoursEnabled = false
    @AppStorage(QuietHours.startKey) private var quietStart = QuietHours.defaultStart
    @AppStorage(QuietHours.endKey) private var quietEnd = QuietHours.defaultEnd
    /// Whether Arcfin may send notifications at all; nil until read.
    @State private var authorization: UNAuthorizationStatus?
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

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

    @ViewBuilder
    private var permissionSection: some View {
        switch authorization {
        case .notDetermined:
            Section {
                Button("Allow Notifications") { Task { await askForPermission() } }
            } footer: {
                Text("Arcfin can't send any of these until you allow notifications.")
            }
        case .denied:
            Section {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                }
            } footer: {
                Text("Notifications are off for Arcfin. Turn them on in Settings to get any of these.")
            }
        default:
            EmptyView()
        }
    }

    private func askForPermission() async {
        await NotificationManager.requestAuthorizationIfNeeded()
        authorization = await Self.currentAuthorization()
    }

    private nonisolated static func currentAuthorization() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    var body: some View {
        List {
            permissionSection

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
                Toggle(isOn: $notifyAnnouncements) {
                    TVRowLabelText(title: "Announcements", detail: "Messages from your server's admin, and a day before planned maintenance. Needs the Arcfin Sync plugin.")
                }
                .syncLocked(BackgroundRefresh.announcementsKey, authManager)
                Toggle(isOn: $notifyIssues) {
                    TVRowLabelText(title: "Issues", detail: "When an issue you reported gets a comment or is resolved, and new issues if you manage them in Seerr. Needs the Arcfin Sync plugin.")
                }
                .syncLocked(BackgroundRefresh.issuesKey, authManager)
                Toggle(isOn: $notifyRequestsToApprove) {
                    TVRowLabelText(title: "Requests to Approve", detail: "If you can approve requests in Seerr: new ones waiting, ones approved automatically, and ones that failed. Needs the Arcfin Sync plugin.")
                }
                .syncLocked(BackgroundRefresh.requestsToApproveKey, authManager)
                Toggle(isOn: $notifyDownload) {
                    TVRowLabelText(title: "Download Complete", detail: "When a download finishes.")
                }
                .syncLocked("notifyDownload", authManager)
                Toggle(isOn: $notifyMusicDownloads) {
                    TVRowLabelText(title: "Music Downloads", detail: "Tells you when songs you're downloading are ready to play offline.")
                }
                .syncLocked(MusicSettings.notifyDownloadsKey, authManager)
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
                        .syncLocked(QuietHours.startKey, authManager)
                    DatePicker("To", selection: time($quietEnd), displayedComponents: .hourAndMinute)
                        .syncLocked(QuietHours.endKey, authManager)
                }
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge("Notifications")
        .task { authorization = await Self.currentAuthorization() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { authorization = await Self.currentAuthorization() } }
        }
        .onChange(of: notifyNewEpisodes) { _, isOn in if isOn { Task { await askForPermission() } } }
        .onChange(of: notifyNewFilms) { _, isOn in if isOn { Task { await askForPermission() } } }
        .onChange(of: notifyServerEvents) { _, isOn in if isOn { Task { await askForPermission() } } }
        .onChange(of: showsStreamBadge) { _, isOn in
            Task {
                if isOn { await askForPermission() }
                await StreamBadge.refresh()
            }
        }
        .onChange(of: notifyRequestUpdates) { _, isOn in if isOn { Task { await askForPermission() } } }
        .onChange(of: notifyWatchlistAvailable) { _, isOn in if isOn { Task { await askForPermission() } } }
        .onChange(of: notifyDownload) { _, isOn in if isOn { Task { await askForPermission() } } }
        .onChange(of: notifyMusicDownloads) { _, isOn in if isOn { Task { await askForPermission() } } }
    }
}

#Preview {
    NavigationStack { NotificationsSettingsView() }
        .environment(AuthManager())
}
