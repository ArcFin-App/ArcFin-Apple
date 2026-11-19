// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI
import MediaEngine

/// Every song, or only the favourites, with Play and Shuffle above and a sort.
struct MusicSongsView: View {
    let libraryID: String
    var favoritesOnly = false
    @AppStorage("music.songSort") private var sort: MusicSort = .name
    @State private var list: MusicPagedList<MusicSong>?

    var body: some View {
        List {
            if let list {
                MusicPlayShuffleButtons(play: { MusicActions.play(list.items) }, shuffle: { shuffleAll() })
                    .disabled(list.items.isEmpty)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                MusicListState(list: list, empty: favoritesOnly ? "No Favorite Songs" : "No Songs")
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
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
            }
        }
        .task(id: sort) {
            let libraryID = libraryID, sort = sort, filter = MusicFilter(favoritesOnly: favoritesOnly)
            let list = MusicPagedList<MusicSong> { start in
                let page = try await MusicAPI.call {
                    try await $0.getMusicTracks(credential: $1, authHeader: $2, libraryId: libraryID, sort: sort,
                                                ascending: sort != .dateAdded && sort != .playCount, filter: filter,
                                                startIndex: start)
                }
                return (page.tracks, page.total)
            }
            self.list = list
            await list.loadIfNeeded()
        }
    }

    /// The whole list at random, not only the songs loaded so far.
    private func shuffleAll() {
        let libraryID = libraryID, filter = MusicFilter(favoritesOnly: favoritesOnly)
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

    var body: some View {
        Button(action: play) {
            HStack(spacing: DT.Spacing.sm) {
                MusicArtwork(url: MusicAPI.artworkURL(song, width: 120), cornerRadius: DT.Radius.xs)
                    .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: song.name)
                        .foregroundStyle(DT.Color.textPrimary)
                    if let artist = song.artistLine {
                        Text(verbatim: artist)
                            .font(.footnote)
                            .foregroundStyle(DT.Color.textSecondary)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: DT.Spacing.xs)
                MusicDownloadedMark(songID: song.id)
                if player.current?.id == song.id {
                    MusicPlayingIndicator(isPlaying: player.isPlaying)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .contextMenu {
            MusicSongMenu(song: song)
            if let onRemove {
                Divider()
                Button("Remove from Playlist", systemImage: "minus.circle", role: .destructive, action: onRemove)
            }
        }
        .swipeActions(edge: .leading) {
            Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") { MusicActions.playNext([song]) }
                .tint(DT.Color.accent)
        }
        .swipeActions(edge: .trailing) {
            Button("Add to Queue", systemImage: "text.line.last.and.arrowtriangle.forward") { MusicActions.addToQueue([song]) }
                .tint(.indigo)
        }
    }
}

/// The library's album artists, A to Z.
struct MusicArtistsView: View {
    let libraryID: String
    @State private var list: MusicPagedList<MusicArtist>

    init(libraryID: String) {
        self.libraryID = libraryID
        _list = State(initialValue: MusicPagedList { start in
            let page = try await MusicAPI.call {
                try await $0.getMusicArtists(credential: $1, authHeader: $2, libraryId: libraryID, startIndex: start)
            }
            return (page.artists, page.total)
        })
    }

    var body: some View {
        List {
            MusicListState(list: list, empty: "No Artists")
                .listRowBackground(Color.clear)
            ForEach(list.items) { artist in
                NavigationLink { MusicDestination(route: MusicRoute.artist(artist, libraryID: libraryID)) } label: {
                    HStack(spacing: DT.Spacing.sm) {
                        MusicArtwork(url: MusicAPI.artworkURL(artist, width: 160), isCircle: true)
                            .frame(width: 48, height: 48)
                        Text(verbatim: artist.name)
                            .foregroundStyle(DT.Color.textPrimary)
                            .lineLimit(1)
                    }
                }
                .listRowBackground(Color.clear)
                .task { await list.rowAppeared(artist) }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("Artists")
        .task { await list.loadIfNeeded() }
    }
}

/// The library's genres; each opens its albums.
struct MusicGenresView: View {
    let libraryID: String
    @State private var list: MusicPagedList<MusicGenre>

    init(libraryID: String) {
        self.libraryID = libraryID
        _list = State(initialValue: MusicPagedList { _ in
            let genres = try await MusicAPI.call { try await $0.getMusicGenres(credential: $1, authHeader: $2, libraryId: libraryID) }
            return (genres, genres.count)
        })
    }

    var body: some View {
        List {
            MusicListState(list: list, empty: "No Genres")
                .listRowBackground(Color.clear)
            ForEach(list.items) { genre in
                NavigationLink { MusicDestination(route: MusicRoute.albums(libraryID: libraryID, title: genre.name, genreID: genre.id)) } label: {
                    Text(verbatim: genre.name)
                        .foregroundStyle(DT.Color.textPrimary)
                }
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("Genres")
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
                // The artist's photo across the top, like an album page, with their name below.
                MusicHero(play: { play(shuffled: false) }, shuffle: { play(shuffled: true) }) { _ in
                    MusicHeroImage(url: MusicAPI.artworkURL(artist, width: 1200))
                } info: {
                    Text(verbatim: artist.name)
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(DT.Color.textPrimary)
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
        .musicHeroBackground(MusicAPI.artworkURL(artist, width: 300))
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu("More", systemImage: "ellipsis") {
                    Button("Create Station", systemImage: "dot.radiowaves.left.and.right") {
                        let id = artist.id
                        Task { await MusicActions.instantMix(from: id) }
                    }
                }
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

    var body: some View {
        List {
            MusicListState(list: list, empty: "No Playlists")
                .listRowBackground(Color.clear)
            ForEach(list.items) { playlist in
                NavigationLink { MusicDestination(route: MusicRoute.playlist(playlist)) } label: {
                    HStack(spacing: DT.Spacing.sm) {
                        MusicArtwork(url: MusicAPI.artworkURL(playlist, width: 160), cornerRadius: DT.Radius.xs)
                            .frame(width: 56, height: 56)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: playlist.name)
                                .foregroundStyle(DT.Color.textPrimary)
                            if let count = playlist.songCount {
                                Text("\(count) songs")
                                    .font(.footnote)
                                    .foregroundStyle(DT.Color.textSecondary)
                            }
                        }
                        .lineLimit(1)
                    }
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
                ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
            } else if songs.isEmpty {
                ContentUnavailableView("No Songs", systemImage: "music.note").listRowBackground(Color.clear)
            }
            ForEach(Array(songs.enumerated()), id: \.offset) { index, song in
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
