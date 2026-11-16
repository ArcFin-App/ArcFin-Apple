// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI
import MediaEngine

/// An album: its cover, name and artist, Play and Shuffle, and the songs by disc.
struct MusicAlbumView: View {
    @State private var album: MusicAlbum
    @State private var songs: [MusicSong] = []
    @State private var hasLoaded = false
    @State private var hasFailed = false

    init(album: MusicAlbum) {
        _album = State(initialValue: album)
    }

    private var discs: [(number: Int, songs: [MusicSong])] {
        Dictionary(grouping: songs) { $0.discNumber ?? 1 }
            .sorted { $0.key < $1.key }
            .map { ($0.key, $0.value) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: DT.Spacing.lg) {
                header
                MusicPlayShuffleButtons(play: { MusicActions.play(songs) }, shuffle: { MusicActions.shuffle(songs) })
                    .disabled(songs.isEmpty)
                    .padding(.horizontal, DT.Spacing.pagePad)
                trackList
                footer
            }
            .padding(.bottom, DT.Spacing.xl)
        }
        .screenBackground()
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                let isFavorite = MusicFavorites.shared.isFavorite(album.id, server: album.isFavorite)
                Button(isFavorite ? "Remove from Favorites" : "Add to Favorites", systemImage: isFavorite ? "star.fill" : "star") {
                    MusicFavorites.shared.toggle(album.id, server: album.isFavorite)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu("More", systemImage: "ellipsis") {
                    MusicAlbumMenu(album: album, showsDownload: false)
                    MusicDownloadButton(songs: { songs }, album: album, known: songs)
                }
            }
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(spacing: DT.Spacing.xs) {
            MusicArtwork(url: MusicAPI.artworkURL(album, width: 800), cornerRadius: DT.Radius.md)
                .frame(maxWidth: 280)
                .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
                .padding(.bottom, DT.Spacing.xs)
            Text(verbatim: album.name)
                .font(.title2.weight(.bold))
                .foregroundStyle(DT.Color.textPrimary)
                .multilineTextAlignment(.center)
            if let artist = album.albumArtist {
                Text(verbatim: artist)
                    .font(.title3)
                    .foregroundStyle(DT.Color.accent)
                    .multilineTextAlignment(.center)
            }
            if let detail {
                Text(verbatim: detail)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(DT.Color.textSecondary)
            }
        }
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.top, DT.Spacing.xs)
    }

    /// Genre · year, as far as the server knows them.
    private var detail: String? {
        let parts = [album.genres.first, album.productionYear.map(String.init)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var trackList: some View {
        if !hasLoaded {
            ProgressView().frame(minHeight: 120)
        } else if songs.isEmpty {
            ContentUnavailableView {
                Label(hasFailed ? "Can’t Load Music" : "No Songs", systemImage: "music.note")
            } actions: {
                if hasFailed { Button("Try Again") { Task { await load() } } }
            }
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(discs, id: \.number) { disc in
                    if discs.count > 1 {
                        Text("Disc \(disc.number)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DT.Color.textSecondary)
                            .padding(.horizontal, DT.Spacing.pagePad)
                            .padding(.top, DT.Spacing.md)
                            .padding(.bottom, DT.Spacing.xxs)
                    }
                    ForEach(disc.songs) { song in
                        MusicAlbumSongRow(song: song, albumArtist: album.albumArtist) {
                            MusicActions.play(songs, from: songs.firstIndex(of: song) ?? 0)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if !songs.isEmpty {
            let minutes = Int((songs.compactMap(\.duration).reduce(0, +) / 60).rounded())
            Text("\(songs.count) songs, \(minutes) minutes")
                .font(.footnote)
                .foregroundStyle(DT.Color.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DT.Spacing.pagePad)
        }
    }

    private func load() async {
        let id = album.id
        do {
            async let tracks = MusicAPI.call { try await $0.getAlbumTracks(credential: $1, authHeader: $2, albumId: id) }
            async let full = MusicAPI.call { try await $0.getMusicAlbum(credential: $1, authHeader: $2, albumId: id) }
            songs = try await tracks
            if let full = try? await full { album = full }
            hasFailed = false
        } catch {
            hasFailed = !(error is CancellationError)
        }
        hasLoaded = true
    }
}

/// One song on an album: its number (or bars while it plays), name, any guest artist, length.
private struct MusicAlbumSongRow: View {
    let song: MusicSong
    let albumArtist: String?
    let play: () -> Void
    private var player: MusicQueuePlayer { AppServices.music.player }

    var body: some View {
        Button(action: play) {
            HStack(spacing: DT.Spacing.sm) {
                Group {
                    if player.current?.id == song.id {
                        MusicPlayingIndicator(isPlaying: player.isPlaying)
                    } else {
                        Text(verbatim: song.trackNumber.map(String.init) ?? "")
                            .foregroundStyle(DT.Color.textSecondary)
                    }
                }
                .font(.body.monospacedDigit())
                .frame(width: 28, alignment: .center)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: song.name)
                        .foregroundStyle(DT.Color.textPrimary)
                        .lineLimit(1)
                    if let artist = song.artistLine, artist != albumArtist {
                        Text(verbatim: artist)
                            .font(.footnote)
                            .foregroundStyle(DT.Color.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: DT.Spacing.xs)
                MusicDownloadedMark(songID: song.id)
                if let duration = song.duration {
                    Text(verbatim: duration.musicTime)
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(DT.Color.textSecondary)
                }
            }
            .padding(.horizontal, DT.Spacing.pagePad)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { MusicSongMenu(song: song) }
        .overlay(alignment: .bottom) {
            Divider().padding(.leading, DT.Spacing.pagePad + 28 + DT.Spacing.sm)
        }
    }
}
