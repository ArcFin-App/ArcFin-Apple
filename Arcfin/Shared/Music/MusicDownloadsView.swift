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
        } else if state.queued > 0, known.count == 1 {
            Button("Cancel Download", systemImage: "xmark.circle") { downloads.cancel(known) }
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

/// Everything saved for offline listening: what it takes up, what's still downloading, and
/// the albums, laid out like Downloads.
struct MusicDownloadsView: View {
    @State private var confirmRemoveAll = false
    @State private var freeBytes: Int64?
    private var downloads: MusicDownloads { .shared }
    private var allSongs: [MusicSong] { downloads.albums.flatMap(\.songs) }

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 14, alignment: .top)]

    var body: some View {
        Group {
            if downloads.isEmpty && downloads.queue.isEmpty && downloads.failed.isEmpty {
                ContentUnavailableView("No Downloaded Music", systemImage: "arrow.down.circle",
                                       description: Text("Download a song, album or playlist from its menu to listen offline."))
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 28) {
                        storageCard
                        if !downloads.queue.isEmpty || !downloads.failed.isEmpty { downloadingSection }
                        if !downloads.isEmpty { albumsSection }
                    }
                    .padding(.horizontal, DT.Spacing.pagePad)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                    .animation(DT.Animation.standard, value: (downloads.queue + downloads.failed).map(\.id))
                }
            }
        }
        .screenBackground()
        .navigationTitle("Downloaded Music")
        .task(id: downloads.songCount) { freeBytes = StorageManagement.freeBytes() }
        .toolbar {
            if !downloads.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Menu("More", systemImage: "ellipsis") {
                        Button("Shuffle All", systemImage: "shuffle") { MusicActions.shuffle(allSongs) }
                        Button("Remove All Downloads", systemImage: "trash", role: .destructive) { confirmRemoveAll = true }
                    }
                }
            }
        }
        .confirmationDialog("Remove all downloaded music?", isPresented: $confirmRemoveAll, titleVisibility: .visible) {
            Button("Remove All Downloads", role: .destructive) { downloads.removeAll() }
        }
    }

    // MARK: Storage

    private var storageCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "internaldrive.fill")
                    .font(.title3)
                    .foregroundStyle(DT.Color.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Storage")
                        .font(.headline)
                        .foregroundStyle(DT.Color.textPrimary)
                    Text("\(downloads.songCount) songs")
                        .font(.caption)
                        .foregroundStyle(DT.Color.textSecondary)
                }
                Spacer()
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: ByteCountFormatter.string(fromByteCount: downloads.totalBytes, countStyle: .file))
                    .font(.title2.weight(.bold))
                    .foregroundStyle(DT.Color.textPrimary)
                    .contentTransition(.numericText())
                Text("used by music")
                    .font(.subheadline)
                    .foregroundStyle(DT.Color.textSecondary)
                Spacer(minLength: 8)
                if let freeBytes {
                    Text("\(ByteCountFormatter.string(fromByteCount: freeBytes, countStyle: .file)) free on device")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(DT.Color.textSecondary)
                        .multilineTextAlignment(.trailing)
                }
            }
            .accessibilityElement(children: .combine)
            if !downloads.isEmpty {
                MusicPlayShuffleButtons(play: { MusicActions.play(allSongs) }, shuffle: { MusicActions.shuffle(allSongs) })
            }
        }
        .padding(16)
        .background(MusicDownloadsCard())
    }

    // MARK: Downloading

    private var downloadingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                MusicDownloadsHeader(title: "Downloading", count: downloads.queue.count + downloads.failed.count)
                Spacer()
                if !downloads.failed.isEmpty {
                    Button("Retry All") { downloads.retryFailed() }
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.plain)
                        .foregroundStyle(DT.Color.accent)
                        .padding(.trailing, 12)
                }
                Button("Cancel All", role: .destructive) { downloads.cancelAll() }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(DT.Color.accent)
            }
            VStack(spacing: 0) {
                ForEach(Array((downloads.queue + downloads.failed).enumerated()), id: \.element.id) { index, song in
                    if index > 0 {
                        Divider().overlay(DT.Color.textPrimary.opacity(0.06)).padding(.leading, 68)
                    }
                    MusicDownloadingRow(song: song)
                }
            }
            .background(MusicDownloadsCard())
        }
    }

    // MARK: Albums

    private var albumsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            MusicDownloadsHeader(title: "Albums", count: downloads.albums.count)
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(downloads.albums, id: \.songs.first?.id) { group in
                    MusicDownloadedAlbumTile(album: group.album, songs: group.songs)
                }
            }
        }
    }
}

/// The card behind Storage and Downloading, as on Downloads.
private struct MusicDownloadsCard: View {
    var body: some View {
        RoundedRectangle(cornerRadius: DT.Radius.lg, style: .continuous)
            .fill(DT.Color.backgroundSecondary)
            .overlay(RoundedRectangle(cornerRadius: DT.Radius.lg, style: .continuous)
                .stroke(DT.Color.textPrimary.opacity(0.06), lineWidth: 1))
    }
}

private struct MusicDownloadsHeader: View {
    let title: LocalizedStringKey
    let count: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(DT.Font.cardTitle)
                .foregroundStyle(DT.Color.textPrimary)
                .tracking(-0.2)
            Text(verbatim: "\(count)")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(DT.Color.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A song on its way: how far it is, that it's waiting, or that it couldn't be saved.
private struct MusicDownloadingRow: View {
    let song: MusicSong
    private var downloads: MusicDownloads { .shared }

    var body: some View {
        let progress = downloads.progress[song.id]
        let isCurrent = progress != nil
        let hasFailed = downloads.hasFailed(song.id)
        HStack(spacing: 12) {
            MusicArtwork(url: MusicAPI.artworkURL(song, width: 120), cornerRadius: DT.Radius.xs)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: song.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isCurrent ? DT.Color.textPrimary : DT.Color.textSecondary)
                    .lineLimit(1)
                if let progress {
                    ProgressView(value: progress)
                        .tint(DT.Color.accent)
                } else if hasFailed {
                    Label("Couldn't download", systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(DT.Color.palette("F43F5E"))
                } else if downloads.isWaitingForNetwork {
                    Text("Waiting for a connection")
                        .font(.caption)
                        .foregroundStyle(DT.Color.textSecondary)
                } else if downloads.isWaitingForWiFi {
                    Text("Waiting for Wi-Fi")
                        .font(.caption)
                        .foregroundStyle(DT.Color.textSecondary)
                } else {
                    Text("Waiting in queue")
                        .font(.caption)
                        .foregroundStyle(DT.Color.textSecondary)
                }
            }
            if let progress {
                Text(progress, format: .percent.precision(.fractionLength(0)).rounded(rule: .down))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(DT.Color.textSecondary)
                    .contentTransition(.numericText())
            }
            if hasFailed {
                Button { downloads.download([song]) } label: {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .font(.title3)
                        .foregroundStyle(DT.Color.accent)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Retry")
            }
            Button { downloads.cancel([song]) } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(DT.Color.textSecondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel Download")
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .padding(.vertical, 8)
    }
}

/// A saved album: its cover, name, and how many songs and how much space.
private struct MusicDownloadedAlbumTile: View {
    let album: MusicAlbum?
    let songs: [MusicSong]
    private var downloads: MusicDownloads { .shared }

    var body: some View {
        let first = songs.first
        NavigationLink {
            MusicDownloadedAlbumView(album: album, albumID: first?.albumId)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                MusicArtwork(url: album.flatMap { MusicAPI.artworkURL($0) } ?? first.flatMap { MusicAPI.artworkURL($0) })
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: album?.name ?? first?.albumName ?? "")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(DT.Color.textPrimary)
                    Text("\(songs.count) songs · \(ByteCountFormatter.string(fromByteCount: downloads.bytes(of: songs), countStyle: .file))")
                        .font(.footnote)
                        .foregroundStyle(DT.Color.textSecondary)
                }
                .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Play", systemImage: "play") { MusicActions.play(songs) }
            Button("Shuffle", systemImage: "shuffle") { MusicActions.shuffle(songs) }
            Divider()
            Button("Remove Download", systemImage: "trash", role: .destructive) { downloads.remove(songs) }
        }
    }
}

/// One saved album, laid out like its page: the cover, Play and Shuffle, and the saved songs.
/// Hold a song to remove it.
private struct MusicDownloadedAlbumView: View {
    let album: MusicAlbum?
    let albumID: String?
    @Environment(\.dismiss) private var dismiss
    private var downloads: MusicDownloads { .shared }
    private var songs: [MusicSong] { downloads.albums.first { $0.songs.first?.albumId == albumID }?.songs ?? [] }

    var body: some View {
        let first = songs.first
        ScrollView {
            VStack(spacing: DT.Spacing.lg) {
                VStack(spacing: DT.Spacing.xs) {
                    MusicArtwork(url: album.flatMap { MusicAPI.artworkURL($0, width: 800) } ?? first.flatMap { MusicAPI.artworkURL($0, width: 800) },
                                 cornerRadius: DT.Radius.md)
                        .frame(maxWidth: 280)
                        .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
                        .padding(.bottom, DT.Spacing.xs)
                    Text(verbatim: album?.name ?? first?.albumName ?? "")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(DT.Color.textPrimary)
                        .multilineTextAlignment(.center)
                    if let artist = album?.albumArtist ?? first?.albumArtist {
                        Text(verbatim: artist)
                            .font(.title3)
                            .foregroundStyle(DT.Color.accent)
                            .multilineTextAlignment(.center)
                    }
                    Text("\(songs.count) songs · \(ByteCountFormatter.string(fromByteCount: downloads.bytes(of: songs), countStyle: .file))")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(DT.Color.textSecondary)
                }
                .padding(.horizontal, DT.Spacing.pagePad)
                .padding(.top, DT.Spacing.xs)
                MusicPlayShuffleButtons(play: { MusicActions.play(songs) }, shuffle: { MusicActions.shuffle(songs) })
                    .padding(.horizontal, DT.Spacing.pagePad)
                LazyVStack(spacing: 0) {
                    ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                        MusicSongRow(song: song) { MusicActions.play(songs, from: index) }
                            .padding(.horizontal, DT.Spacing.pagePad)
                            .padding(.vertical, 6)
                    }
                }
            }
            .padding(.bottom, DT.Spacing.xl)
        }
        .screenBackground()
        .inlineNavigationTitle()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu("More", systemImage: "ellipsis") {
                    Button("Remove Download", systemImage: "trash", role: .destructive) { downloads.remove(songs) }
                }
            }
        }
        .onChange(of: songs.isEmpty) { _, isEmpty in
            if isEmpty { dismiss() }
        }
    }
}
