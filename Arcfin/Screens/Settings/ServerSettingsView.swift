// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import JellyfinAPI

struct ServerSettingsView: View {
    @Environment(AuthManager.self) private var authManager

    // Scoped to the profile these were configured for — a flat, unscoped key here is what
    // let one server's Local/Remote URL silently get applied to a completely different
    // server after switching profiles or signing into a new one. See AuthManager.resolveBaseURL.
    @AppStorage private var remoteURL: String
    @AppStorage private var localURL: String
    @AppStorage private var homeSSID: String

    @State private var publicInfo: JellyfinPublicServerInfo?
    @State private var isLoadingInfo = true
    @State private var infoError: String?
    @State private var isCapturingSSID = false

    private let client = JellyfinMediaClient()

    init(profileID: UUID) {
        let idKey = profileID.uuidString
        _remoteURL = AppStorage(wrappedValue: "", "serverRemoteURL.\(idKey)")
        _localURL = AppStorage(wrappedValue: "", "serverLocalURL.\(idKey)")
        _homeSSID = AppStorage(wrappedValue: "", "serverHomeSSID.\(idKey)")
    }

    private var activeBaseURL: URL? { authManager.state.credential?.baseURL }

    private var currentlyUsing: String {
        guard let host = activeBaseURL?.host else { return "Unknown" }
        if let localHost = URL(string: localURL)?.host, localHost == host { return "Local URL" }
        if let remoteHost = URL(string: remoteURL)?.host, remoteHost == host { return "Remote URL" }
        return "Custom"
    }

    var body: some View {
        List {
            Section {
                if isLoadingInfo {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if let info = publicInfo {
                    LabeledContent("Server Name", value: info.serverName ?? "—")
                    LabeledContent("Version", value: info.version ?? "—")
                    LabeledContent("Product", value: info.productName ?? "—")
                    LabeledContent("Operating System", value: info.operatingSystem ?? "—")
                    LabeledContent("Local Address", value: info.localAddress ?? "—")
                        .lineLimit(1)
                    LabeledContent("Setup Completed", value: (info.startupWizardCompleted ?? false) ? "Yes" : "No")
                } else if let infoError {
                    Text(infoError)
                        .font(.caption)
                        .foregroundStyle(DT.Color.palette("EF4444"))
                }
            } header: {
                Label("Public Server Info", systemImage: "server.rack")
                    .font(.system(.caption, design: .default, weight: .semibold))
                    .foregroundStyle(DT.Color.textSecondary)
                    .textCase(nil)
            }

            Section {
                if authManager.isSyncingArcfin {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if let status = authManager.arcfinSyncStatus {
                    LabeledContent("Status", value: "Connected")
                    LabeledContent("Version", value: status.version)
                    LabeledContent("Locked Settings", value: "\(authManager.arcfinSyncLockedKeys.count)")
                    if let lastSynced = authManager.arcfinSyncLastSyncedAt {
                        LabeledContent("Last Synced") {
                            Text(lastSynced, style: .relative)
                        }
                    }
                } else {
                    LabeledContent("Status", value: "Not Installed")
                }
                Button {
                    authManager.syncArcfinNow()
                } label: {
                    Text(authManager.isSyncingArcfin ? "Syncing…" : "Sync Now")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
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

            Section {
                TextField("https://your-server.example.com", text: $remoteURL)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
            } header: {
                Label("Remote URL", systemImage: "globe")
                    .font(.system(.caption, design: .default, weight: .semibold))
                    .foregroundStyle(DT.Color.textSecondary)
                    .textCase(nil)
            } footer: {
                Text("Used when you're not on the saved home Wi-Fi network below.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }

            Section {
                TextField("http://10.0.1.50:8096", text: $localURL)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Home Wi-Fi Network")
                            .font(.system(.subheadline, design: .default))
                        Text(homeSSID.isEmpty ? "Not set" : homeSSID)
                            .font(.caption)
                            .foregroundStyle(DT.Color.textSecondary)
                    }
                    Spacer()
                    // currentWiFiSSID() only resolves on iOS (see AuthManager) — no point
                    // offering a capture button elsewhere that can only ever come back nil.
                    #if os(iOS)
                    Button {
                        captureCurrentSSID()
                    } label: {
                        if isCapturingSSID { ProgressView().scaleEffect(0.8) }
                        else { Text("Use Current") }
                    }
                    .disabled(isCapturingSSID)
                    #endif
                }
            } header: {
                Label("Local URL", systemImage: "wifi")
                    .font(.system(.caption, design: .default, weight: .semibold))
                    .foregroundStyle(DT.Color.textSecondary)
                    .textCase(nil)
            } footer: {
                Text("Used automatically when this device is connected to the saved home Wi-Fi network. Requires the Access Wi-Fi Information capability.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }

            Section {
                NavigationLink { CustomHeadersView() } label: {
                    TVRowLabelText(title: "Custom Headers", detail: "Extra headers for a server behind an access gateway, such as Cloudflare Access.")
                }
            }

            Section {
                LabeledContent("Currently Using", value: currentlyUsing)
            } footer: {
                Text("Close and reopen the app for URL or Wi-Fi network changes to take effect.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge("Server Settings")
        .task {
            guard let base = activeBaseURL else { isLoadingInfo = false; return }
            do {
                publicInfo = try await client.getPublicInfo(baseURL: base)
            } catch {
                infoError = "Couldn't reach the server for its public info."
            }
            isLoadingInfo = false
        }
    }

    private func captureCurrentSSID() {
        isCapturingSSID = true
        Task {
            if let ssid = await AuthManager.currentWiFiSSID() {
                homeSSID = ssid
            } else {
                homeSSID = ""
            }
            isCapturingSSID = false
        }
    }
}
