// SPDX-License-Identifier: AGPL-3.0-or-later

#if os(macOS)
import SwiftUI
import AuthCore

/// Arcfin › Settings… (⌘,): the same panes as the iPhone's Settings, in their own window with
/// a sidebar, as Mac apps keep their settings.
struct MacSettingsWindow: View {
    private enum Pane: String, CaseIterable, Identifiable {
        case general, playback, downloads, appearance, notifications, server, integrations

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: "General"
            case .playback: "Playback"
            case .downloads: "Downloads"
            case .appearance: "Appearance"
            case .notifications: "Notifications"
            case .server: "Server"
            case .integrations: "Integrations"
            }
        }

        var icon: String {
            switch self {
            case .general: "person.crop.circle"
            case .playback: "play.circle"
            case .downloads: "arrow.down.circle"
            case .appearance: "paintbrush"
            case .notifications: "bell"
            case .server: "person.badge.key"
            case .integrations: "puzzlepiece.extension"
            }
        }
    }

    @State private var pane: Pane? = .general

    var body: some View {
        Group {
            // The main window holds the PIN lock; settings stay closed until it's passed.
            if AppServices.hasPassedLock, AppServices.authManager.state.credential != nil {
                NavigationSplitView {
                    List(Pane.allCases, selection: $pane) { pane in
                        Label(pane.title, systemImage: pane.icon).tag(pane)
                    }
                    .navigationSplitViewColumnWidth(190)
                } detail: {
                    NavigationStack {
                        detail(for: pane ?? .general)
                    }
                    .id(pane)
                }
            } else {
                ContentUnavailableView("Settings Are Locked", systemImage: "lock",
                                       description: Text("Sign in or unlock Arcfin in its main window first."))
            }
        }
        .frame(minWidth: 780, idealWidth: 860, minHeight: 540, idealHeight: 640)
        .environment(AppServices.authManager)
        .environment(AppServices.mediaRepo)
        .environment(AppServices.seerrRepo)
        .environment(AppServices.downloadManager)
        .environment(AppServices.syncPlayManager)
        .environment(AppServices.sharePlayManager)
    }

    @ViewBuilder
    private func detail(for pane: Pane) -> some View {
        switch pane {
        case .general: SettingsView()
        case .playback: PlaybackSettingsView()
        case .downloads: DownloadsSettingsView()
        case .appearance: AppearanceView()
        case .notifications: NotificationsSettingsView()
        case .server: ServerAccountSettingsView()
        case .integrations: IntegrationsSettingsView()
        }
    }
}
#endif
