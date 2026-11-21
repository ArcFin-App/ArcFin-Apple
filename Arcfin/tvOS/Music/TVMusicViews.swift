// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI
import MediaEngine

extension View {
    func musicDestinations() -> some View {
        navigationDestination(for: MusicRoute.self) { route in
            switch route {
            case .artists(let library): TVMusicArtistsView(libraryID: library)
            case .albums(let library, let title, let genre): TVMusicAlbumsView(libraryID: library, title: title, genreID: genre)
            case .songs(let library): TVMusicSongsView(libraryID: library)
            case .favorites(let library): TVMusicSongsView(libraryID: library, favoritesOnly: true)
            case .genres(let library): TVMusicGenresView(libraryID: library)
            case .playlists: TVMusicPlaylistsView()
            case .playlist(let playlist): TVMusicPlaylistView(playlist: playlist)
            case .album(let album): TVMusicAlbumView(album: album)
            case .artist(let artist, let library): TVMusicArtistView(artist: artist, libraryID: library)
            }
        }
    }
}

/// Playing from the TV opens Now Playing, as the system's own players do.
@MainActor @Observable
final class TVMusicPresenter {
    static let shared = TVMusicPresenter()
    var isShowingNowPlaying = false

    func play(_ songs: [MusicSong], from index: Int = 0) {
        guard !songs.isEmpty else { return }
        MusicActions.play(songs, from: index)
        isShowingNowPlaying = true
    }

    /// Play/Pause on the remote, outside a video: plays or pauses the music and brings Now
    /// Playing up, so the music is always a press away.
    func playPausePressed() {
        guard AppServices.music.isActive else { return }
        AppServices.music.togglePlayPause()
        isShowingNowPlaying = true
    }

    func shuffle(_ songs: [MusicSong]) {
        guard !songs.isEmpty else { return }
        MusicActions.shuffle(songs)
        isShowingNowPlaying = true
    }
}

// MARK: - Pieces

/// Square art that lifts and takes the accent ring when focused.
struct TVMusicArtwork: View {
    let url: URL?
    var isCircle = false
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        let shape = isCircle ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: DT.Radius.card))
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                CachedAsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        ZStack {
                            DT.Color.backgroundTertiary
                            Image(systemName: isCircle ? "music.microphone" : "music.note")
                                .font(.largeTitle)
                                .foregroundStyle(DT.Color.textSecondary)
                        }
                    }
                }
            }
            .clipShape(shape)
            .overlay { shape.stroke(isFocused ? DT.Color.accent : .clear, lineWidth: 4) }
            .shadow(color: isFocused ? DT.Color.accent.opacity(0.4) : .clear, radius: 14)
            .scaleEffect(isFocused ? 1.06 : 1)
            .animation(DT.Animation.fast, value: isFocused)
            .accessibilityHidden(true)
    }
}

/// A tile in a grid or row: art, then a name and a line under it.
struct TVMusicTile: View {
    let url: URL?
    let title: String
    var subtitle: String?
    var isCircle = false
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        VStack(alignment: isCircle ? .center : .leading, spacing: 10) {
            TVMusicArtwork(url: url, isCircle: isCircle)
            VStack(alignment: isCircle ? .center : .leading, spacing: 2) {
                Text(verbatim: title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(isFocused ? DT.Color.accent : DT.Color.textPrimary)
                if let subtitle {
                    Text(verbatim: subtitle)
                        .font(.caption)
                        .foregroundStyle(DT.Color.textSecondary)
                }
            }
            .lineLimit(1)
        }
    }
}

/// A capsule button that fills with the accent when focused.
struct TVMusicPill: View {
    let title: Text
    let systemImage: String
    @Environment(\.isFocused) private var isFocused

    init(title: LocalizedStringKey, systemImage: String) {
        self.title = Text(title)
        self.systemImage = systemImage
    }

    init(verbatim: String, systemImage: String) {
        self.title = Text(verbatim: verbatim)
        self.systemImage = systemImage
    }

    var body: some View {
        Label { title } icon: { Image(systemName: systemImage) }
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
            .foregroundStyle(isFocused ? DT.Color.onAccent : DT.Color.textPrimary)
            .background(isFocused ? DT.Color.accent : DT.Color.backgroundTertiary, in: Capsule())
            .scaleEffect(isFocused ? 1.05 : 1)
            .animation(DT.Animation.fast, value: isFocused)
    }
}

/// Its views left to right, starting a new line when the next one doesn't fit.
struct TVWrapLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map { row in row.reduce(0) { $0 + $1.width } + spacing * CGFloat(max(row.count - 1, 0)) }.max() ?? 0
        let height = rows.map { $0.map(\.height).max() ?? 0 }.reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY, index = 0
        for row in rows(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            let height = row.map(\.height).max() ?? 0
            for size in row {
                subviews[index].place(at: CGPoint(x: x, y: y + (height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
                index += 1
            }
            y += height + spacing
        }
    }

    private func rows(width: CGFloat, subviews: Subviews) -> [[CGSize]] {
        var rows: [[CGSize]] = [], row: [CGSize] = [], used: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if !row.isEmpty, used + spacing + size.width > width {
                rows.append(row)
                row = []
                used = 0
            }
            used += (row.isEmpty ? 0 : spacing) + size.width
            row.append(size)
        }
        if !row.isEmpty { rows.append(row) }
        return rows
    }
}

private struct TVPillButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) { TVMusicPill(title: title, systemImage: systemImage) }
            .buttonStyle(TVCardButtonStyle())
            .focusEffectDisabled()
    }
}

/// A song in a list: its number or cover, name, artist and length; the playing one marked.
struct TVMusicSongRow: View {
    let song: MusicSong
    var number: Int?
    var showsArtwork = false
    var removeTitle: LocalizedStringKey = "Remove from Playlist"
    var onRemove: (() -> Void)?
    let play: () -> Void

    var body: some View {
        Button(action: play) { Label(song: song, number: number, showsArtwork: showsArtwork) }
            .buttonStyle(TVCardButtonStyle())
            .focusEffectDisabled()
            .contextMenu {
                Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") { MusicActions.playNext([song]) }
                Button("Play Last", systemImage: "text.line.last.and.arrowtriangle.forward") { MusicActions.addToQueue([song]) }
                MusicFavoriteButton(id: song.id, server: song.isFavorite)
                MusicAddToPlaylistButton { [song] }
                if let onRemove {
                    Button(removeTitle, systemImage: "minus.circle", role: .destructive, action: onRemove)
                }
                Button("Create Station", systemImage: "dot.radiowaves.left.and.right") {
                    Task {
                        await MusicActions.instantMix(from: song.id)
                        TVMusicPresenter.shared.isShowingNowPlaying = true
                    }
                }
            }
    }

    private struct Label: View {
        let song: MusicSong
        let number: Int?
        let showsArtwork: Bool
        @Environment(\.isFocused) private var isFocused
        private var player: MusicQueuePlayer { AppServices.music.player }

        var body: some View {
            HStack(spacing: 24) {
                if showsArtwork {
                    TVMusicArtwork(url: MusicAPI.artworkURL(song, width: 160)).frame(width: 72, height: 72)
                } else {
                    Group {
                        if player.current?.id == song.id {
                            Image(systemName: "waveform")
                                .symbolEffect(.variableColor.iterative, isActive: player.isPlaying)
                        } else {
                            Text(verbatim: number.map(String.init) ?? "")
                        }
                    }
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(isFocused ? DT.Color.onAccent : DT.Color.textSecondary)
                    .frame(width: 48)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: song.name).font(.callout)
                    if showsArtwork, let artist = song.artistLine {
                        Text(verbatim: artist).font(.caption)
                            .foregroundStyle(isFocused ? DT.Color.onAccent.opacity(0.8) : DT.Color.textSecondary)
                    }
                }
                .lineLimit(1)
                Spacer()
                if let duration = song.duration {
                    Text(verbatim: duration.musicTime)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(isFocused ? DT.Color.onAccent.opacity(0.8) : DT.Color.textSecondary)
                }
            }
            .foregroundStyle(isFocused ? DT.Color.onAccent : DT.Color.textPrimary)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(isFocused ? DT.Color.accent : .clear, in: RoundedRectangle(cornerRadius: DT.Radius.md))
            .scaleEffect(isFocused ? 1.02 : 1)
            .animation(DT.Animation.fast, value: isFocused)
        }
    }
}

private struct TVMusicLoading<Item: Identifiable & Sendable>: View {
    let list: MusicPagedList<Item>
    let empty: LocalizedStringKey

    var body: some View {
        if !list.hasLoaded {
            ProgressView().frame(maxWidth: .infinity, minHeight: 300)
        } else if list.items.isEmpty {
            ContentUnavailableView(list.hasFailed ? "Can’t Load Music" : empty, systemImage: "music.note")
                .frame(maxWidth: .infinity, minHeight: 300)
        }
    }
}

private let albumColumns = [GridItem(.adaptive(minimum: 260), spacing: 48)]

private struct TVAlbumGrid: View {
    let list: MusicPagedList<MusicAlbum>
    var showsArtist = true
    /// On a screen with nothing else to focus, the first album takes focus once it loads.
    var claimsFocus = false
    @FocusState private var focused: String?

    var body: some View {
        LazyVGrid(columns: albumColumns, alignment: .leading, spacing: 56) {
            ForEach(list.items) { album in
                NavigationLink(value: MusicRoute.album(album)) {
                    TVMusicTile(url: MusicAPI.artworkURL(album, width: 520), title: album.name,
                                subtitle: showsArtist ? album.albumArtist : album.productionYear.map(String.init))
                }
                .buttonStyle(TVCardButtonStyle())
                .focusEffectDisabled()
                .contextMenu {
                    Button("Play", systemImage: "play") { Task { TVMusicPresenter.shared.play(await MusicActions.albumSongs(album)) } }
                    Button("Shuffle", systemImage: "shuffle") { Task { TVMusicPresenter.shared.shuffle(await MusicActions.albumSongs(album)) } }
                    Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") {
                        Task { MusicActions.playNext(await MusicActions.albumSongs(album)) }
                    }
                    Button("Play Last", systemImage: "text.line.last.and.arrowtriangle.forward") {
                        Task { MusicActions.addToQueue(await MusicActions.albumSongs(album)) }
                    }
                    MusicAddToPlaylistButton { await MusicActions.albumSongs(album) }
                }
                .focused($focused, equals: album.id)
                .task { await list.rowAppeared(album) }
            }
        }
        .focusSection()
        .onChange(of: list.items.first?.id) { _, first in
            if claimsFocus, focused == nil { focused = first }
        }
    }
}

/// Focus for a screen whose only focusable things arrive with its list: the first one, once it does.
private struct TVClaimFirstFocus<ID: Hashable>: ViewModifier {
    let first: ID?
    let focus: FocusState<ID?>.Binding

    func body(content: Content) -> some View {
        content.onChange(of: first) { _, first in
            if focus.wrappedValue == nil { focus.wrappedValue = first }
        }
    }
}

// MARK: - Library

/// A music library: Now Playing when there's music, the sections, then what was added lately.
struct TVMusicLibraryView: View {
    let library: JellyfinLibrary
    @State private var recent: MusicPagedList<MusicAlbum>
    @State private var recentlyPlayed: MusicPagedList<MusicSong>
    @State private var mostPlayed: MusicPagedList<MusicSong>

    init(library: JellyfinLibrary) {
        self.library = library
        let id = library.id
        _recentlyPlayed = State(initialValue: TVMusicSongShelf.list(libraryID: id, sort: .datePlayed))
        _mostPlayed = State(initialValue: TVMusicSongShelf.list(libraryID: id, sort: .playCount))
        _recent = State(initialValue: MusicPagedList { _ in
            let page = try await MusicAPI.call {
                try await $0.getMusicAlbums(credential: $1, authHeader: $2, libraryId: id, sort: .dateAdded,
                                            ascending: false, limit: 40)
            }
            return (page.albums, page.albums.count)
        })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 56) {
                // Onto a second or third line where the screen's too narrow for one.
                TVWrapLayout(spacing: 24) {
                    NavigationLink { TVMusicSearchView() } label: {
                        TVMusicPill(title: "Search", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(TVCardButtonStyle())
                    .focusEffectDisabled()
                    link("Favorites", systemImage: "star", route: .favorites(libraryID: library.id))
                    link("Playlists", systemImage: "music.note.list", route: .playlists)
                    link("Artists", systemImage: "music.microphone", route: .artists(libraryID: library.id))
                    link("Albums", systemImage: "square.stack", route: .albums(libraryID: library.id, title: String(localized: "Albums")))
                    link("Songs", systemImage: "music.note", route: .songs(libraryID: library.id))
                    link("Genres", systemImage: "guitars", route: .genres(libraryID: library.id))
                }
                .focusSection()
                TVMusicSmartPlaylistShelf(libraryID: library.id)
                TVMusicSongShelf(title: "Recently Played", list: recentlyPlayed)
                TVMusicSongShelf(title: "Most Played", list: mostPlayed)
                VStack(alignment: .leading, spacing: 24) {
                    Text("Recently Added").font(.title3.weight(.semibold))
                    TVMusicLoading(list: recent, empty: "No Albums")
                    TVAlbumGrid(list: recent)
                }
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 48)
        }
        .screenBackground()
        .task {
            async let albums: Void = recent.loadIfNeeded()
            async let played: Void = recentlyPlayed.loadIfNeeded()
            async let most: Void = mostPlayed.loadIfNeeded()
            _ = await (albums, played, most)
        }
    }

    private func link(_ title: LocalizedStringKey, systemImage: String, route: MusicRoute) -> some View {
        NavigationLink(value: route) { TVMusicPill(title: title, systemImage: systemImage) }
            .buttonStyle(TVCardButtonStyle())
            .focusEffectDisabled()
    }
}

/// A row of songs this profile has played; choosing one plays the row from there.
/// Made for You: each smart playlist plays as soon as it's picked.
private struct TVMusicSmartPlaylistShelf: View {
    let libraryID: String

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Made for You").font(.title3.weight(.semibold))
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 40) {
                    ForEach(MusicSmartPlaylist.allCases) { playlist in
                        Button {
                            Task {
                                let songs = await playlist.songs(libraryID: libraryID)
                                if !songs.isEmpty { TVMusicPresenter.shared.play(songs, from: 0) }
                            }
                        } label: {
                            TVSmartPlaylistCard(playlist: playlist, libraryID: libraryID)
                        }
                        .buttonStyle(TVCardButtonStyle())
                        .focusEffectDisabled()
                    }
                }
                .padding(.vertical, 20)
            }
            .scrollClipDisabled()
        }
        .focusSection()
    }
}

/// A Made for You cover, ringed and lifted when focused like the other tiles.
private struct TVSmartPlaylistCard: View {
    let playlist: MusicSmartPlaylist
    let libraryID: String
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DT.Radius.card, style: .continuous)
        VStack(alignment: .leading, spacing: 12) {
            // Plain images: the artwork view's own focus ring would light each cover.
            MusicSmartPlaylistArt(playlist: playlist, libraryID: libraryID, side: 240) { url in
                CachedAsyncImage(url: url) { phase in
                    if case .success(let image) = phase { image.resizable().scaledToFill() } else { Color.clear }
                }
            }
            .clipShape(shape)
            .overlay { shape.stroke(isFocused ? DT.Color.accent : .clear, lineWidth: 4) }
            .shadow(color: isFocused ? DT.Color.accent.opacity(0.4) : .clear, radius: 14)
            .scaleEffect(isFocused ? 1.06 : 1)
            .animation(DT.Animation.fast, value: isFocused)
            Text(playlist.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
        .frame(width: 240, alignment: .leading)
    }
}

private struct TVMusicSongShelf: View {
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
            VStack(alignment: .leading, spacing: 24) {
                Text(title).font(.title3.weight(.semibold))
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 40) {
                        ForEach(Array(list.items.enumerated()), id: \.element.id) { index, song in
                            Button { TVMusicPresenter.shared.play(list.items, from: index) } label: {
                                TVMusicTile(url: MusicAPI.artworkURL(song, width: 400), title: song.name, subtitle: song.artistLine)
                                    .frame(width: 240)
                            }
                            .buttonStyle(TVCardButtonStyle())
                            .focusEffectDisabled()
                        }
                    }
                    .padding(.vertical, 20)
                }
                .scrollClipDisabled()
            }
            .focusSection()
        }
    }
}

struct TVMusicAlbumsView: View {
    let libraryID: String
    let title: String
    let genreID: String?
    @State private var list: MusicPagedList<MusicAlbum>

    init(libraryID: String, title: String, genreID: String?) {
        self.libraryID = libraryID
        self.title = title
        self.genreID = genreID
        let filter = MusicFilter(genreId: genreID)
        _list = State(initialValue: MusicPagedList { start in
            let page = try await MusicAPI.call {
                try await $0.getMusicAlbums(credential: $1, authHeader: $2, libraryId: libraryID, filter: filter, startIndex: start)
            }
            return (page.albums, page.total)
        })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                Text(verbatim: title).font(.title2.weight(.bold))
                TVMusicLoading(list: list, empty: "No Albums")
                TVAlbumGrid(list: list, claimsFocus: true)
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 48)
        }
        .screenBackground()
        .task { await list.loadIfNeeded() }
    }
}

struct TVMusicArtistsView: View {
    let libraryID: String
    @State private var list: MusicPagedList<MusicArtist>
    @FocusState private var focused: String?

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
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                Text("Artists").font(.title2.weight(.bold))
                TVMusicLoading(list: list, empty: "No Artists")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 48)], spacing: 56) {
                    ForEach(list.items) { artist in
                        NavigationLink(value: MusicRoute.artist(artist, libraryID: libraryID)) {
                            TVMusicTile(url: MusicAPI.artworkURL(artist, width: 440), title: artist.name, isCircle: true)
                        }
                        .buttonStyle(TVCardButtonStyle())
                        .focusEffectDisabled()
                        .focused($focused, equals: artist.id)
                        .task { await list.rowAppeared(artist) }
                    }
                }
                .focusSection()
                .modifier(TVClaimFirstFocus(first: list.items.first?.id, focus: $focused))
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 48)
        }
        .screenBackground()
        .task { await list.loadIfNeeded() }
    }
}

struct TVMusicGenresView: View {
    let libraryID: String
    @State private var list: MusicPagedList<MusicGenre>
    @FocusState private var focused: String?

    init(libraryID: String) {
        self.libraryID = libraryID
        _list = State(initialValue: MusicPagedList { _ in
            let genres = try await MusicAPI.call { try await $0.getMusicGenres(credential: $1, authHeader: $2, libraryId: libraryID) }
            return (genres, genres.count)
        })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                Text("Genres").font(.title2.weight(.bold))
                TVMusicLoading(list: list, empty: "No Genres")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 32)], alignment: .leading, spacing: 32) {
                    ForEach(list.items) { genre in
                        NavigationLink(value: MusicRoute.albums(libraryID: libraryID, title: genre.name, genreID: genre.id)) {
                            TVMusicPill(verbatim: genre.name, systemImage: "guitars")
                        }
                        .buttonStyle(TVCardButtonStyle())
                        .focusEffectDisabled()
                        .focused($focused, equals: genre.id)
                    }
                }
                .focusSection()
                .modifier(TVClaimFirstFocus(first: list.items.first?.id, focus: $focused))
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 48)
        }
        .screenBackground()
        .task { await list.loadIfNeeded() }
    }
}

struct TVMusicPlaylistsView: View {
    @FocusState private var focused: String?
    @State private var list = MusicPagedList<MusicPlaylist> { _ in
        let playlists = try await MusicAPI.call { try await $0.getMusicPlaylists(credential: $1, authHeader: $2) }
        return (playlists, playlists.count)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                Text("Playlists").font(.title2.weight(.bold))
                TVMusicLoading(list: list, empty: "No Playlists")
                LazyVGrid(columns: albumColumns, alignment: .leading, spacing: 56) {
                    ForEach(list.items) { playlist in
                        NavigationLink(value: MusicRoute.playlist(playlist)) {
                            TVMusicTile(url: MusicAPI.artworkURL(playlist, width: 520), title: playlist.name,
                                        subtitle: playlist.songCount.map { String(localized: "\($0) songs") })
                        }
                        .buttonStyle(TVCardButtonStyle())
                        .focusEffectDisabled()
                        .focused($focused, equals: playlist.id)
                    }
                }
                .focusSection()
                .modifier(TVClaimFirstFocus(first: list.items.first?.id, focus: $focused))
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 48)
        }
        .screenBackground()
        .task { await list.loadIfNeeded() }
    }
}

// MARK: - Album, playlist, songs

/// The cover and Play and Shuffle on the left, the songs on the right.
private struct TVMusicSongPage<Header: View>: View {
    let artworkURL: URL?
    let songs: [MusicSong]
    let hasLoaded: Bool
    var numbered = true
    var onRemove: ((MusicSong) -> Void)?
    @ViewBuilder let header: () -> Header

    var body: some View {
        HStack(alignment: .top, spacing: 80) {
            VStack(alignment: .leading, spacing: 24) {
                TVMusicArtwork(url: artworkURL).frame(width: 460, height: 460).focusable(false)
                header()
                HStack(spacing: 24) {
                    TVPillButton(title: "Play", systemImage: "play.fill") { TVMusicPresenter.shared.play(songs) }
                    TVPillButton(title: "Shuffle", systemImage: "shuffle") { TVMusicPresenter.shared.shuffle(songs) }
                }
                .focusSection()
            }
            .frame(width: 460)
            ScrollView {
                LazyVStack(spacing: 4) {
                    if !hasLoaded {
                        ProgressView().frame(maxWidth: .infinity, minHeight: 300)
                    } else if songs.isEmpty {
                        ContentUnavailableView("No Songs", systemImage: "music.note")
                    }
                    ForEach(Array(songs.enumerated()), id: \.offset) { index, song in
                        TVMusicSongRow(song: song, number: numbered ? (song.trackNumber ?? index + 1) : nil, showsArtwork: !numbered,
                                       onRemove: onRemove.map { remove in { remove(song) } }) {
                            TVMusicPresenter.shared.play(songs, from: index)
                        }
                    }
                }
                .padding(.vertical, 24)
            }
            .focusSection()
        }
        .padding(.horizontal, 80)
        .padding(.vertical, 48)
        .screenBackground()
    }
}

struct TVMusicAlbumView: View {
    let album: MusicAlbum
    @State private var songs: [MusicSong] = []
    @State private var hasLoaded = false

    var body: some View {
        TVMusicSongPage(artworkURL: MusicAPI.artworkURL(album, width: 920), songs: songs, hasLoaded: hasLoaded) {
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: album.name).font(.title2.weight(.bold)).lineLimit(2)
                if let artist = album.albumArtist {
                    Text(verbatim: artist).font(.title3).foregroundStyle(DT.Color.accent)
                }
                let detail = [album.genres.first, album.productionYear.map(String.init)].compactMap { $0 }
                if !detail.isEmpty {
                    Text(verbatim: detail.joined(separator: " · ")).font(.caption).foregroundStyle(DT.Color.textSecondary)
                }
            }
        }
        .task {
            songs = await MusicActions.albumSongs(album)
            hasLoaded = true
        }
    }
}

/// A playlist: its songs in order; hold one to remove it.
struct TVMusicPlaylistView: View {
    let playlist: MusicPlaylist
    @State private var songs: [MusicSong] = []
    @State private var hasLoaded = false

    var body: some View {
        TVMusicSongPage(artworkURL: MusicAPI.artworkURL(playlist, width: 800), songs: songs, hasLoaded: hasLoaded,
                        numbered: false, onRemove: { song in Task { await MusicPlaylistEditor.shared.remove(song, from: playlist) } }) {
            Text(verbatim: playlist.name).font(.title2.weight(.bold)).lineLimit(2)
        }
        .task(id: MusicPlaylistEditor.shared.changeCount) {
            songs = await MusicActions.playlistSongs(playlist)
            hasLoaded = true
        }
    }
}

struct TVMusicSongsView: View {
    let libraryID: String
    let favoritesOnly: Bool
    @State private var list: MusicPagedList<MusicSong>

    init(libraryID: String, favoritesOnly: Bool = false) {
        self.libraryID = libraryID
        self.favoritesOnly = favoritesOnly
        let filter = MusicFilter(favoritesOnly: favoritesOnly)
        _list = State(initialValue: MusicPagedList { start in
            let page = try await MusicAPI.call {
                try await $0.getMusicTracks(credential: $1, authHeader: $2, libraryId: libraryID, filter: filter, startIndex: start)
            }
            return (page.tracks, page.total)
        })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 24) {
                    Text(favoritesOnly ? "Favorite Songs" : "Songs").font(.title2.weight(.bold))
                    Spacer()
                    TVPillButton(title: "Play", systemImage: "play.fill") { TVMusicPresenter.shared.play(list.items) }
                    TVPillButton(title: "Shuffle", systemImage: "shuffle") { shuffleAll() }
                }
                .focusSection()
                TVMusicLoading(list: list, empty: favoritesOnly ? "No Favorite Songs" : "No Songs")
                LazyVStack(spacing: 4) {
                    ForEach(Array(list.items.enumerated()), id: \.element.id) { index, song in
                        TVMusicSongRow(song: song, showsArtwork: true) { TVMusicPresenter.shared.play(list.items, from: index) }
                            .task { await list.rowAppeared(song) }
                    }
                }
                .focusSection()
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 48)
        }
        .screenBackground()
        .task { await list.loadIfNeeded() }
    }

    private func shuffleAll() {
        let libraryID = libraryID, filter = MusicFilter(favoritesOnly: favoritesOnly)
        Task {
            let page = try? await MusicAPI.call {
                try await $0.getMusicTracks(credential: $1, authHeader: $2, libraryId: libraryID, sort: .random,
                                            filter: filter, limit: 300)
            }
            TVMusicPresenter.shared.play(page?.tracks ?? [])
        }
    }
}

struct TVMusicArtistView: View {
    let libraryID: String?
    @State private var artist: MusicArtist
    @State private var albums: MusicPagedList<MusicAlbum>
    @State private var topSongs: MusicPagedList<MusicSong>

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
        _topSongs = State(initialValue: MusicPagedList { _ in
            let page = try await MusicAPI.call {
                try await $0.getMusicTracks(credential: $1, authHeader: $2, libraryId: libraryID, sort: .playCount,
                                            ascending: false, filter: filter, limit: 10)
            }
            return (page.tracks, page.tracks.count)
        })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 48) {
                HStack(spacing: 48) {
                    TVMusicArtwork(url: MusicAPI.artworkURL(artist, width: 600), isCircle: true)
                        .frame(width: 280, height: 280)
                    VStack(alignment: .leading, spacing: 24) {
                        Text(verbatim: artist.name).font(.largeTitle.weight(.bold))
                        if let overview = artist.overview, !overview.isEmpty {
                            Text(verbatim: overview)
                                .font(.callout)
                                .foregroundStyle(DT.Color.textSecondary)
                                .lineLimit(3)
                                .frame(maxWidth: 1000, alignment: .leading)
                        }
                        HStack(spacing: 24) {
                            TVPillButton(title: "Play", systemImage: "play.fill") { play(shuffled: false) }
                            TVPillButton(title: "Shuffle", systemImage: "shuffle") { play(shuffled: true) }
                            TVPillButton(title: "Create Station", systemImage: "dot.radiowaves.left.and.right") {
                                let id = artist.id
                                Task {
                                    await MusicActions.instantMix(from: id)
                                    TVMusicPresenter.shared.isShowingNowPlaying = true
                                }
                            }
                        }
                        .focusSection()
                    }
                }
                TVMusicSongShelf(title: "Top Songs", list: topSongs)
                VStack(alignment: .leading, spacing: 24) {
                    Text("Albums").font(.title3.weight(.semibold))
                    TVMusicLoading(list: albums, empty: "No Albums")
                    TVAlbumGrid(list: albums, showsArtist: false)
                }
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 48)
        }
        .screenBackground()
        .task {
            async let top: Void = topSongs.loadIfNeeded()
            await albums.loadIfNeeded()
            _ = await top
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
            TVMusicPresenter.shared.play(page?.tracks ?? [])
        }
    }
}

// MARK: - Search

/// Searching the music on its own, from the music library.
struct TVMusicSearchView: View {
    @State private var query = ""
    @State private var search = MusicSearchModel()

    var body: some View {
        ScrollView {
            if search.isSearching {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 120)
            } else if search.results.isEmpty, query.trimmingCharacters(in: .whitespaces).count >= 2 {
                ContentUnavailableView.search(text: query).padding(.vertical, 80)
            } else {
                TVMusicSearchSection(results: search.results)
                    .padding(.horizontal, 80)
                    .padding(.vertical, 48)
            }
        }
        .screenBackground()
        .searchable(text: $query, prompt: "Artists, albums and songs")
        .onChange(of: query) { _, term in search.search(term) }
    }
}

/// Music in search on Apple TV: rows of artists and albums, then songs.
struct TVMusicSearchSection: View {
    let results: MusicSearchResults

    var body: some View {
        VStack(alignment: .leading, spacing: 48) {
            if !results.artists.isEmpty {
                row("Artists") {
                    ForEach(results.artists) { artist in
                        NavigationLink(value: MusicRoute.artist(artist, libraryID: nil)) {
                            TVMusicTile(url: MusicAPI.artworkURL(artist, width: 400), title: artist.name, isCircle: true)
                                .frame(width: 200)
                        }
                        .buttonStyle(TVCardButtonStyle())
                        .focusEffectDisabled()
                    }
                }
            }
            if !results.albums.isEmpty {
                row("Albums") {
                    ForEach(results.albums) { album in
                        NavigationLink(value: MusicRoute.album(album)) {
                            TVMusicTile(url: MusicAPI.artworkURL(album, width: 480), title: album.name, subtitle: album.albumArtist)
                                .frame(width: 240)
                        }
                        .buttonStyle(TVCardButtonStyle())
                        .focusEffectDisabled()
                    }
                }
            }
            if !results.songs.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Songs").font(.title3.weight(.semibold)).padding(.horizontal, DT.Spacing.pagePad)
                    VStack(spacing: 4) {
                        ForEach(Array(results.songs.prefix(8).enumerated()), id: \.element.id) { index, song in
                            TVMusicSongRow(song: song, showsArtwork: true) { TVMusicPresenter.shared.play(results.songs, from: index) }
                        }
                    }
                    .padding(.horizontal, DT.Spacing.pagePad)
                }
                .focusSection()
            }
        }
    }

    private func row<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.title3.weight(.semibold)).padding(.horizontal, DT.Spacing.pagePad)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 40) { content() }
                    .padding(.horizontal, DT.Spacing.pagePad)
                    .padding(.vertical, 24)
            }
        }
        .focusSection()
    }
}
