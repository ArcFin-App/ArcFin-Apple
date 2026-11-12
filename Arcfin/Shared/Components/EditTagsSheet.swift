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
    @State private var serverTags: [String] = []

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
                    Button("Save") { save() }
                        .disabled(isLoading || isSaving)
                }
            }
            .alert("Couldn't Save Tags", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(error ?? "")
            }
        }
        .task { await load() }
    }

    private var form: some View {
        List {
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
                if tags.isEmpty {
                    Text("No tags yet.")
                        .foregroundStyle(DT.Color.textSecondary)
                }
                ForEach(tags, id: \.self) { tag in
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
                .onDelete { tags.remove(atOffsets: $0) }
            } header: {
                Text(item.name)
            } footer: {
                Text("Tags are saved on the server, for everyone who uses it.")
            }
            if !suggestions.isEmpty {
                Section {
                    TagFlowLayout(spacing: 8) {
                        ForEach(suggestions, id: \.self) { tag in
                            Button { add(tag) } label: {
                                Label(tag, systemImage: "plus")
                                    .font(.system(.footnote, weight: .medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(Self.isHomeTag(tag) ? DT.Color.accent.opacity(0.18) : DT.Color.textPrimary.opacity(0.08)))
                                    .foregroundStyle(Self.isHomeTag(tag) ? DT.Color.accent : DT.Color.textPrimary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Add \(tag)")
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Suggested")
                } footer: {
                    Text(item.type == .boxSet
                         ? "arcfin-featured puts this collection's titles in Home's hero; arcfin-promoted gives it its own row on Home. The rest are tags already used on this server."
                         : "arcfin-featured puts this title in Home's hero. The rest are tags already used on this server.")
                }
            }
        }
        .arcfinListStyle()
    }

    /// The Home tags that apply here, then the server's own tags, leaving out any it has.
    private var suggestions: [String] {
        let home = item.type == .boxSet ? [Self.featuredTag, Self.promotedTag] : [Self.featuredTag]
        let all = home + serverTags.filter { !Self.isHomeTag($0) }.prefix(30)
        return all.filter { tag in !tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame } }
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
        let client = JellyfinMediaClient()
        async let current = client.getTags(credential: credential, authHeader: header, itemId: item.id)
        async let used = client.getLibraryFilterOptions(credential: credential, authHeader: header, libraryId: "")
        tags = (try? await current) ?? []
        isLoading = false
        serverTags = (try? await used)?.tags ?? []
    }

    private func save() {
        guard let credential = authManager.state.credential else { return }
        add(newTag)
        let header = authManager.authClient.authHeader(token: credential.accessToken)
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await JellyfinMediaClient().setTags(credential: credential, authHeader: header, itemId: item.id, tags: tags)
                HapticManager.impact(.light)
                dismiss()
                // A Home tag changes what Home shows.
                if item.type == .boxSet {
                    await mediaRepo.load(credential: credential, authClient: authManager.authClient, force: true)
                }
            } catch {
                self.error = String(localized: "The server didn't take the change. Check your connection and that you're still an admin, then try again.")
            }
        }
    }
}

/// Suggested tags, wrapping onto as many lines as they need.
private struct TagFlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, width: proposal.width ?? .infinity)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func rows(for subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
