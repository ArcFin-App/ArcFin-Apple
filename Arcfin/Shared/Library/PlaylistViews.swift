// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import JellyfinAPI

// MARK: - Add to Playlist

struct AddToPlaylistSheet: View {
    let item: MediaItem

    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    private var store: PlaylistStore { .shared }
    @State private var newName = ""
    @State private var busy = false
    @State private var errorMessage: String?
    /// For a show or season: how many episodes adding it puts in the playlist.
    @State private var episodeCount: Int?

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
                } footer: {
                    // The server adds a show or season as each of its episodes.
                    if let episodeCount, episodeCount > 1 {
                        Text("Adds \(episodeCount) episodes of \(item.type == .season ? (item.seriesName.map { "\($0), \(item.name)" } ?? item.name) : item.name).")
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
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .task {
                guard let credential, let authHeader else { return }
                await store.load(credential: credential, authHeader: authHeader)
            }
            .task {
                guard let credential, let authHeader else { return }
                let seriesId = item.type == .series ? item.id : (item.type == .season ? item.seriesId : nil)
                guard let seriesId else { return }
                episodeCount = try? await JellyfinMediaClient().getEpisodes(
                    credential: credential, authHeader: authHeader, seriesId: seriesId,
                    seasonId: item.type == .season ? item.id : nil
                ).filter { !$0.isVirtual }.count
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
    /// Episode counts of the shows listed, fetched as their rows appear.
    @State private var episodeCounts: [String: Int] = [:]
    /// The picked titles that are shows, kept apart from the list so a new search doesn't lose them.
    @State private var pickedShowIDs: Set<String> = []

    private let client = JellyfinMediaClient()

    /// The server adds a show as each of its episodes, so with a show picked the total
    /// differs from the number of rows ticked.
    private var selectionSummary: String? {
        let shows = selectedIDs.filter { pickedShowIDs.contains($0) }
        guard !shows.isEmpty else { return nil }
        let episodes = shows.compactMap { episodeCounts[$0] }.reduce(0, +)
        let others = selectedIDs.count - shows.count
        let showText = shows.count == 1 ? "1 show" : "\(shows.count) shows"
        let episodeText = episodes > 0 && shows.allSatisfy({ episodeCounts[$0] != nil }) ? " (\(episodes) episodes)" : ""
        let otherText = others > 0 ? " and \(others) other \(others == 1 ? "title" : "titles")" : ""
        return "Adds \(showText)\(episodeText)\(otherText)."
    }

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
                if let selectionSummary {
                    Text(selectionSummary)
                        .font(.footnote)
                        .foregroundStyle(DT.Color.textSecondary)
                        .listRowBackground(Color.clear)
                }
                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }
            }
            .arcfinListStyle()
            .screenBackground()
            .searchable(text: $query, prompt: "Movies, shows, episodes")
            .navigationTitle("Add Titles")
            .inlineNavigationTitle()
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
        .task(id: item.id) { await loadEpisodeCount(item) }
    }

    private func loadEpisodeCount(_ item: MediaItem) async {
        guard item.type == .series, episodeCounts[item.id] == nil, let cred = authManager.state.credential else { return }
        let episodes = try? await client.getEpisodes(
            credential: cred, authHeader: authManager.authClient.authHeader(token: cred.accessToken),
            seriesId: item.id, seasonId: nil)
        if let episodes { episodeCounts[item.id] = episodes.filter { !$0.isVirtual }.count }
    }

    private func detail(for item: MediaItem, isIn: Bool) -> String {
        if isIn { return "Already in this playlist" }
        switch item.type {
        case .series: return episodeCounts[item.id].map { "Show · adds \($0) episodes" } ?? "Show · every episode"
        case .episode:
            let code = [item.parentIndexNumber.map { "S\($0)" }, item.indexNumber.map { "E\($0)" }].compactMap { $0 }.joined(separator: " · ")
            return [code, item.name].filter { !$0.isEmpty }.joined(separator: " · ")
        default: return item.productionYear.map { "Movie · \($0)" } ?? "Movie"
        }
    }

    private func toggle(_ item: MediaItem) {
        if let index = selectedIDs.firstIndex(of: item.id) { selectedIDs.remove(at: index) } else { selectedIDs.append(item.id) }
        if item.type == .series { pickedShowIDs.insert(item.id) }
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
                ContainingSets.shared.invalidate()
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
