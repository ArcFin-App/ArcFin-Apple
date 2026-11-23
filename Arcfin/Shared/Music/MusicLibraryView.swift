// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

/// A music library: Artists, Albums, Songs and Genres, then what was added lately.
struct MusicLibraryView: View {
    let library: JellyfinLibrary
    @State private var recent: MusicPagedList<MusicAlbum>
    @State private var recentlyPlayed: MusicPagedList<MusicSong>
    @State private var mostPlayed: MusicPagedList<MusicSong>
    @State private var query = ""
    @State private var search = MusicSearchModel()
    @State private var showsIdentify = false
    @State private var isEditingRows = false
    @AppStorage(MusicLibraryRow.orderKey) private var rowOrder = ""
    @AppStorage(MusicLibraryRow.hiddenKey) private var hiddenRows = ""
    @AppStorage(MusicSettings.identifySongsKey) private var identifiesSongs = false

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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { isEditingRows = true }
            }
            if identifiesSongs, PlatformMetrics.identifiesSongs {
                ToolbarItem(placement: .primaryAction) {
                    Button("What's Playing?", systemImage: "shazam.logo") { showsIdentify = true }
                }
            }
        }
        .sheet(isPresented: $showsIdentify) { MusicIdentifyView() }
        .sheet(isPresented: $isEditingRows) { MusicLibraryRowsEditor(order: $rowOrder, hidden: $hiddenRows) }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DT.Spacing.lg) {
                VStack(spacing: 0) {
                    // In the order picked with Edit; Apple Music's until then.
                    let rows = MusicLibraryRow.shown(order: rowOrder, hidden: hiddenRows)
                        .filter { $0 != .downloaded || !MusicDownloads.shared.isEmpty }
                    ForEach(rows) { row in
                        NavigationLink { destination(row) } label: {
                            rowLabel(row.title, systemImage: row.systemImage, isLast: row == rows.last)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !recent.items.isEmpty {
                    VStack(alignment: .leading, spacing: DT.Spacing.sm) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Recently Added")
                                .font(DT.Font.sectionTitle)
                                .foregroundStyle(DT.Color.textPrimary)
                                .accessibilityAddTraits(.isHeader)
                            Spacer()
                            NavigationLink("See All") {
                                MusicAlbumsView(libraryID: library.id, title: String(localized: "Recently Added"),
                                                genreID: nil, fixedSort: .dateAdded)
                            }
                            .font(.body.weight(.medium))
                            .tint(DT.Color.accent)
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: DT.Spacing.md) {
                                ForEach(recent.items) { MusicAlbumCard(album: $0).frame(width: 160) }
                            }
                        }
                        .shelfScrollButtons()
                        .padding(.horizontal, -DT.Spacing.pagePad)
                        .contentMargins(.horizontal, DT.Spacing.pagePad, for: .scrollContent)
                    }
                }
                MusicSmartPlaylistShelf(libraryID: library.id)
                MusicSongShelf(title: "Recently Played", list: recentlyPlayed)
                MusicSongShelf(title: "Most Played", list: mostPlayed)
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

    @ViewBuilder
    private func destination(_ row: MusicLibraryRow) -> some View {
        switch row {
        case .playlists: MusicDestination(route: .playlists)
        case .artists: MusicDestination(route: .artists(libraryID: library.id))
        case .albums: MusicDestination(route: .albums(libraryID: library.id, title: String(localized: "Albums")))
        case .songs: MusicDestination(route: .songs(libraryID: library.id))
        case .genres: MusicDestination(route: .genres(libraryID: library.id))
        case .favorites: MusicDestination(route: .favorites(libraryID: library.id))
        case .downloaded: MusicDownloadsView()
        case .yearInMusic: MusicRecapView(libraryID: library.id)
        }
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
    /// Recently Added's See All: newest first, without the sort menu or touching the saved sort.
    var fixedSort: MusicSort?
    @Environment(\.horizontalSizeClass) private var sizeClass
    @AppStorage("music.albumSort") private var savedSort: MusicSort = .name
    private var sort: MusicSort { fixedSort ?? savedSort }
    @State private var favoritesOnly = false
    @State private var list: MusicPagedList<MusicAlbum>?
    /// The sort, filter and search `list` was made for.
    @State private var listKey: String?
    @State private var query = ""
    @State private var term: String?

    var body: some View {
        ScrollView {
            if let list {
                MusicListState(list: list, empty: favoritesOnly ? "No Favorite Albums" : "No Albums", searchTerm: term)
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
        .sectionSearchable(text: $query, prompt: "Search Albums")
        .musicSearchTerm(query, $term)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if fixedSort == nil {
                        Picker("Sort By", selection: $savedSort) {
                        Text("Title").tag(MusicSort.name)
                        Text("Artist").tag(MusicSort.artist)
                        Text("Year").tag(MusicSort.year)
                        Text("Recently Added").tag(MusicSort.dateAdded)
                        }
                    }
                    Toggle("Favorites Only", systemImage: "star", isOn: $favoritesOnly)
                } label: {
                    Label("Sort and Filter", systemImage: "line.3.horizontal.decrease")
                }
            }
        }
        .task(id: "\(sort.rawValue)-\(favoritesOnly)-\(term ?? "")") {
            // The task runs again on coming back from an album; the list and its place stay.
            let key = "\(sort.rawValue)-\(favoritesOnly)-\(term ?? "")"
            if key != listKey {
                list = makeList()
                listKey = key
            }
            await list?.loadIfNeeded()
        }
    }

    private func makeList() -> MusicPagedList<MusicAlbum> {
        let filter = MusicFilter(favoritesOnly: favoritesOnly, genreId: genreID, searchTerm: term)
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
        if !model.results.isEmpty || !model.appleMusic.isEmpty {
            ScrollView {
                MusicSearchSection(results: model.results, appleMusic: model.appleMusic)
                    .padding(.bottom, DT.Spacing.xl)
            }
        } else if model.isSearching {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView.search
        }
    }
}

/// The rows at the top of the music library, in an order and with a set that Edit changes.
enum MusicLibraryRow: String, CaseIterable, Identifiable {
    case playlists, artists, albums, songs, genres, favorites, downloaded, yearInMusic

    static let orderKey = "music.libraryRowOrder"
    static let hiddenKey = "music.libraryRowsHidden"

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .playlists: "Playlists"
        case .artists: "Artists"
        case .albums: "Albums"
        case .songs: "Songs"
        case .genres: "Genres"
        case .favorites: "Favorites"
        case .downloaded: "Downloaded"
        case .yearInMusic: "Year in Music"
        }
    }

    var systemImage: String {
        switch self {
        case .playlists: "music.note.list"
        case .artists: "music.microphone"
        case .albums: "square.stack"
        case .songs: "music.note"
        case .genres: "guitars"
        case .favorites: "star"
        case .downloaded: "arrow.down.circle"
        case .yearInMusic: "chart.bar.xaxis"
        }
    }

    /// Every row in the saved order; ones it doesn't know yet (new in an update) at the end.
    static func ordered(_ order: String) -> [MusicLibraryRow] {
        let saved = order.split(separator: ",").compactMap { MusicLibraryRow(rawValue: String($0)) }
        return saved + allCases.filter { !saved.contains($0) }
    }

    static func shown(order: String, hidden: String) -> [MusicLibraryRow] {
        let hiddenRows = Set(hidden.split(separator: ",").map(String.init))
        return ordered(order).filter { !hiddenRows.contains($0.rawValue) }
    }
}

/// Edit: which rows the library shows, and their order.
struct MusicLibraryRowsEditor: View {
    @Binding var order: String
    @Binding var hidden: String
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [MusicLibraryRow] = []
    @State private var hiddenRows: Set<String> = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(rows) { row in
                        Button {
                            if hiddenRows.contains(row.rawValue) { hiddenRows.remove(row.rawValue) } else { hiddenRows.insert(row.rawValue) }
                        } label: {
                            HStack(spacing: DT.Spacing.sm) {
                                Image(systemName: hiddenRows.contains(row.rawValue) ? "circle" : "checkmark.circle.fill")
                                    .foregroundStyle(hiddenRows.contains(row.rawValue) ? DT.Color.textSecondary : DT.Color.accent)
                                    .font(.title3)
                                Label(row.title, systemImage: row.systemImage)
                                    .foregroundStyle(DT.Color.textPrimary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(hiddenRows.contains(row.rawValue) ? [] : .isSelected)
                    }
                    .onMove { rows.move(fromOffsets: $0, toOffset: $1) }
                } footer: {
                    Text("Tick the rows to show, and drag them into the order you like.")
                }
            }
            .alwaysEditing()
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Reset") {
                        rows = MusicLibraryRow.allCases
                        hiddenRows = []
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        order = rows.map(\.rawValue).joined(separator: ",")
                        hidden = hiddenRows.sorted().joined(separator: ",")
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            rows = MusicLibraryRow.ordered(order)
            hiddenRows = Set(hidden.split(separator: ",").map(String.init))
        }
    }
}
