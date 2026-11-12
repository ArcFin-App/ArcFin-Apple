// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import JellyfinAPI

@MainActor @Observable
final class AdminPluginsModel {
    private(set) var installed: [JellyfinPlugin] = []
    private(set) var catalogue: [JellyfinPackage] = []
    private(set) var isLoading = true
    private(set) var errorMessage: String?
    var actionError: String?
    var actionDone: String?

    let admin = JellyfinAdminClient()

    /// The newest catalogue version of an installed plugin, when it's newer than what's there.
    func update(for plugin: JellyfinPlugin) -> JellyfinPackage? {
        guard let package = catalogue.first(where: { $0.id.lowercased() == plugin.id.lowercased() }),
              let latest = package.latestVersion,
              latest.compare(plugin.version, options: .numeric) == .orderedDescending else { return nil }
        return package
    }

    var available: [JellyfinPackage] {
        let ids = Set(installed.map { $0.id.lowercased() })
        return catalogue.filter { !ids.contains($0.id.lowercased()) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func load(authManager: AuthManager) async {
        guard let access = AdminAccess.session(authManager) else { return }
        async let installed = admin.plugins(credential: access.credential, authHeader: access.header)
        async let catalogue = admin.catalogue(credential: access.credential, authHeader: access.header)
        do {
            self.installed = try await installed.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            errorMessage = nil
        } catch {
            errorMessage = String(localized: "Couldn't load the server's plugins.")
        }
        self.catalogue = (try? await catalogue) ?? []
        isLoading = false
    }

    func perform(_ authManager: AuthManager, done: String? = nil, failure: String,
                 _ work: @escaping (JellyfinAdminClient, ServerCredential, String) async throws -> Void) {
        guard let access = AdminAccess.session(authManager) else { return }
        Task {
            do {
                try await work(admin, access.credential, access.header)
                HapticManager.impact(.light)
                if let done { actionDone = done }
                await load(authManager: authManager)
            } catch {
                actionError = failure
            }
        }
    }
}

/// Installed plugins (enable, disable, update, uninstall) and the catalogue to install from.
struct AdminPluginsView: View {
    @Environment(AuthManager.self) private var authManager
    @State private var model = AdminPluginsModel()
    @State private var uninstalling: JellyfinPlugin?
    @State private var search = ""

    private static let restartNote = String(localized: "It takes effect when the server restarts, from the Admin tab.")

    var body: some View {
        List {
            if let error = model.errorMessage {
                Text(error).foregroundStyle(DT.Color.textSecondary)
            }
            Section("Installed") {
                ForEach(model.installed) { plugin in
                    installedRow(plugin)
                }
            }
            let matches = model.available.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }
            if !matches.isEmpty {
                Section {
                    ForEach(matches) { package in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(package.name).foregroundStyle(DT.Color.textPrimary)
                                if let overview = package.overview, !overview.isEmpty {
                                    Text(overview)
                                        .font(.system(.caption))
                                        .foregroundStyle(DT.Color.textSecondary)
                                        .lineLimit(2)
                                }
                                Text([package.category, package.latestVersion].compactMap { $0 }.joined(separator: " · "))
                                    .font(.system(.caption2))
                                    .foregroundStyle(DT.Color.textSecondary)
                            }
                            Spacer(minLength: 8)
                            Button("Install") {
                                model.perform(authManager, done: String(localized: "“\(package.name)” is installing. \(Self.restartNote)"),
                                              failure: String(localized: "“\(package.name)” wasn't installed.")) { admin, credential, header in
                                    try await admin.install(package, credential: credential, authHeader: header)
                                }
                            }
                            .buttonStyle(.bordered)
                            .tint(DT.Color.accent)
                            .controlSize(.small)
                        }
                    }
                } header: {
                    Text("Catalogue")
                }
            }
        }
        .searchable(text: $search, prompt: Text("Search the Catalogue"))
        .overlay { if model.isLoading { ProgressView() } }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge("Plugins")
        .task { await model.load(authManager: authManager) }
        .refreshable { await model.load(authManager: authManager) }
        .alert("Uninstall \(uninstalling?.name ?? "")?", isPresented: Binding(get: { uninstalling != nil }, set: { if !$0 { uninstalling = nil } }),
               presenting: uninstalling) { plugin in
            Button("Uninstall", role: .destructive) {
                model.perform(authManager, done: String(localized: "“\(plugin.name)” is uninstalled. \(Self.restartNote)"),
                              failure: String(localized: "“\(plugin.name)” wasn't uninstalled.")) { admin, credential, header in
                    try await admin.uninstall(plugin, credential: credential, authHeader: header)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Its settings go with it.")
        }
        .adminResultAlerts(error: $model.actionError, done: $model.actionDone)
    }

    private func installedRow(_ plugin: JellyfinPlugin) -> some View {
        let update = model.update(for: plugin)
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(plugin.name)
                    .foregroundStyle(plugin.status == "Disabled" ? DT.Color.textSecondary : DT.Color.textPrimary)
                Text([String(localized: "Version \(plugin.version)"), statusText(plugin)].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(.caption))
                    .foregroundStyle(plugin.status == "Malfunctioned" || plugin.status == "NotSupported"
                                     ? DT.Color.palette("F43F5E") : DT.Color.textSecondary)
                if let latest = update?.latestVersion {
                    Text("Version \(latest) available")
                        .font(.system(.caption, weight: .semibold))
                        .foregroundStyle(DT.Color.palette("60A5FA"))
                }
            }
            Spacer(minLength: 8)
            Menu {
                if let update {
                    Button("Update to \(update.latestVersion ?? "")", systemImage: "arrow.down.circle") {
                        model.perform(authManager, done: String(localized: "“\(plugin.name)” is updating. \(Self.restartNote)"),
                                      failure: String(localized: "“\(plugin.name)” wasn't updated.")) { admin, credential, header in
                            try await admin.install(update, credential: credential, authHeader: header)
                        }
                    }
                }
                if plugin.status == "Disabled" {
                    Button("Enable", systemImage: "checkmark.circle") { setEnabled(plugin, true) }
                } else if plugin.status == "Active" {
                    Button("Disable", systemImage: "pause.circle") { setEnabled(plugin, false) }
                }
                if plugin.canUninstall {
                    Button("Uninstall", systemImage: "trash", role: .destructive) { uninstalling = plugin }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(.body))
                    .foregroundStyle(DT.Color.textSecondary)
                    .frame(minWidth: 32, minHeight: 32)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Options for \(plugin.name)")
        }
    }

    private func statusText(_ plugin: JellyfinPlugin) -> String? {
        switch plugin.status {
        case "Disabled": String(localized: "Disabled")
        case "Restart": String(localized: "Restart needed")
        case "NotSupported": String(localized: "Not supported by this server")
        case "Malfunctioned": String(localized: "Failed to load")
        case "Superceded": String(localized: "Replaced by a newer version")
        case "Deleted": String(localized: "Removed when the server restarts")
        default: nil
        }
    }

    private func setEnabled(_ plugin: JellyfinPlugin, _ enabled: Bool) {
        model.perform(authManager, done: enabled ? String(localized: "“\(plugin.name)” is enabled. \(Self.restartNote)")
                                                 : String(localized: "“\(plugin.name)” is disabled. \(Self.restartNote)"),
                      failure: String(localized: "“\(plugin.name)” didn't change.")) { admin, credential, header in
            try await admin.setPlugin(plugin, enabled: enabled, credential: credential, authHeader: header)
        }
    }
}
