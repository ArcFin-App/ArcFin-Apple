// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import JellyfinAPI

// MARK: - Playlists grid

/// Every playlist as a grid, with a card to start a new one: what the Browse tab's
/// Playlists tile opens.
struct PlaylistsGridView: View {
    var title = "Playlists"

    @Environment(AuthManager.self) private var authManager
    @Environment(MediaRepository.self) private var mediaRepo

    private var store: PlaylistStore { .shared }
    @State private var showNewPlaylist = false
    @State private var newPlaylistName = ""
    @State private var createdPlaylist: MediaPlaylist?
    private let columns = [GridItem(.adaptive(minimum: PlaylistCard.size), spacing: 16)]

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                Button { showNewPlaylist = true } label: { newPlaylistCard }
                    .buttonStyle(PressableButtonStyle())
                ForEach(store.playlists) { playlist in
                    NavigationLink {
                        PlaylistDetailView(playlist: playlist)
                    } label: {
                        PlaylistCard(playlist: playlist, imageURL: playlistImageURL(playlist, mediaRepo: mediaRepo))
                    }
                    .buttonStyle(PressableButtonStyle())
                }
            }
            .padding(DT.Spacing.pagePad)
        }
        .screenBackground()
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showNewPlaylist = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("New Playlist")
            }
        }
        .alert("New Playlist", isPresented: $showNewPlaylist) {
            TextField("Name", text: $newPlaylistName)
            Button("Cancel", role: .cancel) { newPlaylistName = "" }
            Button("Create") { create() }
        }
        .navigationDestination(item: $createdPlaylist) { PlaylistDetailView(playlist: $0, startsAddingTitles: true) }
        .task { await reload() }
    }

    private var newPlaylistCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "plus")
                .font(.system(.title2, weight: .light))
                .foregroundStyle(DT.Color.accent)
                .frame(width: PlaylistCard.size, height: PlaylistCard.size)
                .background(
                    RoundedRectangle(cornerRadius: DT.Radius.card)
                        .strokeBorder(DT.Color.accent.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                )
            Text("New Playlist")
                .font(.system(.caption, weight: .semibold))
                .foregroundStyle(DT.Color.textPrimary)
        }
    }

    private func reload() async {
        guard let cred = authManager.state.credential else { return }
        await store.load(credential: cred, authHeader: authManager.authClient.authHeader(token: cred.accessToken))
    }

    /// Creates it empty, then opens it straight into picking titles.
    private func create() {
        let name = newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
        newPlaylistName = ""
        guard !name.isEmpty, let cred = authManager.state.credential else { return }
        let header = authManager.authClient.authHeader(token: cred.accessToken)
        Task {
            guard let id = try? await JellyfinMediaClient().createPlaylist(credential: cred, authHeader: header, name: name, itemIds: []) else { return }
            await store.load(credential: cred, authHeader: header)
            createdPlaylist = store.playlists.first { $0.id == id } ?? MediaPlaylist(id: id, name: name, itemCount: 0)
        }
    }
}

@MainActor
private func playlistImageURL(_ playlist: MediaPlaylist, mediaRepo: MediaRepository) -> URL? {
    guard let tag = playlist.primaryImageTag, let base = mediaRepo.baseURL, let token = mediaRepo.accessToken else { return nil }
    return JellyfinMediaClient.imageURL(baseURL: base, itemID: playlist.id, tag: tag, type: .primary, fillWidth: 320, token: token)
}

private struct PlaylistCard: View {
    static let size: CGFloat = 132
    let playlist: MediaPlaylist
    let imageURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if let imageURL {
                    CachedAsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .success(let image): image.resizable().scaledToFill()
                        default: placeholder
                        }
                    }
                } else {
                    placeholder
                }
            }
            .frame(width: Self.size, height: Self.size)
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.card))
            .overlay(RoundedRectangle(cornerRadius: DT.Radius.card).stroke(.white.opacity(0.06), lineWidth: 1))

            Text(playlist.name)
                .font(.system(.caption, weight: .semibold))
                .foregroundStyle(DT.Color.textPrimary)
                .lineLimit(1)
                .frame(width: Self.size, alignment: .leading)
            Text(playlist.itemCount == 1 ? "1 title" : "\(playlist.itemCount) titles")
                .font(.system(.caption2))
                .foregroundStyle(DT.Color.textSecondary)
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [DT.Color.accentDeep.opacity(0.5), DT.Color.backgroundTertiary],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "list.and.film")
                .font(.system(.title, weight: .light))
                .foregroundStyle(.white.opacity(0.8))
        }
    }
}

// MARK: - Playlist page

struct PlaylistDetailView: View {
    let playlist: MediaPlaylist

    @Environment(AuthManager.self) private var authManager
    @Environment(MediaRepository.self) private var mediaRepo
    @Environment(PlaybackPresenter.self) private var playbackPresenter
    @Environment(\.dismiss) private var dismiss

    @State private var entries: [PlaylistEntry] = []
    @State private var isLoading = true
    @State private var name: String
    @State private var playbackRequest: MediaDetailView.PlaybackRequest?
    @State private var showRename = false
    @State private var renameText = ""
    @State private var confirmDelete = false
    @State private var errorMessage: String?
    @State private var showAddTitles = false

    private let client = JellyfinMediaClient()

    /// `startsAddingTitles` opens the title picker straight away, for a playlist just created.
    init(playlist: MediaPlaylist, startsAddingTitles: Bool = false) {
        self.playlist = playlist
        _name = State(initialValue: playlist.name)
        _showAddTitles = State(initialValue: startsAddingTitles)
    }

    private var credential: ServerCredential? { authManager.state.credential }
    private var authHeader: String? { credential.map { authManager.authClient.authHeader(token: $0.accessToken) } }

    var body: some View {
        List {
            Section {
                header
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            if isLoading && entries.isEmpty {
                ProgressView()
                    .tint(DT.Color.accent)
                    .frame(maxWidth: .infinity, minHeight: 160)
                    .listRowBackground(Color.clear)
            } else if entries.isEmpty {
                VStack(spacing: 12) {
                    ContentUnavailableView(
                        "Empty Playlist",
                        systemImage: "list.and.film",
                        description: Text("Add movies, shows and episodes, or long-press any title and choose Add to Playlist."))
                    Button { showAddTitles = true } label: {
                        Label("Add Titles", systemImage: "plus")
                            .font(.system(.subheadline, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DT.Color.accent)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(entries) { entry in
                        Button { play(from: entry) } label: { row(entry.item) }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.clear)
                    }
                    #if os(iOS)
                    .onDelete(perform: remove)
                    .onMove(perform: move)
                    #endif
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle(name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .topBarTrailing) {
                if !entries.isEmpty { EditButton() }
            }
            #endif
            ToolbarItem(placement: .primaryAction) {
                Button { showAddTitles = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add Titles")
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { renameText = name; showRename = true } label: { Label("Rename", systemImage: "pencil") }
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Delete Playlist", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("Playlist options")
            }
        }
        .alert("Rename Playlist", isPresented: $showRename) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Save") { rename() }
        }
        .confirmationDialog("Delete \(name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Playlist", role: .destructive) { deletePlaylist() }
        } message: {
            Text("The titles stay in your library.")
        }
        .alert("Playlist", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(isPresented: $showAddTitles) {
            AddTitlesToPlaylistSheet(playlistId: playlist.id, existingIds: Set(entries.map(\.item.id))) {
                Task { await load() }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        #if os(macOS)
        .onChange(of: playbackRequest) { _, request in
            guard let request else { return }
            playbackPresenter.present(request.item, startTicks: request.startTicks)
            playbackRequest = nil
        }
        .onChange(of: playbackPresenter.request == nil) { _, closed in
            if closed { PlayQueue.clear(); Task { await load() } }
        }
        #else
        .fullScreenCover(item: $playbackRequest, onDismiss: {
            PlayQueue.clear()
            Task { await load() }
        }) { request in
            PlayerView(item: request.item, startPositionTicks: request.startTicks) { next in
                PlayerView.keepOrientationOnNextDisappear = true
                playbackRequest = MediaDetailView.PlaybackRequest(item: next, startTicks: 0)
            }
            .id(request.item.id)
        }
        #endif
    }

    private var header: some View {
        VStack(spacing: 14) {
            Text(entries.count == 1 ? "1 title" : "\(entries.count) titles")
                .font(.system(.footnote))
                .foregroundStyle(DT.Color.textSecondary)
            HStack(spacing: 12) {
                headerButton("Play", systemImage: "play.fill", prominent: true) {
                    if let first = entries.first { play(from: first) }
                }
                headerButton("Shuffle", systemImage: "shuffle", prominent: false) { shuffle() }
            }
            .disabled(entries.isEmpty)
        }
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.vertical, DT.Spacing.md)
    }

    private func headerButton(_ title: String, systemImage: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(.subheadline, weight: .semibold))
                .foregroundStyle(prominent ? Color.black : DT.Color.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(prominent ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.white.opacity(0.1)),
                            in: RoundedRectangle(cornerRadius: DT.Radius.md))
        }
        .buttonStyle(PressableButtonStyle())
    }

    private func row(_ item: MediaItem) -> some View {
        HStack(spacing: 12) {
            CachedAsyncImage(url: thumbnailURL(for: item)) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                default: DT.Color.backgroundSecondary
                }
            }
            .frame(width: 112, height: 63)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .bottom) {
                if let pct = item.userData?.playedPercentage, pct > 0, pct < 100 {
                    GeometryReader { geo in
                        Capsule().fill(DT.Color.accent)
                            .frame(width: geo.size.width * pct / 100, height: 3)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                    .padding(4)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.type == .episode ? (item.seriesName ?? item.name) : item.name)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(DT.Color.textPrimary)
                    .lineLimit(1)
                Text(subtitle(for: item))
                    .font(.system(.caption))
                    .foregroundStyle(DT.Color.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if item.userData?.played == true {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(DT.Color.accent)
                    .accessibilityLabel("Watched")
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func subtitle(for item: MediaItem) -> String {
        if item.type == .episode {
            let code = [item.parentIndexNumber.map { "S\($0)" }, item.indexNumber.map { "E\($0)" }].compactMap { $0 }.joined(separator: " · ")
            return [code, item.name].filter { !$0.isEmpty }.joined(separator: " · ")
        }
        return item.productionYear.map(String.init) ?? ""
    }

    private func thumbnailURL(for item: MediaItem) -> URL? {
        item.type == .episode
            ? mediaRepo.episodeThumbnailURL(for: item, fillWidth: 240)
            : mediaRepo.imageURL(for: item, type: .thumb, fillWidth: 240)
    }

    // MARK: - Actions

    private func load() async {
        guard let credential, let authHeader else { return }
        if let fetched = try? await client.getPlaylistEntries(credential: credential, authHeader: authHeader, playlistId: playlist.id) {
            entries = fetched
        }
        isLoading = false
    }

    private func play(from entry: PlaylistEntry) {
        guard let index = entries.firstIndex(of: entry) else { return }
        PlayQueue.start(entries[index...].map(\.item))
        startPlayback(entry.item)
    }

    private func shuffle() {
        let shuffled = entries.map(\.item).shuffled()
        guard let first = shuffled.first else { return }
        PlayQueue.start(shuffled)
        startPlayback(first)
    }

    private func startPlayback(_ item: MediaItem) {
        let resume = item.userData?.played == true ? 0 : (item.userData?.playbackPositionTicks ?? 0)
        playbackRequest = MediaDetailView.PlaybackRequest(item: item, startTicks: resume)
    }

    #if os(iOS)
    private func remove(at offsets: IndexSet) {
        guard let credential, let authHeader else { return }
        let removed = offsets.map { entries[$0].entryId }
        entries.remove(atOffsets: offsets)
        Task {
            do {
                try await client.removeFromPlaylist(credential: credential, authHeader: authHeader, playlistId: playlist.id, entryIds: removed)
            } catch {
                errorMessage = error.localizedDescription
                await load()
            }
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        guard let credential, let authHeader, let from = source.first else { return }
        let entryId = entries[from].entryId
        entries.move(fromOffsets: source, toOffset: destination)
        let newIndex = entries.firstIndex { $0.entryId == entryId } ?? 0
        Task {
            do {
                try await client.movePlaylistEntry(credential: credential, authHeader: authHeader, playlistId: playlist.id, entryId: entryId, toIndex: newIndex)
            } catch {
                errorMessage = error.localizedDescription
                await load()
            }
        }
    }
    #endif

    private func rename() {
        let newName = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, newName != name, let credential, let authHeader else { return }
        let oldName = name
        name = newName
        Task {
            do {
                try await client.renamePlaylist(credential: credential, authHeader: authHeader, playlistId: playlist.id, name: newName)
                await PlaylistStore.shared.load(credential: credential, authHeader: authHeader)
            } catch {
                name = oldName
                errorMessage = error.localizedDescription
            }
        }
    }

    private func deletePlaylist() {
        guard let credential, let authHeader else { return }
        Task {
            do {
                try await client.deletePlaylist(credential: credential, authHeader: authHeader, playlistId: playlist.id)
                await PlaylistStore.shared.load(credential: credential, authHeader: authHeader)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Add to Playlist

struct AddToPlaylistSheet: View {
    let item: MediaItem

    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    private var store: PlaylistStore { .shared }
    @State private var newName = ""
    @State private var busy = false
    @State private var errorMessage: String?

    private var credential: ServerCredential? { authManager.state.credential }
    private var authHeader: String? { credential.map { authManager.authClient.authHeader(token: $0.accessToken) } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("New playlist", text: $newName)
                            .submitLabel(.done)
                            .onSubmit(createWithItem)
                        Button("Create", action: createWithItem)
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty || busy)
                    }
                }
                if !store.playlists.isEmpty {
                    Section("Your Playlists") {
                        ForEach(store.playlists) { playlist in
                            Button { add(to: playlist) } label: {
                                HStack {
                                    Label(playlist.name, systemImage: "list.and.film")
                                        .foregroundStyle(DT.Color.textPrimary)
                                    Spacer()
                                    Text("\(playlist.itemCount)")
                                        .foregroundStyle(DT.Color.textSecondary)
                                }
                            }
                            .disabled(busy)
                        }
                    }
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Add to Playlist")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .task {
                guard let credential, let authHeader else { return }
                await store.load(credential: credential, authHeader: authHeader)
            }
        }
    }

    private func add(to playlist: MediaPlaylist) {
        guard let credential, let authHeader else { return }
        busy = true
        Task {
            do {
                try await store.add(item, to: playlist, credential: credential, authHeader: authHeader)
                HapticManager.impact(.light)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            busy = false
        }
    }

    private func createWithItem() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let credential, let authHeader else { return }
        busy = true
        Task {
            do {
                try await store.create(named: name, with: [item], credential: credential, authHeader: authHeader)
                HapticManager.impact(.light)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            busy = false
        }
    }
}

// MARK: - Add titles from inside a playlist

/// Pick any number of movies, shows and episodes to add at once: suggestions from Home
/// while the search field is empty, search results once something is typed.
struct AddTitlesToPlaylistSheet: View {
    let playlistId: String
    let existingIds: Set<String>
    let onAdded: () -> Void

    @Environment(AuthManager.self) private var authManager
    @Environment(MediaRepository.self) private var mediaRepo
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [MediaItem] = []
    /// In the order they were picked, which is the order they're added in.
    @State private var selectedIDs: [String] = []
    @State private var isSearching = false
    @State private var isAdding = false
    @State private var errorMessage: String?

    private let client = JellyfinMediaClient()

    private var suggestions: [MediaItem] {
        var seen = Set<String>()
        return (mediaRepo.continueWatching + mediaRepo.recentlyAddedMovies + mediaRepo.recentlyAddedShows + mediaRepo.favorites)
            .filter { [.movie, .series, .episode].contains($0.type) && seen.insert($0.id).inserted }
    }

    private var shown: [MediaItem] { query.isEmpty ? suggestions : results }

    var body: some View {
        NavigationStack {
            List {
                if isSearching && results.isEmpty {
                    HStack { Spacer(); ProgressView(); Spacer() }.listRowBackground(Color.clear)
                } else if !query.isEmpty && results.isEmpty {
                    ContentUnavailableView.search(text: query).listRowBackground(Color.clear)
                } else {
                    Section(query.isEmpty ? "Suggestions" : "Results") {
                        ForEach(shown) { item in
                            Button { toggle(item) } label: { row(item) }
                                .disabled(existingIds.contains(item.id))
                        }
                    }
                }
                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
            .scrollContentBackground(.hidden)
            .screenBackground()
            .searchable(text: $query, prompt: "Movies, shows, episodes")
            .navigationTitle("Add Titles")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(selectedIDs.isEmpty ? "Add" : "Add \(selectedIDs.count)") { add() }
                        .disabled(selectedIDs.isEmpty || isAdding)
                }
            }
            .task(id: query) { await search() }
        }
    }

    private func row(_ item: MediaItem) -> some View {
        let isIn = existingIds.contains(item.id)
        let isSelected = selectedIDs.contains(item.id)
        return HStack(spacing: 12) {
            CachedAsyncImage(url: mediaRepo.imageURL(for: item, type: .primary, fillWidth: 120)) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                default: DT.Color.backgroundSecondary
                }
            }
            .frame(width: 40, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.type == .episode ? (item.seriesName ?? item.name) : item.name)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(DT.Color.textPrimary)
                    .lineLimit(1)
                Text(detail(for: item, isIn: isIn))
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: isIn || isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isIn ? DT.Color.textSecondary : (isSelected ? DT.Color.accent : DT.Color.textSecondary.opacity(0.5)))
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func detail(for item: MediaItem, isIn: Bool) -> String {
        if isIn { return "Already in this playlist" }
        switch item.type {
        case .series: return "Show · every episode"
        case .episode:
            let code = [item.parentIndexNumber.map { "S\($0)" }, item.indexNumber.map { "E\($0)" }].compactMap { $0 }.joined(separator: " · ")
            return [code, item.name].filter { !$0.isEmpty }.joined(separator: " · ")
        default: return item.productionYear.map { "Movie · \($0)" } ?? "Movie"
        }
    }

    private func toggle(_ item: MediaItem) {
        if let index = selectedIDs.firstIndex(of: item.id) { selectedIDs.remove(at: index) } else { selectedIDs.append(item.id) }
        HapticManager.impact(.light)
    }

    private func search() async {
        let term = query.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { results = []; return }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled, let cred = authManager.state.credential else { return }
        isSearching = true
        let found = (try? await client.search(credential: cred, authHeader: authManager.authClient.authHeader(token: cred.accessToken), query: term, limit: 40)) ?? []
        guard !Task.isCancelled else { return }
        results = found.filter { [.movie, .series, .episode].contains($0.type) }
        isSearching = false
    }

    private func add() {
        guard let cred = authManager.state.credential else { return }
        let header = authManager.authClient.authHeader(token: cred.accessToken)
        let ordered = selectedIDs
        isAdding = true
        Task {
            do {
                try await client.addToPlaylist(credential: cred, authHeader: header, playlistId: playlistId, itemIds: ordered)
                await PlaylistStore.shared.load(credential: cred, authHeader: header)
                onAdded()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isAdding = false
        }
    }
}
