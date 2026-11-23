// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI
import MediaEngine

/// Every song, or only the favourites, with Play and Shuffle above and a sort.
struct MusicSongsView: View {
    let libraryID: String
    var favoritesOnly = false
    @AppStorage("music.songSort") private var sort: MusicSort = .name
    @Environment(AuthManager.self) private var authManager
    @State private var list: MusicPagedList<MusicSong>?
    /// The sort and search `list` was made for.
    @State private var listKey: String?
    @State private var query = ""
    @State private var term: String?

    var body: some View {
        List {
            if let list {
                MusicPlayShuffleButtons(play: { MusicActions.play(list.items) }, shuffle: { shuffleAll() })
                    .disabled(list.items.isEmpty)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                MusicListState(list: list, empty: favoritesOnly ? "No Favorite Songs" : "No Songs", searchTerm: term)
                    .listRowBackground(Color.clear)
                ForEach(Array(list.items.enumerated()), id: \.element.id) { index, song in
                    MusicSongRow(song: song) { MusicActions.play(list.items, from: index) }
                        .task { await list.rowAppeared(song) }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle(favoritesOnly ? "Favorite Songs" : "Songs")
        .sectionSearchable(text: $query, prompt: favoritesOnly ? "Search Favorites" : "Search Songs")
        .musicSearchTerm(query, $term)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Sort By", selection: $sort) {
                        Text("Title").tag(MusicSort.name)
                        Text("Artist").tag(MusicSort.artist)
                        Text("Album").tag(MusicSort.album)
                        Text("Recently Added").tag(MusicSort.dateAdded)
                        Text("Most Played").tag(MusicSort.playCount)
                    }
                    .syncLocked("music.songSort", authManager)
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
            }
        }
        .task(id: "\(sort.rawValue)-\(term ?? "")") {
            // The task runs again on coming back from a pushed screen; the list and its place stay.
            let key = "\(sort.rawValue)-\(term ?? "")"
            if key != listKey {
                let libraryID = libraryID, sort = sort, filter = MusicFilter(favoritesOnly: favoritesOnly, searchTerm: term)
                list = MusicPagedList<MusicSong> { start in
                    let page = try await MusicAPI.call {
                        try await $0.getMusicTracks(credential: $1, authHeader: $2, libraryId: libraryID, sort: sort,
                                                    ascending: sort != .dateAdded && sort != .playCount, filter: filter,
                                                    startIndex: start)
                    }
                    return (page.tracks, page.total)
                }
                listKey = key
            }
            await list?.loadIfNeeded()
        }
    }

    /// The whole list at random, not only the songs loaded so far.
    private func shuffleAll() {
        let libraryID = libraryID, filter = MusicFilter(favoritesOnly: favoritesOnly, searchTerm: term)
        Task {
            let page = try? await MusicAPI.call {
                try await $0.getMusicTracks(credential: $1, authHeader: $2, libraryId: libraryID, sort: .random,
                                            filter: filter, limit: 300)
            }
            if let songs = page?.tracks, !songs.isEmpty { MusicActions.play(songs) }
        }
    }
}

/// A song in a list: its cover, name and artist, and a menu.
struct MusicSongRow: View {
    let song: MusicSong
    /// On a playlist's page: Remove from Playlist in its menu.
    var onRemove: (() -> Void)?
    let play: () -> Void
    private var player: MusicQueuePlayer { AppServices.music.player }

    @ViewBuilder
    private var menu: some View {
        MusicSongMenu(song: song)
        if let onRemove {
            Divider()
            Button("Remove from Playlist", systemImage: "minus.circle", role: .destructive, action: onRemove)
        }
    }

    var body: some View {
        HStack(spacing: DT.Spacing.xs) {
            Button(action: play) {
                HStack(spacing: DT.Spacing.sm) {
                    MusicArtwork(url: MusicAPI.artworkURL(song, width: 120), cornerRadius: DT.Radius.xs)
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: song.name)
                            .foregroundStyle(DT.Color.textPrimary)
                        if let artist = song.artistLine {
                            Text(verbatim: artist)
                                .font(.subheadline)
                                .foregroundStyle(DT.Color.textSecondary)
                        }
                    }
                    .lineLimit(1)
                    .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                    Spacer(minLength: DT.Spacing.xs)
                    MusicDownloadedMark(songID: song.id)
                    if player.current?.id == song.id {
                        MusicPlayingIndicator(isPlaying: player.isPlaying)
                    }
                }
                .padding(.vertical, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // The song's menu, in reach without a long press, as in Apple Music; beside the
            // row's button, which would otherwise take its taps.
            Menu {
                menu
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DT.Color.textSecondary)
                    .frame(width: 32, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("More")
        }
        .listRowBackground(Color.clear)
        .contextMenu { menu }
        .swipeActions(edge: .leading) {
            Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") { MusicActions.playNext([song]) }
                .tint(DT.Color.accent)
        }
        .swipeActions(edge: .trailing) {
            Button("Play Last", systemImage: "text.line.last.and.arrowtriangle.forward") { MusicActions.addToQueue([song]) }
                .tint(DT.Color.textSecondary)
        }
    }
}

/// The library's album artists, A to Z.
struct MusicArtistsView: View {
    let libraryID: String
    @State private var list: MusicPagedList<MusicArtist>
    @State private var query = ""
    @State private var term: String?
    /// The search `list` was made for.
    @State private var listTerm: String?

    init(libraryID: String) {
        self.libraryID = libraryID
        _list = State(initialValue: Self.list(libraryID: libraryID, term: nil))
    }

    private static func list(libraryID: String, term: String?) -> MusicPagedList<MusicArtist> {
        MusicPagedList { start in
            let page = try await MusicAPI.call {
                try await $0.getMusicArtists(credential: $1, authHeader: $2, libraryId: libraryID,
                                             filter: MusicFilter(searchTerm: term), startIndex: start, limit: 500)
            }
            return (page.artists, page.total)
        }
    }

    @Environment(\.horizontalSizeClass) private var sizeClass

    private var columns: [GridItem] {
        sizeClass == .regular
            ? [GridItem(.adaptive(minimum: 130), spacing: DT.Spacing.md)]
            : Array(repeating: GridItem(.flexible(), spacing: DT.Spacing.md), count: 3)
    }

    /// The artists under the letter they start with, # first as in the other libraries; worked
    /// out as pages arrive, not on every render.
    @State private var sections: [(letter: String, artists: [MusicArtist])] = []

    private static func sections(of artists: [MusicArtist]) -> [(letter: String, artists: [MusicArtist])] {
        let grouped = Dictionary(grouping: artists) { letter(of: $0.name) }
        return LibraryLetterIndex.letters.compactMap { letter in grouped[letter].map { (letter, $0) } }
    }

    private static func letter(of name: String) -> String {
        let first = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespaces).prefix(1).uppercased()
        return first.first.map { ("A"..."Z").contains(String($0)) } == true ? first : "#"
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                MusicListState(list: list, empty: "No Artists", searchTerm: term)
                LazyVStack(alignment: .leading, spacing: DT.Spacing.lg, pinnedViews: [.sectionHeaders]) {
                    ForEach(sections, id: \.letter) { section in
                        Section {
                            LazyVGrid(columns: columns, alignment: .center, spacing: DT.Spacing.lg) {
                                ForEach(section.artists) { artist in
                                    NavigationLink { MusicDestination(route: MusicRoute.artist(artist, libraryID: libraryID)) } label: {
                                        VStack(spacing: DT.Spacing.xs) {
                                            MusicArtwork(url: MusicAPI.artworkURL(artist, width: 300), isCircle: true)
                                                .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                                            Text(verbatim: artist.name)
                                                .font(.footnote.weight(.medium))
                                                .foregroundStyle(DT.Color.textPrimary)
                                                .multilineTextAlignment(.center)
                                                .lineLimit(2)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .task { await list.rowAppeared(artist) }
                                }
                            }
                        } header: {
                            Text(verbatim: section.letter)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(DT.Color.accent)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, DT.Spacing.xxs)
                                .background(DT.Color.backgroundPrimary.opacity(0.92))
                                .accessibilityAddTraits(.isHeader)
                        }
                        .id(section.letter)
                    }
                }
                .padding(.leading, DT.Spacing.pagePad)
                // Room for the A–Z bar.
                .padding(.trailing, DT.Spacing.pagePad + 14)
                .padding(.bottom, DT.Spacing.xl)
            }
            .overlay {
                if list.hasLoaded, !list.items.isEmpty, term == nil {
                    LetterIndexBar { letter in Task { await jump(to: letter, proxy) } }
                }
            }
        }
        .screenBackground()
        .navigationTitle("Artists")
        .sectionSearchable(text: $query, prompt: "Search Artists")
        .musicSearchTerm(query, $term)
        .onChange(of: list.items, initial: true) { _, artists in sections = Self.sections(of: artists) }
        .task(id: term) {
            if term != listTerm {
                list = Self.list(libraryID: libraryID, term: term)
                listTerm = term
            }
            await list.loadIfNeeded()
        }
    }

    /// To the letter, or the next one that has artists, loading more until it's there.
    private func jump(to letter: String, _ proxy: ScrollViewProxy) async {
        let letters = LibraryLetterIndex.letters
        guard let start = letters.firstIndex(of: letter) else { return }
        let wanted = Set(letters[start...])
        while !list.items.contains(where: { wanted.contains(Self.letter(of: $0.name)) }), list.items.count < list.total {
            let before = list.items.count
            await list.loadMore()
            if list.items.count == before { break }
        }
        let sections = Self.sections(of: list.items)
        let present = Set(sections.map(\.letter))
        guard let target = letters[start...].first(where: present.contains) ?? sections.last?.letter else { return }
        withAnimation(DT.Animation.standard) { proxy.scrollTo(target, anchor: .top) }
    }
}

/// The library's genres; each opens its albums.
struct MusicGenresView: View {
    let libraryID: String
    @State private var list: MusicPagedList<MusicGenre>
    @State private var query = ""
    @State private var term: String?

    init(libraryID: String) {
        self.libraryID = libraryID
        _list = State(initialValue: MusicPagedList { _ in
            let genres = try await MusicAPI.call { try await $0.getMusicGenres(credential: $1, authHeader: $2, libraryId: libraryID) }
            return (genres, genres.count)
        })
    }

    @Environment(\.horizontalSizeClass) private var sizeClass

    /// A colour for each genre, the same every time, from the app's palette.
    private static let hues = ["FF6A4D", "60A5FA", "10B981", "F59E0B", "F43F5E", "B83A25", "1D4ED8", "047857"]
    private func tint(_ genre: MusicGenre) -> Color {
        let index = genre.name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7FFF_FFFF } % Self.hues.count
        return DT.Color.palette(Self.hues[index])
    }

    var body: some View {
        ScrollView {
            MusicListState(list: list, empty: "No Genres")
            let genres = list.items.matching(term, \.name)
            if list.hasLoaded, !list.items.isEmpty, genres.isEmpty, let term {
                ContentUnavailableView.search(text: term)
            }
            LazyVGrid(columns: MusicGrid.columns(sizeClass), spacing: DT.Spacing.md) {
                ForEach(genres) { genre in
                    NavigationLink { MusicDestination(route: MusicRoute.albums(libraryID: libraryID, title: genre.name, genreID: genre.id)) } label: {
                        MusicGenreTile(genre: genre, libraryID: libraryID, tint: tint(genre))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DT.Spacing.pagePad)
            .padding(.bottom, DT.Spacing.xl)
        }
        .screenBackground()
        .navigationTitle("Genres")
        .sectionSearchable(text: $query, prompt: "Search Genres")
        .musicSearchTerm(query, $term)
        .task { await list.loadIfNeeded() }
    }
}

/// An artist: their picture and name, Play (their most played) and Shuffle, their top songs,
/// albums, singles and EPs, the albums they're on, what the server knows about them, and
/// artists like them.
struct MusicArtistView: View {
    let libraryID: String?
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var artist: MusicArtist
    @State private var albums: MusicPagedList<MusicAlbum>
    @State private var showsFullBio = false
    @State private var topSongs: [MusicSong] = []
    @State private var appearsOn: [MusicAlbum] = []
    @State private var similar: [MusicArtist] = []
    @State private var confirmDownloadAll = false

    init(artist: MusicArtist, libraryID: String?) {
        self.libraryID = libraryID
        _artist = State(initialValue: artist)
        let filter = MusicFilter(artistId: artist.id)
        _albums = State(initialValue: MusicPagedList { start in
            let page = try await MusicAPI.call {
                try await $0.getMusicAlbums(credential: $1, authHeader: $2, libraryId: libraryID, sort: .year,
                                            ascending: false, filter: filter, startIndex: start)
            }
            return (page.albums, page.total)
        })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DT.Spacing.lg) {
                // The artist's photo across the top, like an album page, with their logo or name on it.
                MusicHero(play: { play(shuffled: false) }, shuffle: { play(shuffled: true) }) { _ in
                    MusicHeroImage(url: heroArtURL(width: 1600))
                } heading: {
                    MusicArtistTitle(artist: artist, logoSize: CGSize(width: 280, height: 96), onArt: true)
                } info: {
                    EmptyView()
                }
                VStack(alignment: .leading, spacing: DT.Spacing.lg) {
                    if !topSongs.isEmpty {
                        VStack(alignment: .leading, spacing: DT.Spacing.xs) {
                            sectionTitle("Top Songs")
                            ForEach(Array(topSongs.enumerated()), id: \.element.id) { index, song in
                                MusicSongRow(song: song) { MusicActions.play(topSongs, from: index) }
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: DT.Spacing.sm) {
                        sectionTitle("Albums")
                        MusicListState(list: albums, empty: "No Albums")
                        albumGrid(albums.items.filter { !$0.isSingle })
                    }
                    let singles = albums.items.filter(\.isSingle)
                    if !singles.isEmpty {
                        VStack(alignment: .leading, spacing: DT.Spacing.sm) {
                            sectionTitle("Singles & EPs")
                            albumGrid(singles)
                        }
                    }
                    if !appearsOn.isEmpty {
                        VStack(alignment: .leading, spacing: DT.Spacing.sm) {
                            sectionTitle("Appears On")
                            albumShelf(appearsOn)
                        }
                    }
                    if let overview = artist.overview, !overview.isEmpty {
                        VStack(alignment: .leading, spacing: DT.Spacing.xs) {
                            Text("About")
                                .font(DT.Font.sectionTitle)
                                .foregroundStyle(DT.Color.textPrimary)
                            Text(verbatim: overview)
                                .font(.callout)
                                .foregroundStyle(DT.Color.textSecondary)
                                .lineLimit(showsFullBio ? nil : 4)
                            Button(showsFullBio ? "Less" : "More") { withAnimation { showsFullBio.toggle() } }
                                .font(.callout.weight(.semibold))
                                .tint(DT.Color.accent)
                        }
                    }
                    if !similar.isEmpty {
                        VStack(alignment: .leading, spacing: DT.Spacing.sm) {
                            sectionTitle("Similar Artists")
                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(alignment: .top, spacing: DT.Spacing.md) {
                                    ForEach(similar) { other in
                                        NavigationLink { MusicDestination(route: .artist(other, libraryID: libraryID)) } label: {
                                            VStack(spacing: 6) {
                                                MusicArtwork(url: MusicAPI.artworkURL(other, width: 300), isCircle: true)
                                                    .frame(width: 120, height: 120)
                                                Text(verbatim: other.name)
                                                    .font(.footnote.weight(.medium))
                                                    .foregroundStyle(DT.Color.textPrimary)
                                                    .lineLimit(1)
                                            }
                                            .frame(width: 120)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .shelfScrollButtons()
                            .padding(.horizontal, -DT.Spacing.pagePad)
                            .contentMargins(.horizontal, DT.Spacing.pagePad, for: .scrollContent)
                        }
                    }
                }
                .padding(.horizontal, DT.Spacing.pagePad)
            }
            .padding(.bottom, DT.Spacing.xl)
        }
        .ignoresSafeArea(edges: .top)
        .musicHeroBackground(heroArtURL(width: 300))
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu("More", systemImage: "ellipsis") {
                    Button("Create Station", systemImage: "dot.radiowaves.left.and.right") {
                        let id = artist.id
                        Task { await MusicActions.instantMix(from: id) }
                    }
                    MusicArtistDownloadButton(artist: artist, albums: albums.items) { confirmDownloadAll = true }
                }
            }
        }
        .confirmationDialog(Text("Download all \(max(albums.total, albums.items.count)) albums by \(artist.name)?"),
                            isPresented: $confirmDownloadAll, titleVisibility: .visible) {
            Button("Download All Albums") {
                let artist = artist
                Task { await MusicDownloads.shared.download(artist: artist) }
            }
        }
        .task {
            let id = artist.id, libraryID = libraryID
            async let loaded: Void = albums.loadIfNeeded()
            async let full = try? MusicAPI.call { try await $0.getMusicArtist(credential: $1, authHeader: $2, artistId: id) }
            async let top = try? MusicAPI.call {
                try await $0.getMusicTracks(credential: $1, authHeader: $2, libraryId: libraryID, sort: .playCount,
                                            ascending: false, filter: MusicFilter(artistId: id), limit: 5)
            }
            async let on = try? MusicAPI.call {
                try await $0.getAppearsOn(credential: $1, authHeader: $2, artistId: id, libraryId: libraryID)
            }
            async let like = try? MusicAPI.call { try await $0.getSimilarArtists(credential: $1, authHeader: $2, artistId: id) }
            _ = await loaded
            if let full = await full { artist = full }
            topSongs = await top?.tracks ?? []
            appearsOn = await on ?? []
            similar = await like ?? []
        }
    }

    /// The square hero takes the photo, the wide strip the backdrop; either stands in for the other.
    private func heroArtURL(width: Int) -> URL? {
        let photo = MusicAPI.artworkURL(artist, width: width), backdrop = MusicAPI.backdropURL(artist, width: width)
        return sizeClass == .regular ? backdrop ?? photo : photo ?? backdrop
    }

    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(DT.Font.sectionTitle)
            .foregroundStyle(DT.Color.textPrimary)
            .accessibilityAddTraits(.isHeader)
    }

    private func albumGrid(_ items: [MusicAlbum]) -> some View {
        LazyVGrid(columns: MusicGrid.columns(sizeClass), alignment: .leading, spacing: DT.Spacing.lg) {
            ForEach(items) { album in
                MusicAlbumCard(album: album, showsArtist: false)
                    .task { await albums.rowAppeared(album) }
            }
        }
    }

    private func albumShelf(_ items: [MusicAlbum]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: DT.Spacing.md) {
                ForEach(items) { MusicAlbumCard(album: $0).frame(width: 150) }
            }
        }
        .shelfScrollButtons()
        .padding(.horizontal, -DT.Spacing.pagePad)
        .contentMargins(.horizontal, DT.Spacing.pagePad, for: .scrollContent)
    }

    private func play(shuffled: Bool) {
        let filter = MusicFilter(artistId: artist.id), libraryID = libraryID
        Task {
            let page = try? await MusicAPI.call {
                try await $0.getMusicTracks(credential: $1, authHeader: $2, libraryId: libraryID,
                                            sort: shuffled ? .random : .playCount, ascending: false, filter: filter, limit: 200)
            }
            if let songs = page?.tracks, !songs.isEmpty { MusicActions.play(songs) }
        }
    }
}

/// The profile's music playlists.
struct MusicPlaylistsView: View {
    @State private var list = MusicPagedList<MusicPlaylist> { _ in
        let playlists = try await MusicAPI.call { try await $0.getMusicPlaylists(credential: $1, authHeader: $2) }
        return (playlists, playlists.count)
    }
    @State private var query = ""
    @State private var term: String?

    var body: some View {
        let playlists = list.items.matching(term, \.name)
        List {
            MusicListState(list: list, empty: "No Playlists")
                .listRowBackground(Color.clear)
            if list.hasLoaded, !list.items.isEmpty, playlists.isEmpty, let term {
                ContentUnavailableView.search(text: term)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            ForEach(playlists) { playlist in
                NavigationLink { MusicDestination(route: MusicRoute.playlist(playlist)) } label: {
                    HStack(spacing: DT.Spacing.sm) {
                        MusicArtwork(url: MusicAPI.artworkURL(playlist, width: 200), cornerRadius: DT.Radius.sm)
                            .frame(width: 64, height: 64)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: playlist.name)
                                .font(.body.weight(.medium))
                                .foregroundStyle(DT.Color.textPrimary)
                            if let count = playlist.songCount {
                                Text("\(count) songs")
                                    .font(.subheadline)
                                    .foregroundStyle(DT.Color.textSecondary)
                            }
                        }
                        .lineLimit(1)
                        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                    }
                    .padding(.vertical, 2)
                }
                .listRowBackground(Color.clear)
                .contextMenu {
                    Button("Play", systemImage: "play") { Task { MusicActions.play(await MusicActions.playlistSongs(playlist)) } }
                    Button("Shuffle", systemImage: "shuffle") { Task { MusicActions.shuffle(await MusicActions.playlistSongs(playlist)) } }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("Playlists")
        .sectionSearchable(text: $query, prompt: "Search Playlists")
        .musicSearchTerm(query, $term)
        .task { await list.loadIfNeeded() }
        .refreshable { await list.reload() }
        .onChange(of: MusicPlaylistEditor.shared.changeCount) { Task { await list.reload() } }
    }
}

/// A playlist: its cover and name, Play and Shuffle, and its songs in order.
struct MusicPlaylistView: View {
    let playlist: MusicPlaylist
    @State private var songs: [MusicSong] = []
    @State private var hasLoaded = false

    var body: some View {
        List {
            VStack(spacing: DT.Spacing.sm) {
                MusicArtwork(url: MusicAPI.artworkURL(playlist, width: 800), cornerRadius: DT.Radius.md)
                    .frame(maxWidth: 240)
                    .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
                Text(verbatim: playlist.name)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(DT.Color.textPrimary)
                    .multilineTextAlignment(.center)
                MusicPlayShuffleButtons(play: { MusicActions.play(songs) }, shuffle: { MusicActions.shuffle(songs) })
                    .disabled(songs.isEmpty)
                    .padding(.top, DT.Spacing.xs)
            }
            .frame(maxWidth: .infinity)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            if !hasLoaded {
                ProgressView().frame(maxWidth: .infinity).listRowSeparator(.hidden).listRowBackground(Color.clear)
            } else if songs.isEmpty {
                ContentUnavailableView("No Songs", systemImage: "music.note")
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            // By the playlist entry, not the position: after a removal the rows below kept the
            // removed row's place and state.
            ForEach(Array(songs.enumerated()), id: \.element.playlistRowID) { index, song in
                MusicSongRow(song: song, onRemove: { Task { await MusicPlaylistEditor.shared.remove(song, from: playlist) } }) {
                    MusicActions.play(songs, from: index)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .screenBackground()
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu("More", systemImage: "ellipsis") {
                    MusicDownloadButton(songs: { songs }, known: songs)
                }
            }
        }
        .task(id: MusicPlaylistEditor.shared.changeCount) {
            songs = await MusicActions.playlistSongs(playlist)
            hasLoaded = true
        }
    }
}

/// A genre as Apple Music shows one: its colour, its name, and a cover from it tilted into the
/// corner.
private struct MusicGenreTile: View {
    let genre: MusicGenre
    let libraryID: String
    let tint: Color
    @State private var cover: URL?

    var body: some View {
        Color.clear
            .aspectRatio(1.6, contentMode: .fit)
            .background(LinearGradient(colors: [tint, tint.mix(with: .black, by: 0.45)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(alignment: .bottomTrailing) {
                GeometryReader { proxy in
                    let side = proxy.size.height * 0.78
                    MusicArtwork(url: cover, cornerRadius: DT.Radius.xs)
                        .frame(width: side, height: side)
                        .rotationEffect(.degrees(22))
                        .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
                        .position(x: proxy.size.width - side * 0.32, y: proxy.size.height - side * 0.3)
                        .opacity(cover == nil ? 0 : 1)
                }
            }
            .overlay(alignment: .topLeading) {
                Text(verbatim: genre.name)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .padding(DT.Spacing.sm)
            }
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.md, style: .continuous))
            .task(id: genre.id) {
                let id = genre.id, libraryID = libraryID
                let albums = try? await MusicAPI.call {
                    try await $0.getMusicAlbums(credential: $1, authHeader: $2, libraryId: libraryID, sort: .random,
                                                filter: MusicFilter(genreId: id), limit: 1)
                }
                cover = albums?.albums.first.flatMap { MusicAPI.artworkURL($0, width: 300) }
            }
    }
}

private extension MusicSong {
    /// The same song can be in a playlist twice; each entry has its own id.
    var playlistRowID: String { playlistEntryId ?? id }
}
