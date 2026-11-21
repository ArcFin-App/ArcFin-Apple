// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import JellyfinAPI

/// A title's details as the server holds them, edited and posted back whole, plus refresh,
/// identify and artwork. Admins only; saved on the server for everyone.
struct AdminMetadataEditor: View {
    let item: MediaItem

    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss
    @State private var values: [String: Any] = [:]
    @State private var original: [String: Any] = [:]
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var message: String?
    @State private var confirmReplace = false
    @State private var version: ServerVersion?
    @State private var confirmUntested = false

    private var hasChanges: Bool { !ServerEditGuard.changedKeys(from: original, to: values).isEmpty }
    private var compatibility: ServerCompatibility.Status { ServerCompatibility.status(version) }

    var body: some View {
        NavigationStack {
            List {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    AdminCompatibilityNote(status: compatibility)
                    details
                        .disabled(!compatibility.canSave)
                    Section {
                        Button { refresh(replace: false) } label: {
                            Label("Refresh Metadata", systemImage: "arrow.clockwise")
                        }
                        Button(role: .destructive) { confirmReplace = true } label: {
                            Label("Replace All Metadata", systemImage: "arrow.triangle.2.circlepath")
                        }
                        if identifyKind != nil {
                            NavigationLink {
                                AdminIdentifyView(item: item, kind: identifyKind ?? "Movie",
                                                  name: values["Name"] as? String ?? item.name,
                                                  year: (values["ProductionYear"] as? NSNumber)?.intValue,
                                                  onApplied: { dismiss() })
                            } label: {
                                Label("Identify…", systemImage: "magnifyingglass")
                            }
                        }
                        NavigationLink {
                            AdminImagePicker(item: item)
                        } label: {
                            Label("Artwork…", systemImage: "photo.on.rectangle")
                        }
                    } footer: {
                        Text("Refresh fills in what's missing from the metadata providers. Replace fetches everything again, overwriting edits. Identify picks the right match when a title was matched wrongly.")
                    }
                }
            }
            .arcfinListStyle()
            .navigationTitle(item.name)
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if compatibility.needsConfirmation { confirmUntested = true } else { save() }
                    }
                    .disabled(!hasChanges || isSaving || !compatibility.canSave)
                }
            }
            .task { await load() }
            .untestedServerConfirmation(isPresented: $confirmUntested, status: compatibility) { save() }
            .alert("Replace All Metadata?", isPresented: $confirmReplace) {
                Button("Replace", role: .destructive) { refresh(replace: true) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Every detail and image is fetched again, and edits made by hand are lost.")
            }
            .alert("Metadata", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(message ?? "")
            }
        }
    }

    /// What Identify searches as: the providers only know movies, shows and collections.
    private var identifyKind: String? {
        switch item.type {
        case .movie: "Movie"
        case .series: "Series"
        case .boxSet: "BoxSet"
        default: nil
        }
    }

    @ViewBuilder
    private var details: some View {
        Section("Details") {
            field("Title", key: "Name")
            if item.type == .movie || item.type == .series {
                field("Original Title", key: "OriginalTitle")
            }
            field("Sort Title", key: "ForcedSortName")
            HStack {
                Text("Year")
                Spacer()
                TextField("Year", value: number("ProductionYear"), format: .number.grouping(.never))
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 90)
            }
            field("Age Rating", key: "OfficialRating")
            HStack {
                Text("Community Rating")
                Spacer()
                TextField("0–10", value: decimal("CommunityRating"), format: .number.precision(.fractionLength(0...1)))
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 90)
            }
        }
        Section("Overview") {
            TextEditor(text: text("Overview"))
                .frame(minHeight: 120)
        }
        Section {
            TextField("Genres", text: list("Genres"), axis: .vertical)
            if item.type == .movie || item.type == .series {
                TextField("Taglines", text: list("Taglines"), axis: .vertical)
            }
        } header: {
            Text("Genres")
        } footer: {
            Text("Separate several with commas.")
        }
        Section {
            Toggle("Lock Details", isOn: Binding(
                get: { values["LockData"] as? Bool ?? false },
                set: { values["LockData"] = $0 }))
        } footer: {
            Text("A locked title keeps these details when the library is refreshed.")
        }
    }

    private func field(_ title: LocalizedStringKey, key: String) -> some View {
        TextField(title, text: text(key))
    }

    private func text(_ key: String) -> Binding<String> {
        Binding(get: { values[key] as? String ?? "" }, set: { values[key] = $0 })
    }

    private func number(_ key: String) -> Binding<Int?> {
        Binding(get: { (values[key] as? NSNumber)?.intValue }, set: { values[key] = $0.map { $0 as Any } ?? NSNull() })
    }

    private func decimal(_ key: String) -> Binding<Double?> {
        Binding(get: { (values[key] as? NSNumber)?.doubleValue }, set: { values[key] = $0.map { $0 as Any } ?? NSNull() })
    }

    private func list(_ key: String) -> Binding<String> {
        Binding(
            get: { (values[key] as? [String] ?? []).joined(separator: ", ") },
            set: { values[key] = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
        )
    }

    private func load() async {
        guard let access = AdminAccess.session(authManager) else {
            message = AdminAccess.unavailableMessage
            isLoading = false
            return
        }
        version = await ServerVersions.version(for: access.credential)
        if let data = try? await JellyfinAdminClient().item(id: item.id, credential: access.credential, authHeader: access.header),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            values = object
            original = object
        } else {
            message = String(localized: "Couldn't load this title's details.")
        }
        isLoading = false
    }

    private func save() {
        guard compatibility.canSave else { return }
        let mismatched = ServerEditGuard.mismatches(from: original, to: values)
        guard mismatched.isEmpty else {
            message = String(localized: "Nothing was saved: \(ServerEditGuard.describe(mismatched)) didn't match what the server expects.")
            return
        }
        guard let access = AdminAccess.session(authManager),
              let data = try? JSONSerialization.data(withJSONObject: values) else { return }
        let changed = ServerEditGuard.changedKeys(from: original, to: values), sent = values
        isSaving = true
        Task {
            defer { isSaving = false }
            let client = JellyfinAdminClient()
            do {
                try await client.updateItem(id: item.id, data, credential: access.credential, authHeader: access.header)
            } catch {
                message = String(localized: "The server didn't take the change.")
                return
            }
            // What the server kept, read back, so a detail it dropped isn't reported as saved.
            if let reread = try? await client.item(id: item.id, credential: access.credential, authHeader: access.header),
               let object = try? JSONSerialization.jsonObject(with: reread) as? [String: Any] {
                let lost = ServerEditGuard.notKept(changed, sent: sent, reread: object)
                guard lost.isEmpty else {
                    values = object
                    original = object
                    message = String(localized: "The server didn't keep \(ServerEditGuard.describe(lost)) as sent. The editor now shows what it has.")
                    return
                }
            }
            HapticManager.impact(.light)
            dismiss()
        }
    }

    private func refresh(replace: Bool) {
        guard let access = AdminAccess.session(authManager) else { return }
        Task {
            do {
                try await JellyfinAdminClient().refreshItem(id: item.id, replace: replace, credential: access.credential, authHeader: access.header)
                message = String(localized: "The server is fetching this title's details. They'll show in a moment.")
            } catch {
                message = String(localized: "The refresh didn't start.")
            }
        }
    }
}

/// Searches the metadata providers by name and year, and applies the chosen match.
private struct AdminIdentifyView: View {
    let item: MediaItem
    let kind: String
    let onApplied: () -> Void

    @Environment(AuthManager.self) private var authManager
    @State private var name: String
    @State private var year: Int?
    @State private var matches: [JellyfinRemoteMatch] = []
    @State private var isSearching = false
    @State private var applying: JellyfinRemoteMatch?
    @State private var message: String?

    init(item: MediaItem, kind: String, name: String, year: Int?, onApplied: @escaping () -> Void) {
        self.item = item
        self.kind = kind
        self.onApplied = onApplied
        _name = State(initialValue: name)
        _year = State(initialValue: year)
    }

    var body: some View {
        List {
            Section {
                TextField("Title", text: $name)
                    .onSubmit(search)
                TextField("Year", value: $year, format: .number.grouping(.never))
                Button(action: search) {
                    if isSearching { ProgressView() } else { Label("Search", systemImage: "magnifyingglass") }
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSearching)
            }
            if !matches.isEmpty {
                Section("Matches") {
                    ForEach(matches) { match in
                        Button { applying = match } label: {
                            HStack(alignment: .top, spacing: 12) {
                                CachedAsyncImage(url: match.imageURL) { phase in
                                    switch phase {
                                    case .success(let image): image.resizable().scaledToFill()
                                    default: DT.Color.backgroundTertiary
                                    }
                                }
                                .frame(width: 46, height: 69)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(match.name).foregroundStyle(DT.Color.textPrimary)
                                    Text([match.year.map(String.init), match.provider].compactMap { $0 }.joined(separator: " · "))
                                        .font(.system(.caption))
                                        .foregroundStyle(DT.Color.textSecondary)
                                    if let overview = match.overview {
                                        Text(overview)
                                            .font(.system(.caption))
                                            .foregroundStyle(DT.Color.textSecondary)
                                            .lineLimit(3)
                                    }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .arcfinListStyle()
        .navigationTitle("Identify")
        .inlineNavigationTitle()
        .task { if matches.isEmpty { search() } }
        .alert("Use This Match?", isPresented: Binding(get: { applying != nil }, set: { if !$0 { applying = nil } }),
               presenting: applying) { match in
            Button("Use Match") { apply(match) }
            Button("Cancel", role: .cancel) {}
        } message: { match in
            Text("“\(item.name)” becomes \(match.name), with its details and artwork.")
        }
        .alert("Identify", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    private func search() {
        guard let access = AdminAccess.session(authManager) else { return }
        isSearching = true
        let name = name.trimmingCharacters(in: .whitespaces), year = year
        Task {
            defer { isSearching = false }
            matches = (try? await JellyfinAdminClient().identify(itemId: item.id, kind: kind, name: name, year: year,
                                                                 credential: access.credential, authHeader: access.header)) ?? []
            if matches.isEmpty { message = String(localized: "No matches. Try the title in another language, or without the year.") }
        }
    }

    private func apply(_ match: JellyfinRemoteMatch) {
        guard let access = AdminAccess.session(authManager) else { return }
        Task {
            do {
                try await JellyfinAdminClient().apply(match, to: item.id, replaceImages: true,
                                                      credential: access.credential, authHeader: access.header)
                HapticManager.impact(.medium)
                onApplied()
            } catch {
                message = String(localized: "The match wasn't applied.")
            }
        }
    }
}

/// Artwork the metadata providers offer, by kind; tapping one makes it the title's.
private struct AdminImagePicker: View {
    let item: MediaItem

    @Environment(AuthManager.self) private var authManager
    @State private var type = "Primary"
    @State private var images: [JellyfinRemoteImage] = []
    @State private var isLoading = true
    @State private var choosing: JellyfinRemoteImage?
    @State private var message: String?

    private static let types: [(value: String, label: LocalizedStringKey)] = [
        ("Primary", "Poster"), ("Backdrop", "Backdrop"), ("Logo", "Logo"), ("Thumb", "Thumbnail"),
    ]

    private var isWide: Bool { type == "Backdrop" || type == "Thumb" || type == "Logo" }

    var body: some View {
        ScrollView {
            Picker("Kind", selection: $type) {
                ForEach(Self.types, id: \.value) { Text($0.label).tag($0.value) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, DT.Spacing.pagePad)
            if !isLoading && images.isEmpty {
                Text("The providers have no artwork of this kind.")
                    .foregroundStyle(DT.Color.textSecondary)
                    .padding(.top, 40)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: isWide ? 220 : 110), spacing: 12)], spacing: 12) {
                ForEach(images) { image in
                    Button { choosing = image } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            CachedAsyncImage(url: image.url) { phase in
                                switch phase {
                                case .success(let picture): picture.resizable().scaledToFit()
                                default: DT.Color.backgroundTertiary
                                }
                            }
                            .aspectRatio(isWide ? 16 / 9 : 2 / 3, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            Text([image.provider, image.language?.uppercased(),
                                  image.width.flatMap { w in image.height.map { "\(w)×\($0)" } }]
                                .compactMap { $0 }.joined(separator: " · "))
                                .font(.system(.caption2))
                                .foregroundStyle(DT.Color.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(DT.Spacing.pagePad)
        }
        .overlay { if isLoading { ProgressView() } }
        .screenBackground()
        .navigationTitle("Artwork")
        .inlineNavigationTitle()
        .task(id: type) { await load() }
        .alert("Use This Artwork?", isPresented: Binding(get: { choosing != nil }, set: { if !$0 { choosing = nil } }),
               presenting: choosing) { image in
            Button("Use Artwork") { choose(image) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("It replaces the current one for everyone on this server.")
        }
        .alert("Artwork", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    private func load() async {
        guard let access = AdminAccess.session(authManager) else {
            message = AdminAccess.unavailableMessage
            isLoading = false
            return
        }
        isLoading = true
        images = (try? await JellyfinAdminClient().remoteImages(itemId: item.id, type: type,
                                                                credential: access.credential, authHeader: access.header)) ?? []
        isLoading = false
    }

    private func choose(_ image: JellyfinRemoteImage) {
        guard let access = AdminAccess.session(authManager) else { return }
        let type = type
        Task {
            do {
                try await JellyfinAdminClient().setImage(itemId: item.id, type: type, from: image.url,
                                                         credential: access.credential, authHeader: access.header)
                HapticManager.impact(.light)
                message = String(localized: "Done. Arcfin shows the new artwork once its image cache refreshes.")
            } catch {
                message = String(localized: "The artwork wasn't changed.")
            }
        }
    }
}
