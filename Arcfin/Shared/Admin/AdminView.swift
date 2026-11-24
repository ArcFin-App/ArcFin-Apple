// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import JellyfinAPI

/// The signed-in admin's credential and header, for the admin screens' calls.
@MainActor
enum AdminAccess {
    static func session(_ authManager: AuthManager) -> (credential: ServerCredential, header: String)? {
        guard authManager.isAdmin, case .authenticated(let credential) = authManager.state else { return nil }
        return (credential, authManager.authClient.authHeader(token: credential.accessToken))
    }

    static var unavailableMessage: String {
        String(localized: "This profile isn't an admin, or the server can't be reached.")
    }
}

@MainActor @Observable
final class AdminDashboardModel {
    private(set) var info: JellyfinSystemInfo?
    private(set) var sessions: [JellyfinSession] = []
    private(set) var runningTasks = 0
    private(set) var failedTasks = 0
    private(set) var isLoading = true
    private(set) var errorMessage: String?
    var actionError: String?
    var actionDone: String?

    private let admin = JellyfinAdminClient()
    private let media = JellyfinMediaClient()

    var playing: [JellyfinSession] { sessions.filter { $0.nowPlayingItemName != nil } }
    var converting: Int { playing.filter { $0.playMethod == "Transcode" }.count }

    func load(authManager: AuthManager) async {
        guard let access = AdminAccess.session(authManager) else {
            errorMessage = AdminAccess.unavailableMessage
            isLoading = false
            return
        }
        async let info = admin.systemInfo(credential: access.credential, authHeader: access.header)
        async let sessions = media.getActiveSessions(credential: access.credential, authHeader: access.header)
        async let tasks = admin.scheduledTasks(credential: access.credential, authHeader: access.header)
        do {
            self.info = try await info
            errorMessage = nil
        } catch {
            errorMessage = String(localized: "Couldn't reach the server's dashboard. Check your connection, and that this profile is still an admin.")
        }
        if let sessions = try? await sessions { self.sessions = sessions }
        if let tasks = try? await tasks {
            runningTasks = tasks.filter { $0.state == .running }.count
            failedTasks = tasks.filter { $0.lastResult == "Failed" }.count
        }
        isLoading = false
    }

    func restart(authManager: AuthManager) {
        guard let access = AdminAccess.session(authManager) else { return }
        Task {
            do {
                try await admin.restart(credential: access.credential, authHeader: access.header)
                actionDone = String(localized: "The server is restarting. It'll be back in a minute or so.")
            } catch {
                actionError = String(localized: "The server didn't restart.")
            }
        }
    }

    func shutDown(authManager: AuthManager) {
        guard let access = AdminAccess.session(authManager) else { return }
        Task {
            do {
                try await admin.shutDown(credential: access.credential, authHeader: access.header)
                actionDone = String(localized: "The server is shutting down. Start it again on the machine it runs on.")
            } catch {
                actionError = String(localized: "The server didn't shut down.")
            }
        }
    }
}

/// The Admin tab: the server at a glance, then every admin screen.
struct AdminView: View {
    @Environment(AuthManager.self) private var authManager
    @State private var model = AdminDashboardModel()
    @State private var confirmRestart = false
    @State private var confirmShutDown = false

    var body: some View {
        List {
            Section { header }
            Section {
                NavigationLink { AdminSessionsView() } label: {
                    AdminRow(title: "Active Sessions", systemImage: "play.tv",
                             detail: model.playing.isEmpty ? String(localized: "Nobody's watching") : String(localized: "\(model.playing.count) playing"))
                }
                NavigationLink { AdminTasksView() } label: {
                    AdminRow(title: "Scheduled Tasks", systemImage: "clock.arrow.2.circlepath",
                             detail: model.runningTasks > 0 ? String(localized: "\(model.runningTasks) running") : nil,
                             warning: model.failedTasks > 0 ? String(localized: "\(model.failedTasks) failed") : nil)
                }
                NavigationLink { AdminActivityView() } label: {
                    AdminRow(title: "Activity", systemImage: "list.bullet.rectangle", detail: nil)
                }
            } header: {
                Text("Server")
            }
            Section {
                NavigationLink { AdminLibrariesView() } label: {
                    AdminRow(title: "Libraries", systemImage: "books.vertical", detail: nil)
                }
                NavigationLink { AdminUsersView() } label: {
                    AdminRow(title: "Users", systemImage: "person.2", detail: nil)
                }
                NavigationLink { AdminDevicesView() } label: {
                    AdminRow(title: "Devices", systemImage: "laptopcomputer.and.iphone", detail: nil)
                }
            } header: {
                Text("Manage")
            }
            Section {
                NavigationLink { AdminPluginsView() } label: {
                    AdminRow(title: "Plugins", systemImage: "puzzlepiece.extension", detail: nil)
                }
                if authManager.hasArcfinSyncDevices {
                    NavigationLink { ArcfinSyncAdminView() } label: {
                        AdminRow(title: "Arcfin for Everyone", systemImage: "slider.horizontal.3", detail: nil)
                    }
                }
                NavigationLink { AdminAPIKeysView() } label: {
                    AdminRow(title: "API Keys", systemImage: "key", detail: nil)
                }
                NavigationLink { AdminLogsView() } label: {
                    AdminRow(title: "Logs", systemImage: "doc.text.magnifyingglass", detail: nil)
                }
                NavigationLink { AdminBackupsView() } label: {
                    AdminRow(title: "Backups", systemImage: "externaldrive", detail: nil)
                }
            } header: {
                Text("System")
            }
            Section {
                NavigationLink { AdminGeneralSettingsView() } label: {
                    AdminRow(title: "General", systemImage: "gearshape", detail: nil)
                }
                NavigationLink { AdminEncodingSettingsView() } label: {
                    AdminRow(title: "Playback & Transcoding", systemImage: "film.stack", detail: nil)
                }
                NavigationLink { AdminNetworkSettingsView() } label: {
                    AdminRow(title: "Networking", systemImage: "network", detail: nil)
                }
            } header: {
                Text("Server Settings")
            }
            Section {
                Button { HapticManager.warning(); confirmRestart = true } label: {
                    Label("Restart Server", systemImage: "arrow.clockwise")
                }
                Button(role: .destructive) { HapticManager.warning(); confirmShutDown = true } label: {
                    Label("Shut Down Server", systemImage: "power")
                        .foregroundStyle(DT.Color.palette("F43F5E"))
                }
            } footer: {
                Text("Everyone watching is stopped. A shut-down server has to be started again on the machine it runs on.")
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge("Admin")
        .task { await model.load(authManager: authManager) }
        .refreshable { await model.load(authManager: authManager) }
        .alert("Restart the Server?", isPresented: $confirmRestart) {
            Button("Restart", role: .destructive) { model.restart(authManager: authManager) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(model.playing.isEmpty ? String(localized: "It'll be back in a minute or so.")
                 : String(localized: "\(model.playing.count) people are watching. Their playback stops while it restarts."))
        }
        .alert("Shut Down the Server?", isPresented: $confirmShutDown) {
            Button("Shut Down", role: .destructive) { model.shutDown(authManager: authManager) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Arcfin can't start it again. You'll need to start it on the machine it runs on.")
        }
        .alert("Couldn't Do That", isPresented: Binding(get: { model.actionError != nil }, set: { if !$0 { model.actionError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.actionError ?? "")
        }
        .alert("Done", isPresented: Binding(get: { model.actionDone != nil }, set: { if !$0 { model.actionDone = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.actionDone ?? "")
        }
    }

    @ViewBuilder
    private var header: some View {
        if let info = model.info {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(info.serverName)
                        .font(.system(.title2, weight: .bold))
                        .foregroundStyle(DT.Color.textPrimary)
                    Text([String(localized: "Jellyfin \(info.version)"), info.operatingSystem].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(.subheadline))
                        .foregroundStyle(DT.Color.textSecondary)
                }
                if info.hasUpdateAvailable || info.hasPendingRestart {
                    HStack(spacing: 8) {
                        if info.hasUpdateAvailable { AdminPill(text: "Update Available", color: DT.Color.palette("60A5FA")) }
                        if info.hasPendingRestart { AdminPill(text: "Restart Needed", color: DT.Color.palette("f59e0b")) }
                    }
                }
                HStack(spacing: 12) {
                    AdminStat(value: model.playing.count, label: "Playing", systemImage: "play.fill", color: DT.Color.accent)
                    AdminStat(value: model.converting, label: "Converting", systemImage: "gearshape.2.fill", color: DT.Color.palette("f59e0b"))
                    AdminStat(value: model.runningTasks, label: "Tasks Running", systemImage: "clock.fill", color: DT.Color.palette("60A5FA"))
                }
            }
            .padding(.vertical, 6)
        } else if let error = model.errorMessage {
            Label(error, systemImage: "exclamationmark.triangle")
                .font(.system(.footnote))
                .foregroundStyle(DT.Color.textSecondary)
        } else {
            ProgressView().frame(maxWidth: .infinity)
        }
    }
}

/// A row leading to an admin screen, with what's happening there.
struct AdminRow: View {
    let title: LocalizedStringKey
    let systemImage: String
    let detail: String?
    var warning: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(.body))
                .foregroundStyle(DT.Color.accent)
                .frame(width: 26)
            Text(title).foregroundStyle(DT.Color.textPrimary)
            Spacer(minLength: 8)
            if let warning {
                Text(warning)
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(DT.Color.palette("F43F5E"))
            }
            if let detail {
                Text(detail)
                    .font(.system(.caption))
                    .foregroundStyle(DT.Color.textSecondary)
            }
        }
    }
}

struct AdminPill: View {
    let text: LocalizedStringKey
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(.caption, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.15)))
    }
}

private struct AdminStat: View {
    let value: Int
    let label: LocalizedStringKey
    let systemImage: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(.caption))
                .foregroundStyle(color)
            Text(value, format: .number)
                .font(.system(.title2, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(DT.Color.textPrimary)
                .contentTransition(.numericText())
            Text(label)
                .font(.system(.caption2))
                .foregroundStyle(DT.Color.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: DT.Radius.md, style: .continuous).fill(color.opacity(0.1)))
        .accessibilityElement(children: .combine)
    }
}
