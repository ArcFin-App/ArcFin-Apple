// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI
import AuthCore

/// The title whose tags are being edited. Shared like PlaylistStore: Edit Tags sits in
/// long-press menus all over the app, and the sheet is hosted once at the tab root.
@Observable
@MainActor
final class TagEditor {
    static let shared = TagEditor()
    var item: MediaItem?
}

/// The title whose details are being edited, for the metadata editor at the tab root.
@Observable
@MainActor
final class MetadataEditor {
    static let shared = MetadataEditor()
    var item: MediaItem?
}

/// Edit Metadata…, for admins on iPhone, iPad and Mac.
struct EditMetadataButton: View {
    let item: MediaItem

    var body: some View {
        if AdminPlatform.isAvailable, ProfileRules.shared.canEditMetadata,
           [.movie, .series, .season, .episode, .boxSet].contains(item.type) {
            Button { MetadataEditor.shared.item = item } label: {
                Label("Edit Metadata…", systemImage: "square.and.pencil")
            }
        }
    }
}

/// Edit Tags…, for admins, in a title's menus.
struct EditTagsButton: View {
    let item: MediaItem

    var body: some View {
        if ProfileRules.shared.canEditMetadata, item.type != .tvChannel, item.type != .unknown {
            Button { TagEditor.shared.item = item } label: {
                Label("Edit Tags…", systemImage: "tag")
            }
        }
    }
}

/// An item's tags: add or remove them, and for a collection the two that put it on Home.
struct EditTagsSheet: View {
    let item: MediaItem

    @Environment(AuthManager.self) private var authManager
    @Environment(MediaRepository.self) private var mediaRepo
    @Environment(\.dismiss) private var dismiss
    @State private var tags: [String] = []
    @State private var newTag = ""
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var error: String?
    @State private var version: ServerVersion?
    @State private var confirmUntested = false
    private var compatibility: ServerCompatibility.Status { ServerCompatibility.status(version) }

    static let featuredTag = "arcfin-featured"
    static let promotedTag = "arcfin-promoted"

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    form
                }
            }
            .navigationTitle("Tags")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if compatibility.needsConfirmation { confirmUntested = true } else { save() }
                    }
                    .disabled(isLoading || isSaving || !compatibility.canSave)
                }
            }
            .alert("Couldn't Save Tags", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(error ?? "")
            }
        }
        .task { await load() }
        .untestedServerConfirmation(isPresented: $confirmUntested, status: compatibility) { save() }
    }

    private var form: some View {
        List {
            AdminCompatibilityNote(status: compatibility)
            if canFeature {
                Section {
                    Toggle(isOn: binding(for: Self.featuredTag)) {
                        TVRowLabelText(title: "Feature on Home", detail: item.type == .boxSet
                                       ? "Its titles fill Home's hero for everyone on this server."
                                       : "Puts it in Home's hero for everyone on this server.")
                    }
                    if item.type == .boxSet {
                        Toggle(isOn: binding(for: Self.promotedTag)) {
                            TVRowLabelText(title: "Own Row on Home", detail: "Shows as a row named after the collection, under Server Picks.")
                        }
                    }
                } header: {
                    Text("Home")
                }
            }
            Section {
                HStack {
                    TextField("Add Tag", text: $newTag)
                        .autocorrectionDisabled()
                        .onSubmit { add(newTag) }
                    Button { add(newTag) } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(DT.Color.accent)
                    }
                    .buttonStyle(.plain)
                    .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityLabel("Add Tag")
                }
                if otherTags.isEmpty {
                    Text("No tags yet.")
                        .foregroundStyle(DT.Color.textSecondary)
                }
                ForEach(otherTags, id: \.self) { tag in
                    HStack {
                        Text(tag).foregroundStyle(DT.Color.textPrimary)
                        Spacer()
                        Button(role: .destructive) { tags.removeAll { $0 == tag } } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(DT.Color.palette("F43F5E"))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(tag)")
                    }
                }
                .onDelete { offsets in
                    let removed = offsets.map { otherTags[$0] }
                    tags.removeAll { removed.contains($0) }
                }
            } header: {
                Text(item.name)
            } footer: {
                Text("Tags are saved on the server, for everyone who uses it.")
            }
        }
        .arcfinListStyle()
    }

    /// Movies, shows and collections can be featured; only a collection gets its own row.
    private var canFeature: Bool { [.movie, .series, .boxSet].contains(item.type) }

    /// The tags listed below the switches: the Home ones are the switches themselves.
    private var otherTags: [String] { canFeature ? tags.filter { !Self.isHomeTag($0) } : tags }

    private func binding(for tag: String) -> Binding<Bool> {
        Binding(
            get: { tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame } },
            set: { on in
                tags.removeAll { $0.caseInsensitiveCompare(tag) == .orderedSame }
                if on { tags.append(tag) }
            }
        )
    }

    private static func isHomeTag(_ tag: String) -> Bool {
        tag.caseInsensitiveCompare(featuredTag) == .orderedSame || tag.caseInsensitiveCompare(promotedTag) == .orderedSame
    }

    private func add(_ raw: String) {
        let tag = raw.trimmingCharacters(in: .whitespaces)
        guard !tag.isEmpty else { return }
        if !tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
            withAnimation(DT.Animation.fast) { tags.insert(tag, at: 0) }
        }
        if raw == newTag { newTag = "" }
    }

    private func load() async {
        guard let credential = authManager.state.credential else { return }
        let header = authManager.authClient.authHeader(token: credential.accessToken)
        version = await ServerVersions.version(for: credential)
        tags = (try? await JellyfinMediaClient().getTags(credential: credential, authHeader: header, itemId: item.id)) ?? []
        isLoading = false
    }

    private func save() {
        guard compatibility.canSave, let credential = authManager.state.credential else { return }
        add(newTag)
        let header = authManager.authClient.authHeader(token: credential.accessToken)
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                let client = JellyfinMediaClient(), sent = tags
                try await client.setTags(credential: credential, authHeader: header, itemId: item.id, tags: sent)
                // What the server kept, read back, so a tag it refused isn't reported as saved.
                if let kept = try? await client.getTags(credential: credential, authHeader: header, itemId: item.id),
                   Set(kept.map { $0.lowercased() }) != Set(sent.map { $0.lowercased() }) {
                    tags = kept
                    self.error = String(localized: "The server didn't keep every tag as sent. The list now shows what it has.")
                    return
                }
                HapticManager.impact(.light)
                dismiss()
                // A Home tag changes what Home shows.
                if canFeature {
                    await mediaRepo.load(credential: credential, authClient: authManager.authClient, force: true)
                }
            } catch {
                self.error = String(localized: "The server didn't take the change. Check your connection and that you're still an admin, then try again.")
            }
        }
    }
}
