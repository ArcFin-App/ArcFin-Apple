// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

/// Download, Downloading or Remove Download for a set of songs, as it stands.
struct MusicDownloadButton: View {
    let songs: () async -> [MusicSong]
    var album: MusicAlbum?
    /// The songs, when the caller already has them, so the button can say how far along it is.
    var known: [MusicSong] = []
    private var downloads: MusicDownloads { .shared }

    var body: some View {
        let state = downloads.state(of: known)
        if !known.isEmpty, state.saved == known.count {
            Button("Remove Download", systemImage: "trash", role: .destructive) { downloads.remove(known) }
        } else if state.queued > 0 {
            Button("Downloading \(state.saved) of \(known.count)", systemImage: "arrow.down.circle.dotted") {}
                .disabled(true)
        } else {
            Button("Download", systemImage: "arrow.down.circle") {
                Task { downloads.download(await songs(), album: album) }
            }
        }
    }
}

/// A small mark on a saved song.
struct MusicDownloadedMark: View {
    let songID: String

    var body: some View {
        if MusicDownloads.shared.isDownloaded(songID) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.caption2)
                .foregroundStyle(DT.Color.textSecondary)
                .accessibilityLabel("Downloaded")
        } else if MusicDownloads.shared.isQueued(songID) {
            ProgressView().controlSize(.mini)
                .accessibilityLabel("Downloading")
        }
    }
}

/// Everything saved for offline listening, by album.
struct MusicDownloadsView: View {
    @State private var confirmRemoveAll = false
    private var downloads: MusicDownloads { .shared }

    var body: some View {
        List {
            if downloads.isEmpty {
                ContentUnavailableView("No Downloaded Music", systemImage: "arrow.down.circle",
                                       description: Text("Download an album or playlist from its menu to listen offline."))
                    .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(downloads.albums, id: \.songs.first?.id) { group in
                        NavigationLink {
                            MusicDownloadedAlbumView(album: group.album, albumID: group.songs.first?.albumId)
                        } label: {
                            HStack(spacing: DT.Spacing.sm) {
                                MusicArtwork(url: group.songs.first?.albumId.flatMap(downloads.coverURL(albumID:)),
                                             cornerRadius: DT.Radius.xs)
                                    .frame(width: 56, height: 56)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(verbatim: group.album?.name ?? group.songs.first?.albumName ?? "")
                                        .foregroundStyle(DT.Color.textPrimary)
                                    Text(verbatim: group.album?.albumArtist ?? group.songs.first?.albumArtist ?? "")
                                        .font(.footnote)
                                        .foregroundStyle(DT.Color.textSecondary)
                                }
                                .lineLimit(1)
                                Spacer()
                                Text("\(group.songs.count) songs")
                                    .font(.footnote)
                                    .foregroundStyle(DT.Color.textSecondary)
                            }
                        }
                        .listRowBackground(Color.clear)
                        .contextMenu {
                            Button("Play", systemImage: "play") { MusicActions.play(group.songs) }
                            Button("Shuffle", systemImage: "shuffle") { MusicActions.shuffle(group.songs) }
                            Button("Remove Download", systemImage: "trash", role: .destructive) { downloads.remove(group.songs) }
                        }
                    }
                } footer: {
                    Text("\(downloads.songCount) songs, \(ByteCountFormatter.string(fromByteCount: downloads.totalBytes, countStyle: .file))")
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("Downloaded Music")
        .toolbar {
            if !downloads.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Menu("More", systemImage: "ellipsis") {
                        Button("Shuffle All", systemImage: "shuffle") { MusicActions.shuffle(downloads.albums.flatMap(\.songs)) }
                        Button("Remove All Downloads", systemImage: "trash", role: .destructive) { confirmRemoveAll = true }
                    }
                }
            }
        }
        .confirmationDialog("Remove all downloaded music?", isPresented: $confirmRemoveAll, titleVisibility: .visible) {
            Button("Remove All Downloads", role: .destructive) { downloads.removeAll() }
        }
    }
}

/// One saved album: Play, Shuffle and its saved songs; swipe or hold one to remove it.
private struct MusicDownloadedAlbumView: View {
    let album: MusicAlbum?
    let albumID: String?
    private var downloads: MusicDownloads { .shared }
    private var songs: [MusicSong] { downloads.albums.first { $0.songs.first?.albumId == albumID }?.songs ?? [] }

    var body: some View {
        List {
            MusicPlayShuffleButtons(play: { MusicActions.play(songs) }, shuffle: { MusicActions.shuffle(songs) })
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                MusicSongRow(song: song) { MusicActions.play(songs, from: index) }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button("Remove Download", systemImage: "trash", role: .destructive) { downloads.remove([song]) }
                    }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle(Text(verbatim: album?.name ?? songs.first?.albumName ?? ""))
    }
}
