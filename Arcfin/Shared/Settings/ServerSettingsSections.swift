// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import JellyfinAPI
import SyncEngine

/// The server's public info for Server Settings, and the Wi-Fi network this device is on.
@MainActor @Observable
final class ServerSettingsModel {
    private(set) var publicInfo: JellyfinPublicServerInfo?
    private(set) var isLoadingInfo = true
    private(set) var infoError: String?
    private(set) var isCapturingSSID = false
    /// The last "Use Current" couldn't read the network's name.
    private(set) var ssidCaptureFailed = false

    private let client = JellyfinMediaClient()

    func loadInfo(baseURL: URL?) async {
        guard let base = baseURL else { isLoadingInfo = false; return }
        do {
            publicInfo = try await client.getPublicInfo(baseURL: base)
        } catch {
            infoError = String(localized: "Couldn't reach the server for its public info.")
        }
        isLoadingInfo = false
    }

    /// Hands `store` the Wi-Fi network this device is on. When it can't tell, the saved one is
    /// kept and `ssidCaptureFailed` says so.
    func captureCurrentSSID(_ store: @escaping @MainActor (String) -> Void) {
        isCapturingSSID = true
        ssidCaptureFailed = false
        Task {
            if let ssid = await AuthManager.currentWiFiSSID(asksForLocation: true) {
                store(ssid)
            } else {
                ssidCaptureFailed = true
            }
            isCapturingSSID = false
        }
    }

    static func currentlyUsing(activeBaseURL: URL?, localURL: String, remoteURL: String) -> String {
        guard let host = activeBaseURL?.host else { return String(localized: "Unknown") }
        if let localHost = URL(string: localURL)?.host, localHost == host { return String(localized: "Local URL") }
        if let remoteHost = URL(string: remoteURL)?.host, remoteHost == host { return String(localized: "Remote URL") }
        return String(localized: "Custom")
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
                LabeledContent("Setup Completed") { (info.startupWizardCompleted ?? false) ? Text("Yes") : Text("No") }
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
    /// Apple TV has no Admin tab, so Arcfin for Everyone sits here for admins.
    var showsAdminLink = false

    @Environment(AuthManager.self) private var authManager

    /// The admin's locks by name, in the schema's order.
    private var lockedSettings: [SettingsSchema.Setting] {
        SettingsSchema.bundled.settings.filter { authManager.arcfinSyncLockedKeys.contains($0.key) }
    }

    var body: some View {
        Section {
            if authManager.isSyncingArcfin {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .tvReadOnlyRow()
            } else if let status = authManager.arcfinSyncStatus {
                LabeledContent("Status") { Text("Connected") }
                    .tvReadOnlyRow()
                LabeledContent("Version", value: status.version)
                    .tvReadOnlyRow()
                LabeledContent("Locked Settings", value: "\(authManager.arcfinSyncLockedKeys.count)")
                    .tvReadOnlyRow()
                ForEach(lockedSettings) { setting in
                    Label(SettingDisplay.title(setting), systemImage: "lock.fill")
                        .foregroundStyle(DT.Color.textSecondary)
                        .tvReadOnlyRow()
                }
                if let lastSynced = authManager.arcfinSyncLastSyncedAt {
                    LabeledContent("Last Synced") {
                        Text(lastSynced, style: .relative)
                    }
                    .tvReadOnlyRow()
                }
            } else {
                LabeledContent("Status") { Text("Not Installed") }
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

        // Outside the status rows above, which a running sync swaps for a spinner.
        if authManager.hasArcfinSyncDevices {
            Section {
                NavigationLink { DevicesSyncView().tvSettingsPage() } label: {
                    TVRowLabelText(title: "Devices & Sync", detail: "Name this device, choose how it syncs, and see your other devices.")
                }
                if showsAdminLink && authManager.isAdmin {
                    NavigationLink { ArcfinSyncAdminView().tvSettingsPage() } label: {
                        TVRowLabelText(title: "Arcfin for Everyone", detail: "Defaults and locks for every Arcfin app on this server, and everyone's devices.")
                    }
                }
            }
        }
    }
}

/// Server Settings' last sections: Server & Connection, custom headers, and which address is
/// in use.
struct ServerConnectionSections: View {
    let currentlyUsing: String
    var localURL = ""
    var remoteURL = ""

    var body: some View {
        Section {
            NavigationLink {
                ServerConnectionView(localURL: localURL, remoteURL: remoteURL, currentlyUsing: currentlyUsing).tvSettingsPage()
            } label: {
                TVRowLabelText(title: "Server & Connection", detail: "Test your speed to the server, and see what your account and this device can play.")
            }
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

/// A Local or Remote URL: what's typed is checked against the server before it's saved. An
/// address that doesn't answer, or reaches a different server, can be tried again or saved
/// anyway, since a local one only answers on its own network.
struct ServerURLField: View {
    enum Kind { case local, remote }
    enum Check: Equatable {
        case idle, checking
        case reached(String)
        case failed(String)
    }

    let placeholder: String
    let kind: Kind
    @Binding var saved: String
    /// The signed-in server's id, to tell a different server apart.
    let serverID: String?
    @State private var draft = ""
    @State private var check = Check.idle

    var body: some View {
        TextField(placeholder, text: $draft)
            .textContentType(.URL)
            .autocorrectionDisabled()
            .urlFieldKeyboard()
            .onSubmit { Task { await test() } }
            .onAppear { draft = saved }
            .onChange(of: draft) { if check != .checking { check = .idle } }
        if draft.trimmingCharacters(in: .whitespaces) != saved || check != .idle {
            status
        }
    }

    @ViewBuilder
    private var status: some View {
        switch check {
        case .idle:
            Button(draft.trimmingCharacters(in: .whitespaces).isEmpty ? "Clear" : "Test and Save") { Task { await test() } }
                .formRowButton()
        case .checking:
            HStack(spacing: 8) {
                ProgressView()
                Text("Checking…").foregroundStyle(DT.Color.textSecondary)
            }
            .tvReadOnlyRow()
        case .reached(let name):
            Label("Saved. It reaches \(name).", systemImage: "checkmark.circle")
                .foregroundStyle(DT.Color.palette("10B981"))
                .tvReadOnlyRow()
        case .failed(let reason):
            VStack(alignment: .leading, spacing: 8) {
                Label(reason, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(DT.Color.palette("F59E0B"))
                    .font(.callout)
                HStack(spacing: 16) {
                    Button("Try Again") { Task { await test() } }
                    Button("Save Anyway") {
                        saved = draft.trimmingCharacters(in: .whitespaces)
                        check = .idle
                    }
                }
                .buttonStyle(.borderless)
            }
            .tvReadOnlyRow()
        }
    }

    private func test() async {
        let text = draft.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else {
            saved = ""
            check = .idle
            return
        }
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              url.host?.isEmpty == false else {
            check = .failed(String(localized: "That isn't a web address. Start it with http:// or https://."))
            return
        }
        check = .checking
        let info = try? await JellyfinMediaClient().getPublicInfo(baseURL: url)
        guard let info else {
            check = .failed(kind == .local
                ? String(localized: "No answer from this address. A local address only answers on its own network.")
                : String(localized: "No answer from this address. Check it, and that the server is reachable from outside."))
            return
        }
        if let serverID, info.id != serverID {
            check = .failed(String(localized: "This address reaches a different server, \(info.serverName ?? "—")."))
            return
        }
        saved = text
        check = .reached(info.serverName ?? String(localized: "your server"))
    }
}
