// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI
import MediaEngine

/// Every song, with Play and Shuffle above and a sort.
struct MusicSongsView: View {
    let libraryID: String
    @AppStorage("music.songSort") private var sort: MusicSort = .name
    @State private var list: MusicPagedList<MusicSong>?

    var body: some View {
        List {
            if let list {
                MusicPlayShuffleButtons(play: { MusicActions.play(list.items) }, shuffle: { shuffleAll() })
                    .disabled(list.items.isEmpty)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                MusicListState(list: list, empty: "No Songs")
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
        .navigationTitle("Songs")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
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
            let libraryID = libraryID, sort = sort
            let list = MusicPagedList<MusicSong> { start in
                let page = try await MusicAPI.call {
                    try await $0.getMusicTracks(credential: $1, authHeader: $2, libraryId: libraryID, sort: sort,
                                                ascending: sort != .dateAdded && sort != .playCount, startIndex: start)
                }
                return (page.tracks, page.total)
            }
            self.list = list
            await list.loadIfNeeded()
        }
    }

    /// The whole library at random, not only the songs loaded so far.
    private func shuffleAll() {
        let libraryID = libraryID
        Task {
            let page = try? await MusicAPI.call {
                try await $0.getMusicTracks(credential: $1, authHeader: $2, libraryId: libraryID, sort: .random, limit: 300)
            }
            if let songs = page?.tracks, !songs.isEmpty { MusicActions.play(songs) }
        }
    }
}

/// A song in a list: its cover, name and artist, and a menu.
struct MusicSongRow: View {
    let song: MusicSong
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
                if player.current?.id == song.id {
                    MusicPlayingIndicator(isPlaying: player.isPlaying)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .contextMenu { MusicSongMenu(song: song) }
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
                NavigationLink(value: MusicRoute.artist(artist, libraryID: libraryID)) {
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
                NavigationLink(value: MusicRoute.albums(libraryID: libraryID, title: genre.name, genreID: genre.id)) {
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

/// An artist: their picture and name, Play (their most played) and Shuffle, their albums,
/// and what the server knows about them.
struct MusicArtistView: View {
    let libraryID: String?
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var artist: MusicArtist
    @State private var albums: MusicPagedList<MusicAlbum>
    @State private var showsFullBio = false

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
                VStack(spacing: DT.Spacing.sm) {
                    MusicArtwork(url: MusicAPI.artworkURL(artist, width: 600), isCircle: true)
                        .frame(width: 180, height: 180)
                    Text(verbatim: artist.name)
                        .font(.title.weight(.bold))
                        .foregroundStyle(DT.Color.textPrimary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                MusicPlayShuffleButtons(play: { play(shuffled: false) }, shuffle: { play(shuffled: true) })
                VStack(alignment: .leading, spacing: DT.Spacing.sm) {
                    Text("Albums")
                        .font(DT.Font.sectionTitle)
                        .foregroundStyle(DT.Color.textPrimary)
                    MusicListState(list: albums, empty: "No Albums")
                    LazyVGrid(columns: MusicGrid.columns(sizeClass), alignment: .leading, spacing: DT.Spacing.lg) {
                        ForEach(albums.items) { album in
                            MusicAlbumCard(album: album, showsArtist: false)
                                .task { await albums.rowAppeared(album) }
                        }
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
            }
            .padding(.horizontal, DT.Spacing.pagePad)
            .padding(.bottom, DT.Spacing.xl)
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu("More", systemImage: "ellipsis") {
                    Button("Create Station", systemImage: "dot.radiowaves.left.and.right") {
                        let id = artist.id
                        Task { await MusicActions.instantMix(from: id) }
                    }
                }
            }
        }
        .task {
            await albums.loadIfNeeded()
            let id = artist.id
            if let full = try? await MusicAPI.call({ try await $0.getMusicArtist(credential: $1, authHeader: $2, artistId: id) }) {
                artist = full
            }
        }
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
                NavigationLink(value: MusicRoute.playlist(playlist)) {
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
                MusicSongRow(song: song) { MusicActions.play(songs, from: index) }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .task {
            songs = await MusicActions.playlistSongs(playlist)
            hasLoaded = true
        }
    }
}
