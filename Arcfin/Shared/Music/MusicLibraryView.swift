// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

/// A music library: Artists, Albums, Songs and Genres, then what was added lately.
struct MusicLibraryView: View {
    let library: JellyfinLibrary
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var recent: MusicPagedList<MusicAlbum>
    @State private var recentlyPlayed: MusicPagedList<MusicSong>
    @State private var mostPlayed: MusicPagedList<MusicSong>
    @State private var query = ""
    @State private var search = MusicSearchModel()

    init(library: JellyfinLibrary) {
        self.library = library
        let id = library.id
        _recentlyPlayed = State(initialValue: MusicSongShelf.list(libraryID: id, sort: .datePlayed))
        _mostPlayed = State(initialValue: MusicSongShelf.list(libraryID: id, sort: .playCount))
        _recent = State(initialValue: MusicPagedList { _ in
            let page = try await MusicAPI.call {
                try await $0.getMusicAlbums(credential: $1, authHeader: $2, libraryId: id, sort: .dateAdded,
                                            ascending: false, limit: 40)
            }
            return (page.albums, page.albums.count)
        })
    }

    var body: some View {
        Group {
            if query.trimmingCharacters(in: .whitespaces).count >= 2 {
                MusicLibrarySearchResults(model: search)
            } else {
                content
            }
        }
        .screenBackground()
        .navigationTitle(Text(verbatim: library.name))
        .searchable(text: $query, prompt: "Artists, albums and songs")
        .onChange(of: query) { _, term in search.search(term) }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DT.Spacing.lg) {
                VStack(spacing: 0) {
                    row("Favorites", systemImage: "star", route: .favorites(libraryID: library.id))
                    row("Playlists", systemImage: "music.note.list", route: .playlists)
                    row("Artists", systemImage: "music.microphone", route: .artists(libraryID: library.id))
                    row("Albums", systemImage: "square.stack", route: .albums(libraryID: library.id, title: String(localized: "Albums")))
                    row("Songs", systemImage: "music.note", route: .songs(libraryID: library.id))
                    row("Genres", systemImage: "guitars", route: .genres(libraryID: library.id), isLast: MusicDownloads.shared.isEmpty)
                    if !MusicDownloads.shared.isEmpty {
                        NavigationLink { MusicDownloadsView() } label: {
                            rowLabel("Downloaded", systemImage: "arrow.down.circle", isLast: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
                MusicSmartPlaylistShelf(libraryID: library.id)
                MusicSongShelf(title: "Recently Played", list: recentlyPlayed)
                MusicSongShelf(title: "Most Played", list: mostPlayed)
                VStack(alignment: .leading, spacing: DT.Spacing.sm) {
                    Text("Recently Added")
                        .font(DT.Font.sectionTitle)
                        .foregroundStyle(DT.Color.textPrimary)
                    MusicListState(list: recent, empty: "No Albums")
                    LazyVGrid(columns: MusicGrid.columns(sizeClass), alignment: .leading, spacing: DT.Spacing.lg) {
                        ForEach(recent.items) { MusicAlbumCard(album: $0) }
                    }
                }
            }
            .padding(.horizontal, DT.Spacing.pagePad)
            .padding(.bottom, DT.Spacing.xl)
        }
        .task {
            async let albums: Void = recent.loadIfNeeded()
            async let played: Void = recentlyPlayed.loadIfNeeded()
            async let most: Void = mostPlayed.loadIfNeeded()
            _ = await (albums, played, most)
        }
        .refreshable {
            async let albums: Void = recent.reload()
            async let played: Void = recentlyPlayed.reload()
            async let most: Void = mostPlayed.reload()
            _ = await (albums, played, most)
        }
    }

    private func row(_ title: LocalizedStringKey, systemImage: String, route: MusicRoute, isLast: Bool = false) -> some View {
        NavigationLink { MusicDestination(route: route) } label: {
            rowLabel(title, systemImage: systemImage, isLast: isLast)
        }
        .buttonStyle(.plain)
    }

    private func rowLabel(_ title: LocalizedStringKey, systemImage: String, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: DT.Spacing.md) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(DT.Color.accent)
                    .frame(width: 30)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.title3)
                    .foregroundStyle(DT.Color.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(DT.Color.textSecondary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 12)
            if !isLast {
                Divider().padding(.leading, 46)
            }
        }
        .contentShape(Rectangle())
    }
}

/// A row of songs this profile has played, newest or most often first; tap one to play the
/// row from there. Hidden until there's something in it.
struct MusicSongShelf: View {
    let title: LocalizedStringKey
    let list: MusicPagedList<MusicSong>

    static func list(libraryID: String, sort: MusicSort) -> MusicPagedList<MusicSong> {
        MusicPagedList { _ in
            let page = try await MusicAPI.call {
                try await $0.getMusicTracks(credential: $1, authHeader: $2, libraryId: libraryID, sort: sort,
                                            ascending: false, filter: .init(playedOnly: true), limit: 20)
            }
            return (page.tracks, page.tracks.count)
        }
    }

    var body: some View {
        if !list.items.isEmpty {
            VStack(alignment: .leading, spacing: DT.Spacing.sm) {
                Text(title)
                    .font(DT.Font.sectionTitle)
                    .foregroundStyle(DT.Color.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: DT.Spacing.md) {
                        ForEach(Array(list.items.enumerated()), id: \.element.id) { index, song in
                            Button { MusicActions.play(list.items, from: index) } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    MusicArtwork(url: MusicAPI.artworkURL(song, width: 300))
                                        .frame(width: 140, height: 140)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(verbatim: song.name)
                                            .font(.footnote.weight(.medium))
                                            .foregroundStyle(DT.Color.textPrimary)
                                        Text(verbatim: song.artistLine ?? "")
                                            .font(.footnote)
                                            .foregroundStyle(DT.Color.textSecondary)
                                    }
                                    .lineLimit(1)
                                }
                                .frame(width: 140, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contextMenu { MusicSongMenu(song: song) }
                        }
                    }
                }
                .shelfScrollButtons()
                .padding(.horizontal, -DT.Spacing.pagePad)
                .contentMargins(.horizontal, DT.Spacing.pagePad, for: .scrollContent)
            }
        }
    }
}

/// Every album, or a genre's, as a grid with a sort and a favourites filter.
struct MusicAlbumsView: View {
    let libraryID: String
    let title: String
    let genreID: String?
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage("music.albumSort") private var sort: MusicSort = .name
    @State private var favoritesOnly = false
    @State private var list: MusicPagedList<MusicAlbum>?

    var body: some View {
        ScrollView {
            if let list {
                MusicListState(list: list, empty: favoritesOnly ? "No Favorite Albums" : "No Albums")
                LazyVGrid(columns: MusicGrid.columns(sizeClass), alignment: .leading, spacing: DT.Spacing.lg) {
                    ForEach(list.items) { album in
                        MusicAlbumCard(album: album)
                            .task { await list.rowAppeared(album) }
                    }
                }
                .padding(.horizontal, DT.Spacing.pagePad)
                .padding(.bottom, DT.Spacing.xl)
            }
        }
        .screenBackground()
        .navigationTitle(Text(verbatim: title))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Sort By", selection: $sort) {
                        Text("Title").tag(MusicSort.name)
                        Text("Artist").tag(MusicSort.artist)
                        Text("Year").tag(MusicSort.year)
                        Text("Recently Added").tag(MusicSort.dateAdded)
                    }
                    Toggle("Favorites Only", systemImage: "star", isOn: $favoritesOnly)
                } label: {
                    Label("Sort and Filter", systemImage: "line.3.horizontal.decrease")
                }
            }
        }
        .task(id: "\(sort.rawValue)-\(favoritesOnly)") {
            let list = makeList()
            self.list = list
            await list.loadIfNeeded()
        }
    }

    private func makeList() -> MusicPagedList<MusicAlbum> {
        let filter = MusicFilter(favoritesOnly: favoritesOnly, genreId: genreID)
        let libraryID = libraryID, sort = sort
        return MusicPagedList { start in
            let page = try await MusicAPI.call {
                try await $0.getMusicAlbums(credential: $1, authHeader: $2, libraryId: libraryID, sort: sort,
                                            ascending: sort != .dateAdded && sort != .year, filter: filter,
                                            startIndex: start)
            }
            return (page.albums, page.total)
        }
    }
}

/// Search inside a music library: artists, albums and songs.
struct MusicLibrarySearchResults: View {
    let model: MusicSearchModel

    var body: some View {
        if !model.results.isEmpty {
            ScrollView {
                MusicSearchSection(results: model.results)
                    .padding(.bottom, DT.Spacing.xl)
            }
        } else if model.isSearching {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView.search
        }
    }
}
