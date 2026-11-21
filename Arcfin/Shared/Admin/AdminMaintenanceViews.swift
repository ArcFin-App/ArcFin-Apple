// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import JellyfinAPI
import UniformTypeIdentifiers

/// API keys: create one for an app, copy it, revoke it.
struct AdminAPIKeysView: View {
    @Environment(AuthManager.self) private var authManager
    @State private var keys: [JellyfinAPIKey] = []
    @State private var isLoading = true
    @State private var showCreate = false
    @State private var appName = ""
    @State private var revoking: JellyfinAPIKey?
    @State private var error: String?

    var body: some View {
        List {
            if !isLoading && keys.isEmpty {
                Text("No API keys yet.").foregroundStyle(DT.Color.textSecondary)
            }
            ForEach(keys) { key in
                VStack(alignment: .leading, spacing: 4) {
                    Text(key.appName.isEmpty ? String(localized: "Unnamed") : key.appName)
                        .foregroundStyle(DT.Color.textPrimary)
                    Text(key.token)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(DT.Color.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    if let created = key.created {
                        Text("Created \(created.formatted(date: .abbreviated, time: .omitted))")
                            .font(.system(.caption2))
                            .foregroundStyle(DT.Color.textSecondary)
                    }
                }
                .contextMenu {
                    if ExternalApps.canCopy {
                        Button("Copy Key", systemImage: "doc.on.doc") { ExternalApps.copy(key.token) }
                    }
                    Button("Revoke", systemImage: "trash", role: .destructive) { revoking = key }
                }
                .swipeActions {
                    Button("Revoke", role: .destructive) { revoking = key }
                }
            }
        }
        .overlay { if isLoading { ProgressView() } }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge("API Keys")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showCreate = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("New API Key")
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .alert("New API Key", isPresented: $showCreate) {
            TextField("App Name", text: $appName)
            Button("Create") { create() }
            Button("Cancel", role: .cancel) { appName = "" }
        } message: {
            Text("A key has the full access of an admin. Give one only to apps you trust.")
        }
        .alert("Revoke This Key?", isPresented: Binding(get: { revoking != nil }, set: { if !$0 { revoking = nil } }),
               presenting: revoking) { key in
            Button("Revoke", role: .destructive) { revoke(key) }
            Button("Cancel", role: .cancel) {}
        } message: { key in
            Text("\(key.appName.isEmpty ? String(localized: "The app") : key.appName) can't use the server with it any more.")
        }
        .alert("Couldn't Do That", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
    }

    private func load() async {
        guard let access = AdminAccess.session(authManager) else { return }
        if let fetched = try? await JellyfinAdminClient().apiKeys(credential: access.credential, authHeader: access.header) {
            keys = fetched.sorted { ($0.created ?? .distantPast) > ($1.created ?? .distantPast) }
        } else {
            error = String(localized: "Couldn't load the server's API keys.")
        }
        isLoading = false
    }

    private func create() {
        let name = appName.trimmingCharacters(in: .whitespaces)
        appName = ""
        guard !name.isEmpty, let access = AdminAccess.session(authManager) else { return }
        Task {
            do {
                try await JellyfinAdminClient().createAPIKey(appName: name, credential: access.credential, authHeader: access.header)
                await load()
            } catch {
                self.error = String(localized: "The key wasn't created.")
            }
        }
    }

    private func revoke(_ key: JellyfinAPIKey) {
        guard let access = AdminAccess.session(authManager) else { return }
        Task {
            do {
                try await JellyfinAdminClient().revokeAPIKey(key.token, credential: access.credential, authHeader: access.header)
                keys.removeAll { $0.id == key.id }
            } catch {
                self.error = String(localized: "The key wasn't revoked.")
            }
        }
    }
}

/// The server's log files, newest first.
struct AdminLogsView: View {
    @Environment(AuthManager.self) private var authManager
    @State private var files: [JellyfinLogFile] = []
    @State private var isLoading = true
    @State private var failed = false

    var body: some View {
        List {
            if failed { Text("Couldn't load the server's logs.").foregroundStyle(DT.Color.textSecondary) }
            ForEach(files) { file in
                NavigationLink { AdminLogView(file: file) } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(file.name)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(DT.Color.textPrimary)
                        Text([ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file),
                              file.modified.map { $0.formatted(.relative(presentation: .named)) }]
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(.system(.caption2))
                            .foregroundStyle(DT.Color.textSecondary)
                    }
                }
            }
        }
        .overlay { if isLoading { ProgressView() } }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge("Logs")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        guard let access = AdminAccess.session(authManager) else { return }
        if let fetched = try? await JellyfinAdminClient().logFiles(credential: access.credential, authHeader: access.header) {
            files = fetched
            failed = false
        } else {
            failed = true
        }
        isLoading = false
    }
}

/// One log file: the newest lines first, searchable, and shareable as a file.
private struct AdminLogView: View {
    let file: JellyfinLogFile

    @Environment(AuthManager.self) private var authManager
    /// Newest first, numbered in that order so a row keeps its identity while filtering.
    @State private var lines: [(id: Int, text: String)] = []
    @State private var text = ""
    @State private var isLoading = true
    @State private var search = ""
    @State private var query = ""
    @State private var errorsOnly = false
    @State private var shown: [(id: Int, text: String)] = []

    var body: some View {
        List {
            Toggle("Warnings and Errors Only", isOn: $errorsOnly)
            ForEach(shown, id: \.id) { entry in
                let line = entry.text
                Text(line)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(line.contains("[ERR]") || line.contains("[FTL]") ? DT.Color.palette("F43F5E")
                                     : line.contains("[WRN]") ? DT.Color.palette("f59e0b") : DT.Color.textPrimary)
                    .textSelection(.enabled)
            }
        }
        .searchable(text: $search, prompt: Text("Search This Log"))
        .overlay { if isLoading { ProgressView() } }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge(file.name)
        .toolbar {
            if !text.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: LogFileTransfer(name: file.name, text: text),
                              preview: SharePreview(file.name)) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share Log")
                }
            }
        }
        .task { await load() }
        .task(id: search) {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            query = search
        }
        .onChange(of: query) { filter() }
        .onChange(of: errorsOnly) { filter() }
    }

    private func load() async {
        guard let access = AdminAccess.session(authManager) else { return }
        text = (try? await JellyfinAdminClient().logFile(named: file.name, credential: access.credential, authHeader: access.header)) ?? ""
        lines = text.split(separator: "\n", omittingEmptySubsequences: true).reversed().enumerated().map { (id: $0.offset, text: String($0.element)) }
        filter()
        isLoading = false
    }

    private func filter() {
        shown = Array(lines.lazy.filter { entry in
            (query.isEmpty || entry.text.localizedCaseInsensitiveContains(query))
                && (!errorsOnly || entry.text.contains("[ERR]") || entry.text.contains("[WRN]") || entry.text.contains("[FTL]"))
        }.prefix(2000))
    }
}

/// A log shared as a text file with its own name.
private struct LogFileTransfer: Transferable {
    let name: String
    let text: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { log in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(log.name)
            try log.text.write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
    }
}

/// Backups (Jellyfin 10.11 and later): what's there, and make a new one.
struct AdminBackupsView: View {
    @Environment(AuthManager.self) private var authManager
    @State private var backups: [JellyfinBackup] = []
    @State private var isLoading = true
    @State private var unsupported = false
    @State private var loadFailed = false
    @State private var isCreating = false
    @State private var includeMetadata = false
    @State private var includeTrickplay = false
    @State private var includeSubtitles = true
    @State private var message: String?

    var body: some View {
        List {
            if unsupported {
                Text("Backups need Jellyfin 10.11 or later.").foregroundStyle(DT.Color.textSecondary)
            } else {
                Section {
                    Toggle("Metadata and Artwork", isOn: $includeMetadata)
                    Toggle("Trickplay Previews", isOn: $includeTrickplay)
                    Toggle("Subtitles", isOn: $includeSubtitles)
                    Button {
                        create()
                    } label: {
                        if isCreating {
                            ProgressView()
                        } else {
                            Label("Back Up Now", systemImage: "externaldrive.badge.plus")
                        }
                    }
                    .disabled(isCreating)
                } header: {
                    Text("New Backup")
                } footer: {
                    Text("The database and settings are always included. Backups are saved on the server, in its backup folder.")
                }
                Section("Backups") {
                    if loadFailed {
                        Text("Couldn't load the server's backups.").foregroundStyle(DT.Color.textSecondary)
                    } else if !isLoading && backups.isEmpty {
                        Text("No backups yet.").foregroundStyle(DT.Color.textSecondary)
                    }
                    ForEach(backups) { backup in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(backup.created.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? (backup.path as NSString).lastPathComponent)
                                .foregroundStyle(DT.Color.textPrimary)
                            Text([backup.serverVersion.map { String(localized: "Jellyfin \($0)") }, (backup.path as NSString).lastPathComponent]
                                .compactMap { $0 }.joined(separator: " · "))
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(DT.Color.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
            }
        }
        .overlay { if isLoading { ProgressView() } }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge("Backups")
        .task { await load() }
        .refreshable { await load() }
        .alert("Backups", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    private func load() async {
        guard let access = AdminAccess.session(authManager) else { return }
        do {
            backups = try await JellyfinAdminClient().backups(credential: access.credential, authHeader: access.header)
            unsupported = false
            loadFailed = false
        } catch {
            // Only an older server has no backups; anything else is a failure to say so.
            let version = await ServerVersions.version(for: access.credential)
            unsupported = version.map { $0 < ServerVersion(10, 11) } ?? false
            loadFailed = !unsupported
        }
        isLoading = false
    }

    private func create() {
        guard let access = AdminAccess.session(authManager) else { return }
        isCreating = true
        let metadata = includeMetadata, trickplay = includeTrickplay, subtitles = includeSubtitles
        Task {
            defer { isCreating = false }
            do {
                try await JellyfinAdminClient().createBackup(metadata: metadata, trickplay: trickplay, subtitles: subtitles,
                                                             credential: access.credential, authHeader: access.header)
                message = String(localized: "The backup is done.")
                await load()
            } catch {
                message = String(localized: "The backup wasn't made.")
            }
        }
    }
}
