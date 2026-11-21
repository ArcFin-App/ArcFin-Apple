// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import WatchKit

/// Music on the watch: what's kept here, the profile's favourites, and its playlists.
struct WatchMusicView: View {
    @Environment(WatchMusicPlayer.self) private var player
    @State private var playlists: [WatchPlaylist] = []
    @State private var cannotReach = false
    private var downloads: WatchMusicDownloads { .shared }
    private var client: WatchJellyfin? { WatchSignIn.shared.credential.map(WatchJellyfin.init) }

    var body: some View {
        List {
            if player.current != nil {
                NavigationLink { WatchKit.NowPlayingView() } label: {
                    Label("Now Playing", systemImage: "waveform")
                }
            }
            if let problem = player.problem {
                Text(problem).font(.footnote).foregroundStyle(.secondary)
            }
            if !downloads.playlists.isEmpty {
                Section("On This Watch") {
                    ForEach(downloads.playlists) { playlist in
                        NavigationLink { WatchPlaylistView(playlist: playlist) } label: {
                            Label(playlist.name, systemImage: "arrow.down.circle.fill")
                        }
                    }
                }
            }
            if client != nil {
                Section {
                    NavigationLink { WatchPlaylistView(playlist: WatchPlaylistView.favorites) } label: {
                        Label("Favorite Songs", systemImage: "star.fill")
                    }
                    ForEach(playlists) { playlist in
                        NavigationLink { WatchPlaylistView(playlist: playlist) } label: {
                            Text(verbatim: playlist.name)
                        }
                    }
                    if cannotReach { Text("Can’t Reach Your Server").font(.footnote).foregroundStyle(.secondary) }
                } header: {
                    Text("Playlists")
                }
            } else if downloads.playlists.isEmpty {
                Text("Open Arcfin on your iPhone and sign in to play music here.").font(.footnote)
            }
        }
        .navigationTitle("Music")
        .task {
            guard let client else { return }
            do {
                playlists = try await client.playlists()
                cannotReach = false
            } catch {
                cannotReach = true
            }
        }
    }
}

/// A playlist's songs, to play or shuffle here, and keep on the watch.
struct WatchPlaylistView: View {
    /// Favorite Songs, listed like a playlist; it isn't kept on the watch.
    static let favorites = WatchPlaylist(id: "favorites", name: String(localized: "Favorite Songs"), songCount: nil)

    let playlist: WatchPlaylist
    @Environment(WatchMusicPlayer.self) private var player
    @State private var songs: [WatchSong] = []
    @State private var hasLoaded = false
    private var downloads: WatchMusicDownloads { .shared }
    private var client: WatchJellyfin? { WatchSignIn.shared.credential.map(WatchJellyfin.init) }
    private var isFavorites: Bool { playlist.id == Self.favorites.id }

    var body: some View {
        List {
            Section {
                Button("Play", systemImage: "play.fill") { Task { await player.play(songs, using: client) } }
                Button("Shuffle", systemImage: "shuffle") { Task { await player.play(songs, shuffled: true, using: client) } }
                if !isFavorites { keepButton }
            }
            .disabled(songs.isEmpty)
            if !hasLoaded {
                ProgressView()
            }
            ForEach(Array(songs.enumerated()), id: \.element.id) { offset, song in
                Button { Task { await player.play(songs, from: offset, using: client) } } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: song.name).lineLimit(2)
                        if let artist = song.artist {
                            Text(verbatim: artist).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
            }
        }
        .navigationTitle(Text(verbatim: playlist.name))
        .task { await load() }
    }

    @ViewBuilder
    private var keepButton: some View {
        if let downloading = downloads.downloading, downloading.id == playlist.id {
            ProgressView(value: downloading.progress) { Text("Downloading") }
        } else if downloads.isKept(playlist) {
            Button("Remove from Watch", systemImage: "trash", role: .destructive) { downloads.remove(playlist) }
        } else if let client {
            Button("Keep on Watch", systemImage: "arrow.down.circle") {
                Task { await downloads.keep(playlist, songs: songs, using: client) }
            }
            .disabled(downloads.downloading != nil)
        }
    }

    /// From the server when it answers; the kept copy otherwise.
    private func load() async {
        defer { hasLoaded = true }
        if let client {
            let fetched = try? await (isFavorites ? client.favoriteSongs() : client.songs(inPlaylist: playlist.id))
            if let fetched { return songs = fetched }
        }
        songs = downloads.songs(in: playlist)
    }
}
