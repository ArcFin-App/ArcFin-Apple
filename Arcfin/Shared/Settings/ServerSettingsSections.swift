// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import JellyfinAPI

/// The server's public info for Server Settings, and the Wi-Fi network this device is on.
@MainActor @Observable
final class ServerSettingsModel {
    private(set) var publicInfo: JellyfinPublicServerInfo?
    private(set) var isLoadingInfo = true
    private(set) var infoError: String?
    private(set) var isCapturingSSID = false

    private let client = JellyfinMediaClient()

    func loadInfo(baseURL: URL?) async {
        guard let base = baseURL else { isLoadingInfo = false; return }
        do {
            publicInfo = try await client.getPublicInfo(baseURL: base)
        } catch {
            infoError = "Couldn't reach the server for its public info."
        }
        isLoadingInfo = false
    }

    /// Hands `store` the Wi-Fi network this device is on, or "" when it can't tell.
    func captureCurrentSSID(_ store: @escaping @MainActor (String) -> Void) {
        isCapturingSSID = true
        Task {
            if let ssid = await AuthManager.currentWiFiSSID() {
                store(ssid)
            } else {
                store("")
            }
            isCapturingSSID = false
        }
    }

    static func currentlyUsing(activeBaseURL: URL?, localURL: String, remoteURL: String) -> String {
        guard let host = activeBaseURL?.host else { return "Unknown" }
        if let localHost = URL(string: localURL)?.host, localHost == host { return "Local URL" }
        if let remoteHost = URL(string: remoteURL)?.host, remoteHost == host { return "Remote URL" }
        return "Custom"
    }
}

/// Server Settings › Public Server Info.
struct ServerPublicInfoSection: View {
    let model: ServerSettingsModel

    var body: some View {
        Section {
            if model.isLoadingInfo {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .tvReadOnlyRow()
            } else if let info = model.publicInfo {
                LabeledContent("Server Name", value: info.serverName ?? "—")
                    .tvReadOnlyRow()
                LabeledContent("Version", value: info.version ?? "—")
                    .tvReadOnlyRow()
                LabeledContent("Product", value: info.productName ?? "—")
                    .tvReadOnlyRow()
                LabeledContent("Operating System", value: info.operatingSystem ?? "—")
                    .tvReadOnlyRow()
                LabeledContent("Local Address", value: info.localAddress ?? "—")
                    .lineLimit(1)
                    .tvReadOnlyRow()
                LabeledContent("Setup Completed", value: (info.startupWizardCompleted ?? false) ? "Yes" : "No")
                    .tvReadOnlyRow()
            } else if let infoError = model.infoError {
                Text(infoError)
                    .font(.caption)
                    .foregroundStyle(DT.Color.palette("F43F5E"))
                    .tvReadOnlyRow()
            }
        } header: {
            Label("Public Server Info", systemImage: "server.rack")
                .font(.system(.caption, design: .default, weight: .semibold))
                .foregroundStyle(DT.Color.textSecondary)
                .textCase(nil)
        }
    }
}

/// Server Settings › Arcfin Sync.
struct ArcfinSyncSection: View {
    @Environment(AuthManager.self) private var authManager

    var body: some View {
        Section {
            if authManager.isSyncingArcfin {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .tvReadOnlyRow()
            } else if let status = authManager.arcfinSyncStatus {
                LabeledContent("Status", value: "Connected")
                    .tvReadOnlyRow()
                LabeledContent("Version", value: status.version)
                    .tvReadOnlyRow()
                LabeledContent("Locked Settings", value: "\(authManager.arcfinSyncLockedKeys.count)")
                    .tvReadOnlyRow()
                if let lastSynced = authManager.arcfinSyncLastSyncedAt {
                    LabeledContent("Last Synced") {
                        Text(lastSynced, style: .relative)
                    }
                    .tvReadOnlyRow()
                }
            } else {
                LabeledContent("Status", value: "Not Installed")
                    .tvReadOnlyRow()
            }
            Button {
                authManager.syncArcfinNow()
            } label: {
                Text(authManager.isSyncingArcfin ? "Syncing…" : "Sync Now")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .formRowButton()
            .disabled(authManager.isSyncingArcfin)
        } header: {
            Label("Arcfin Sync", systemImage: "arrow.triangle.2.circlepath")
                .font(.system(.caption, design: .default, weight: .semibold))
                .foregroundStyle(DT.Color.textSecondary)
                .textCase(nil)
        } footer: {
            Text("Syncs supported app settings with the Arcfin Sync Jellyfin plugin, when your server has it installed. Locked settings are controlled by your admin and can't be changed here.")
                .font(.caption)
                .foregroundStyle(DT.Color.textSecondary)
        }
    }
}

/// Server Settings' last two sections: custom headers, and which address is in use.
struct ServerConnectionSections: View {
    let currentlyUsing: String

    var body: some View {
        Section {
            NavigationLink { CustomHeadersView().tvSettingsPage() } label: {
                TVRowLabelText(title: "Custom Headers", detail: "Extra headers for a server behind an access gateway, such as Cloudflare Access.")
            }
        }

        Section {
            LabeledContent("Currently Using", value: currentlyUsing)
                .tvReadOnlyRow()
        } footer: {
            Text("Close and reopen the app for URL or Wi-Fi network changes to take effect.")
                .font(.caption)
                .foregroundStyle(DT.Color.textSecondary)
        }
    }
}
