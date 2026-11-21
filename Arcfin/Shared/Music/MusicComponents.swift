// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI
import MediaEngine

/// The screen a music link opens. Links carry it rather than a route value: on the Mac a
/// library opens from a binding, and value links inside it can't reach the stack's destinations.
struct MusicDestination: View {
    let route: MusicRoute

    var body: some View {
        switch route {
        case .artists(let library): MusicArtistsView(libraryID: library)
        case .albums(let library, let title, let genre): MusicAlbumsView(libraryID: library, title: title, genreID: genre)
        case .songs(let library): MusicSongsView(libraryID: library)
        case .favorites(let library): MusicSongsView(libraryID: library, favoritesOnly: true)
        case .genres(let library): MusicGenresView(libraryID: library)
        case .playlists: MusicPlaylistsView()
        case .playlist(let playlist): MusicPlaylistView(playlist: playlist)
        case .album(let album): MusicAlbumView(album: album)
        case .artist(let artist, let library): MusicArtistView(artist: artist, libraryID: library)
        }
    }
}

/// Square cover art, or a note on a plain tile when there's none.
struct MusicArtwork: View {
    let url: URL?
    var cornerRadius: CGFloat = DT.Radius.sm
    var isCircle = false

    var body: some View {
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
                                .font(.title2)
                                .foregroundStyle(DT.Color.textSecondary)
                        }
                    }
                }
            }
            .clipShape(isCircle ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: cornerRadius)))
            .overlay {
                (isCircle ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: cornerRadius)))
                    .stroke(DT.Color.textPrimary.opacity(0.08), lineWidth: 0.5)
            }
            .accessibilityHidden(true)
    }
}

/// An album in a grid: its cover, name and artist.
struct MusicAlbumCard: View {
    let album: MusicAlbum
    var showsArtist = true

    var body: some View {
        NavigationLink { MusicDestination(route: MusicRoute.album(album)) } label: {
            VStack(alignment: .leading, spacing: 6) {
                MusicArtwork(url: MusicAPI.artworkURL(album))
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: album.name)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(DT.Color.textPrimary)
                    if showsArtist, let artist = album.albumArtist {
                        Text(verbatim: artist)
                            .font(.footnote)
                            .foregroundStyle(DT.Color.textSecondary)
                    } else if !showsArtist, let year = album.productionYear {
                        Text(verbatim: String(year))
                            .font(.footnote)
                            .foregroundStyle(DT.Color.textSecondary)
                    }
                }
                .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .contextMenu { MusicAlbumMenu(album: album) }
    }
}

/// Play, shuffle and queue a whole album.
struct MusicAlbumMenu: View {
    let album: MusicAlbum
    /// Off on the album's own page, which has a Download button that knows its progress.
    var showsDownload = true

    var body: some View {
        Button("Play", systemImage: "play") { Task { MusicActions.play(await MusicActions.albumSongs(album)) } }
        Button("Shuffle", systemImage: "shuffle") { Task { MusicActions.shuffle(await MusicActions.albumSongs(album)) } }
        Divider()
        Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") {
            Task { MusicActions.playNext(await MusicActions.albumSongs(album)) }
        }
        Button("Play Last", systemImage: "text.line.last.and.arrowtriangle.forward") {
            Task { MusicActions.addToQueue(await MusicActions.albumSongs(album)) }
        }
        MusicAddToPlaylistButton { await MusicActions.albumSongs(album) }
        if showsDownload {
            MusicDownloadButton(songs: { await MusicActions.albumSongs(album) }, album: album)
        }
        Divider()
        Button("Create Station", systemImage: "dot.radiowaves.left.and.right") {
            Task { await MusicActions.instantMix(from: album.id) }
        }
    }
}

/// Play next, add to queue and a station for one song.
/// A song's menu, the same everywhere, in Apple Music's order: what plays it, where it's
/// kept, then where it's from and sharing it.
struct MusicSongMenu: View {
    let song: MusicSong

    var body: some View {
        Section {
            Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") { MusicActions.playNext([song]) }
            Button("Play Last", systemImage: "text.line.last.and.arrowtriangle.forward") { MusicActions.addToQueue([song]) }
        }
        Section {
            MusicAddToPlaylistButton { [song] }
            MusicDownloadButton(songs: { [song] }, known: [song])
            MusicFavoriteButton(id: song.id, server: song.isFavorite)
        }
        Section {
            Button("Create Station", systemImage: "dot.radiowaves.left.and.right") {
                Task { await MusicActions.instantMix(from: song.id) }
            }
            if let albumID = song.albumId {
                NavigationLink {
                    MusicDestination(route: .album(MusicAlbum(id: albumID, name: song.albumName ?? "",
                                                              albumArtist: song.albumArtist)))
                } label: {
                    Label("Go to Album", systemImage: "square.stack")
                }
            }
            if let artist = song.artists.first {
                NavigationLink {
                    MusicDestination(route: .artist(MusicArtist(id: artist.id, name: artist.name), libraryID: nil))
                } label: {
                    Label("Go to Artist", systemImage: "music.microphone")
                }
            }
            ShareLink(item: [song.name, song.artistLine, song.albumName].compactMap { $0 }.joined(separator: " – ")) {
                Label("Share Song", systemImage: "square.and.arrow.up")
            }
        }
    }
}

/// The two wide buttons under an album or a list: Play and Shuffle.
struct MusicPlayShuffleButtons: View {
    let play: () -> Void
    let shuffle: () -> Void

    var body: some View {
        HStack(spacing: DT.Spacing.sm) {
            button("Play", systemImage: "play.fill", action: play)
            button("Shuffle", systemImage: "shuffle", action: shuffle)
        }
    }

    private func button(_ title: LocalizedStringKey, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(DT.Color.accent)
                .background(DT.Color.backgroundTertiary, in: RoundedRectangle(cornerRadius: DT.Radius.md))
                .contentShape(RoundedRectangle(cornerRadius: DT.Radius.md))
        }
        .buttonStyle(.plain)
    }
}

/// Bars that move while this song plays and rest while it's paused.
struct MusicPlayingIndicator: View {
    let isPlaying: Bool

    var body: some View {
        Image(systemName: "waveform")
            .symbolEffect(.variableColor.iterative, isActive: isPlaying)
            .foregroundStyle(DT.Color.accent)
            .accessibilityLabel(isPlaying ? "Playing" : "Paused")
    }
}

/// The loading, empty and failed states every music list shares.
struct MusicListState<Item: Identifiable & Sendable>: View {
    let list: MusicPagedList<Item>
    let empty: LocalizedStringKey

    var body: some View {
        Group {
            if !list.hasLoaded {
                ProgressView().frame(maxWidth: .infinity, minHeight: 200)
            } else if list.items.isEmpty, list.hasFailed {
                ContentUnavailableView {
                    Label("Can’t Load Music", systemImage: "wifi.exclamationmark")
                } actions: {
                    Button("Try Again") { Task { await list.reload() } }
                }
            } else if list.items.isEmpty {
                ContentUnavailableView(empty, systemImage: "music.note")
            }
        }
        // In a list the line under it would start at the centred text, partway across.
        .listRowSeparator(.hidden)
    }
}

/// Columns for a grid of albums: two on iPhone, as many as fit on iPad.
@MainActor
enum MusicGrid {
    static func columns(_ sizeClass: UserInterfaceSizeClass?) -> [GridItem] {
        sizeClass == .regular
            ? [GridItem(.adaptive(minimum: 170), spacing: DT.Spacing.md)]
            : [GridItem(.flexible(), spacing: DT.Spacing.md), GridItem(.flexible(), spacing: DT.Spacing.md)]
    }
}
