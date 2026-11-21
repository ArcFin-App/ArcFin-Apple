// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import JellyfinAPI

@MainActor @Observable
final class AdminLibrariesModel {
    private(set) var libraries: [JellyfinLibraryFolder] = []
    private(set) var isLoading = true
    private(set) var errorMessage: String?
    var actionError: String?
    var actionDone: String?

    let admin = JellyfinAdminClient()

    func load(authManager: AuthManager) async {
        guard let access = AdminAccess.session(authManager) else { return }
        do {
            libraries = try await admin.libraries(credential: access.credential, authHeader: access.header)
            errorMessage = nil
        } catch {
            errorMessage = String(localized: "Couldn't load the server's libraries.")
        }
        isLoading = false
    }

    /// Runs `work`, then reloads; `failure` is what the alert says if it throws.
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

    static func kindName(_ type: String?) -> String {
        switch type {
        case "movies": String(localized: "Movies")
        case "tvshows": String(localized: "Shows")
        case "music": String(localized: "Music")
        case "musicvideos": String(localized: "Music Videos")
        case "homevideos": String(localized: "Home Videos & Photos")
        case "boxsets": String(localized: "Collections")
        case "books": String(localized: "Books")
        case "playlists": String(localized: "Playlists")
        case "livetv": String(localized: "Live TV")
        default: String(localized: "Mixed Content")
        }
    }

    static let addableKinds: [String?] = ["movies", "tvshows", "music", "musicvideos", "homevideos", "books", nil]
}

/// Libraries: scan one or all, and each library's folders on the server.
struct AdminLibrariesView: View {
    @Environment(AuthManager.self) private var authManager
    @State private var model = AdminLibrariesModel()
    @State private var showAdd = false

    var body: some View {
        List {
            if let error = model.errorMessage {
                Text(error).foregroundStyle(DT.Color.textSecondary)
            }
            Section {
                Button {
                    model.perform(authManager, done: String(localized: "Every library is being scanned. Scheduled Tasks shows its progress."),
                                  failure: String(localized: "The scan didn't start.")) { admin, credential, header in
                        try await admin.scanAllLibraries(credential: credential, authHeader: header)
                    }
                } label: {
                    Label("Scan All Libraries", systemImage: "arrow.triangle.2.circlepath")
                }
            } footer: {
                Text("Looks for new, changed and removed files in every library.")
            }
            Section("Libraries") {
                ForEach(model.libraries) { library in
                    NavigationLink {
                        AdminLibraryDetailView(library: library, model: model)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(library.name).foregroundStyle(DT.Color.textPrimary)
                            Text([AdminLibrariesModel.kindName(library.collectionType),
                                  String(localized: "\(library.locations.count) folders")]
                                .joined(separator: " · "))
                                .font(.system(.caption))
                                .foregroundStyle(DT.Color.textSecondary)
                            if let progress = library.refreshProgress, progress > 0, progress < 100 {
                                ProgressView(value: progress / 100).tint(DT.Color.accent)
                            }
                        }
                    }
                }
            }
        }
        .overlay { if model.isLoading { ProgressView() } }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge("Libraries")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add Library")
            }
        }
        .sheet(isPresented: $showAdd) { AdminAddLibrarySheet(model: model) }
        .task { await model.load(authManager: authManager) }
        .refreshable { await model.load(authManager: authManager) }
        .adminResultAlerts(error: $model.actionError, done: $model.actionDone)
    }
}

/// One library: scan it, refresh its details, its folders, rename or remove it.
private struct AdminLibraryDetailView: View {
    let library: JellyfinLibraryFolder
    let model: AdminLibrariesModel

    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss
    @State private var showFolderPicker = false
    @State private var showRename = false
    @State private var newName = ""
    @State private var confirmRemove = false
    @State private var confirmReplace = false
    @State private var removingFolder: String?

    private var current: JellyfinLibraryFolder { model.libraries.first { $0.id == library.id } ?? library }

    var body: some View {
        List {
            Section {
                Button {
                    model.perform(authManager, done: String(localized: "“\(current.name)” is being scanned."),
                                  failure: String(localized: "The scan didn't start.")) { admin, credential, header in
                        try await admin.scanLibrary(id: current.id, credential: credential, authHeader: header)
                    }
                } label: {
                    Label("Scan for New Files", systemImage: "arrow.triangle.2.circlepath")
                }
                Button { confirmReplace = true } label: {
                    Label("Replace All Metadata", systemImage: "text.badge.checkmark")
                }
            } footer: {
                Text("Replacing metadata fetches every title's details and artwork again, which can take a long time on a large library.")
            }
            Section {
                ForEach(current.locations, id: \.self) { path in
                    Text(path)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(DT.Color.textPrimary)
                        .swipeActions {
                            Button("Remove", role: .destructive) { removingFolder = path }
                        }
                        .contextMenu {
                            Button("Remove Folder", systemImage: "minus.circle", role: .destructive) { removingFolder = path }
                        }
                }
                Button { showFolderPicker = true } label: {
                    Label("Add Folder", systemImage: "folder.badge.plus")
                }
            } header: {
                Text("Folders")
            } footer: {
                Text("Folders on the server's own disk. Removing one takes its titles out of the library; the files stay.")
            }
            Section {
                Button { newName = current.name; showRename = true } label: {
                    Label("Rename Library", systemImage: "pencil")
                }
                Button(role: .destructive) { confirmRemove = true } label: {
                    Label("Remove Library", systemImage: "trash")
                        .foregroundStyle(DT.Color.palette("F43F5E"))
                }
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge(current.name)
        .sheet(isPresented: $showFolderPicker) {
            AdminFolderPicker { path in
                model.perform(authManager, failure: String(localized: "The folder wasn't added.")) { admin, credential, header in
                    try await admin.addLibraryFolder(library: current.name, path: path, credential: credential, authHeader: header)
                }
            }
        }
        .alert("Replace All Metadata?", isPresented: $confirmReplace) {
            Button("Replace", role: .destructive) {
                model.perform(authManager, done: String(localized: "Every title in “\(current.name)” is getting its details again."),
                              failure: String(localized: "The refresh didn't start.")) { admin, credential, header in
                    try await admin.scanLibrary(id: current.id, replaceMetadata: true, credential: credential, authHeader: header)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every detail and image is fetched again, and edits made by hand are lost.")
        }
        .alert("Rename Library", isPresented: $showRename) {
            TextField("Name", text: $newName)
            Button("Rename") {
                let name = newName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty, name != current.name else { return }
                let old = current.name
                model.perform(authManager, failure: String(localized: "The library wasn't renamed.")) { admin, credential, header in
                    try await admin.renameLibrary(old, to: name, credential: credential, authHeader: header)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Remove “\(current.name)”?", isPresented: $confirmRemove) {
            Button("Remove Library", role: .destructive) {
                let name = current.name
                model.perform(authManager, failure: String(localized: "The library wasn't removed.")) { admin, credential, header in
                    try await admin.removeLibrary(name: name, credential: credential, authHeader: header)
                }
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It disappears for everyone, along with watch history for its titles. The files on disk stay.")
        }
        .alert("Remove This Folder?", isPresented: Binding(get: { removingFolder != nil }, set: { if !$0 { removingFolder = nil } }),
               presenting: removingFolder) { path in
            Button("Remove Folder", role: .destructive) {
                let name = current.name
                model.perform(authManager, failure: String(localized: "The folder wasn't removed.")) { admin, credential, header in
                    try await admin.removeLibraryFolder(library: name, path: path, credential: credential, authHeader: header)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { path in
            Text("\(path) leaves “\(current.name)”. Its files stay on disk.")
        }
    }
}

/// A new library: its name, kind and first folder.
private struct AdminAddLibrarySheet: View {
    let model: AdminLibrariesModel

    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kind: String? = "movies"
    @State private var folders: [String] = []
    @State private var showFolderPicker = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    Picker("Kind", selection: $kind) {
                        ForEach(AdminLibrariesModel.addableKinds, id: \.self) { kind in
                            Text(AdminLibrariesModel.kindName(kind)).tag(kind)
                        }
                    }
                }
                Section("Folders") {
                    ForEach(folders, id: \.self) { Text($0).font(.system(.footnote, design: .monospaced)) }
                        .onDelete { folders.remove(atOffsets: $0) }
                    Button { showFolderPicker = true } label: { Label("Add Folder", systemImage: "folder.badge.plus") }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add Library")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let name = name.trimmingCharacters(in: .whitespaces), kind = kind, folders = folders
                        model.perform(authManager, done: String(localized: "“\(name)” was added and is being scanned."),
                                      failure: String(localized: "The library wasn't added.")) { admin, credential, header in
                            try await admin.addLibrary(name: name, collectionType: kind, paths: folders, credential: credential, authHeader: header)
                        }
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || folders.isEmpty)
                }
            }
            .sheet(isPresented: $showFolderPicker) {
                AdminFolderPicker { if !folders.contains($0) { folders.append($0) } }
            }
        }
    }
}

/// Browses the server's own disk for a folder.
struct AdminFolderPicker: View {
    let onPick: (String) -> Void

    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss
    @State private var path = ""
    @State private var entries: [String] = []
    @State private var isLoading = true
    @State private var failed = false

    var body: some View {
        NavigationStack {
            List {
                if !path.isEmpty {
                    Button { open(parent(of: path)) } label: {
                        Label("Up", systemImage: "arrow.turn.left.up")
                    }
                }
                if failed {
                    Text("Couldn't open this folder.").foregroundStyle(DT.Color.textSecondary)
                }
                ForEach(entries, id: \.self) { entry in
                    Button { open(entry) } label: {
                        Label((entry as NSString).lastPathComponent.isEmpty ? entry : (entry as NSString).lastPathComponent,
                              systemImage: "folder")
                            .foregroundStyle(DT.Color.textPrimary)
                    }
                }
            }
            .overlay { if isLoading { ProgressView() } }
            .arcfinListStyle()
            .navigationTitle(path.isEmpty ? String(localized: "Server Folders") : (path as NSString).lastPathComponent)
            .inlineNavigationTitle()
            .safeAreaInset(edge: .bottom) {
                if !path.isEmpty {
                    Button {
                        onPick(path)
                        dismiss()
                    } label: {
                        Text("Use “\(path)”")
                            .font(.system(.subheadline, weight: .semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(DT.Color.accent)
                    .foregroundStyle(DT.Color.onAccent)
                    .controlSize(.large)
                    .padding()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .task { await load() }
        }
    }

    private func parent(of path: String) -> String {
        let parent = (path as NSString).deletingLastPathComponent
        return parent == path ? "" : parent
    }

    private func open(_ newPath: String) {
        path = newPath
        Task { await load() }
    }

    private func load() async {
        guard let access = AdminAccess.session(authManager) else { return }
        isLoading = true
        do {
            entries = try await JellyfinAdminClient().directories(at: path, credential: access.credential, authHeader: access.header)
            failed = false
        } catch {
            entries = []
            failed = true
        }
        isLoading = false
    }
}

extension View {
    /// An admin action's failure, or what it started.
    func adminResultAlerts(error: Binding<String?>, done: Binding<String?>) -> some View {
        self
            .alert("Couldn't Do That", isPresented: Binding(get: { error.wrappedValue != nil }, set: { if !$0 { error.wrappedValue = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(error.wrappedValue ?? "")
            }
            .alert("Done", isPresented: Binding(get: { done.wrappedValue != nil }, set: { if !$0 { done.wrappedValue = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(done.wrappedValue ?? "")
            }
    }
}
