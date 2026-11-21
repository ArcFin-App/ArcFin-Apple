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

    @State private var model = ServerSettingsModel()

    init(profileID: UUID) {
        let idKey = profileID.uuidString
        _remoteURL = AppStorage(wrappedValue: "", "serverRemoteURL.\(idKey)")
        _localURL = AppStorage(wrappedValue: "", "serverLocalURL.\(idKey)")
        _homeSSID = AppStorage(wrappedValue: "", "serverHomeSSID.\(idKey)")
    }

    private var activeBaseURL: URL? { authManager.state.credential?.baseURL }

    var body: some View {
        List {
            ServerPublicInfoSection(model: model)

            ArcfinSyncSection()

            Section {
                ServerURLField(placeholder: "https://your-server.example.com", kind: .remote, saved: $remoteURL,
                               serverID: model.publicInfo?.id)
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
                ServerURLField(placeholder: "http://10.0.1.50:8096", kind: .local, saved: $localURL,
                               serverID: model.publicInfo?.id)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Home Wi-Fi Network")
                            .font(.system(.subheadline, design: .default))
                        Text(homeSSID.isEmpty ? String(localized: "Not set") : homeSSID)
                            .font(.caption)
                            .foregroundStyle(DT.Color.textSecondary)
                    }
                    Spacer()
                    if !homeSSID.isEmpty {
                        Button("Clear") { homeSSID = "" }
                            .buttonStyle(.borderless)
                            .disabled(model.isCapturingSSID)
                    }
                    Button {
                        model.captureCurrentSSID { homeSSID = $0 }
                    } label: {
                        if model.isCapturingSSID { ProgressView().scaleEffect(0.8) }
                        else { Text("Use Current") }
                    }
                    .buttonStyle(.borderless)
                    .disabled(model.isCapturingSSID)
                }
                if model.ssidCaptureFailed {
                    Label("Couldn't read the Wi-Fi network. Allow Location for Arcfin and try again.",
                          systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(DT.Color.palette("F59E0B"))
                }
            } header: {
                Label("Local URL", systemImage: "wifi")
                    .font(.system(.caption, design: .default, weight: .semibold))
                    .foregroundStyle(DT.Color.textSecondary)
                    .textCase(nil)
            } footer: {
                Text("Used automatically when this device is on the saved home Wi-Fi network. Arcfin needs Location access to read the network's name.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }

            ServerConnectionSections(currentlyUsing: ServerSettingsModel.currentlyUsing(
                activeBaseURL: activeBaseURL, localURL: localURL, remoteURL: remoteURL),
                                     localURL: localURL, remoteURL: remoteURL)
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge("Server Settings")
        .task { await model.loadInfo(baseURL: activeBaseURL) }
    }
}
