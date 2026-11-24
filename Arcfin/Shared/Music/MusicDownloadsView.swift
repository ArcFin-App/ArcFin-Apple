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

/// Download, Downloading or Remove Download for everything an artist made, judged by the
/// albums on their page.
struct MusicArtistDownloadButton: View {
    let artist: MusicArtist
    let albums: [MusicAlbum]
    /// Asks first: it can queue the artist's whole catalogue. Shown by the page, as the button
    /// sits in a menu.
    let confirmDownloadAll: () -> Void
    private var downloads: MusicDownloads { .shared }

    var body: some View {
        let ids = Set(albums.map(\.id))
        let saved = downloads.savedSongs(inAlbums: ids)
        let expected = albums.reduce(0) { $0 + ($1.trackCount ?? 0) }
        if downloads.myQueue.contains(where: { $0.albumId.map(ids.contains) ?? false }) {
            Button("Downloading", systemImage: "arrow.down.circle.dotted") {}
                .disabled(true)
        } else if !albums.isEmpty, expected > 0, saved.count >= expected {
            Button("Remove Download", systemImage: "trash", role: .destructive) { downloads.remove(saved) }
        } else {
            Button("Download All Albums", systemImage: "arrow.down.circle", action: confirmDownloadAll)
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
    @State private var confirmCancelAll = false
    @State private var freeBytes: Int64?
    private var downloads: MusicDownloads { .shared }
    private var allSongs: [MusicSong] { downloads.albums.flatMap(\.songs) }

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 220), spacing: 14, alignment: .top)]

    var body: some View {
        Group {
            if downloads.isEmpty && downloads.myQueue.isEmpty && downloads.myFailed.isEmpty {
                ContentUnavailableView("No Downloaded Music", systemImage: "arrow.down.circle",
                                       description: Text("Download a song, album or playlist from its menu to listen offline."))
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 28) {
                        storageCard
                        if !downloads.myQueue.isEmpty || !downloads.myFailed.isEmpty { downloadingSection }
                        if !downloads.isEmpty { albumsSection }
                    }
                    .padding(.horizontal, DT.Spacing.pagePad)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                    .animation(DT.Animation.standard, value: (downloads.myQueue + downloads.myFailed).map(\.id))
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
        .confirmationDialog(Text("Cancel all \(downloads.myQueue.count + downloads.myFailed.count) downloads?"),
                            isPresented: $confirmCancelAll, titleVisibility: .visible) {
            Button("Cancel All", role: .destructive) { downloads.cancelAll() }
            Button("Keep Downloading", role: .cancel) {}
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
                    Text(downloads.albums.count == 1 ? "\(downloads.songCount) songs · 1 album" : "\(downloads.songCount) songs · \(downloads.albums.count) albums")
                        .font(.caption)
                        .foregroundStyle(DT.Color.textSecondary)
                }
                Spacer()
            }
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(StorageManagement.formatted(downloads.totalBytes))
                        .font(.system(.title2, weight: .bold))
                        .foregroundStyle(DT.Color.textPrimary)
                        .contentTransition(.numericText())
                    Text("used by music")
                        .font(.system(.subheadline))
                        .foregroundStyle(DT.Color.textSecondary)
                    Spacer(minLength: 8)
                    if let freeBytes {
                        Text("\(StorageManagement.formatted(freeBytes)) free on device")
                            .font(.system(.caption, weight: .medium))
                            .foregroundStyle(DT.Color.textSecondary)
                            .multilineTextAlignment(.trailing)
                    }
                }
                StorageSegmentsBar(segments: storageSegments)
                StorageSegmentsLegend(segments: storageSegments)
            }
            .accessibilityElement(children: .combine)
            MusicAllowanceLine()
            if !downloads.isEmpty {
                MusicPlayShuffleButtons(play: { MusicActions.play(allSongs) }, shuffle: { MusicActions.shuffle(allSongs) })
            }
        }
        .padding(16)
        .background(MusicDownloadsCard())
    }

    /// Shows, movies and music, the same three parts as on Downloads, so the two read the same.
    private var storageSegments: [StorageSegment] {
        let videos = AppServices.downloadManager.ownTitles()
        let showIDs = AppServices.downloadManager.ownShowEpisodeIDs()
        let shows = videos.filter { showIDs.contains($0.itemID) }.reduce(Int64(0)) { $0 + $1.bytes }
        let movies = videos.filter { !showIDs.contains($0.itemID) }.reduce(Int64(0)) { $0 + $1.bytes }
        return [
            StorageSegment(id: "shows", label: String(localized: "Shows"), bytes: shows, color: StorageBreakdown.showsColor),
            StorageSegment(id: "movies", label: String(localized: "Movies"), bytes: movies, color: StorageBreakdown.moviesColor),
            StorageSegment(id: "music", label: String(localized: "Music"), bytes: downloads.totalBytes, color: StorageBreakdown.musicColor),
        ]
    }

    // MARK: Downloading

    private var downloadingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                MusicDownloadsHeader(title: "Downloading", count: downloads.myQueue.count + downloads.myFailed.count)
                Spacer()
                if !downloads.myFailed.isEmpty {
                    Button("Retry All") { downloads.retryFailed() }
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.plain)
                        .foregroundStyle(DT.Color.accent)
                        .padding(.trailing, 12)
                }
                Button("Cancel All", role: .destructive) { confirmCancelAll = true }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(DT.Color.accent)
            }
            if let message = downloads.limitMessage, !downloads.myFailed.isEmpty {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(DT.Color.palette("f59e0b"))
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Lazy: Download All Albums can queue thousands of songs.
            LazyVStack(spacing: 0) {
                ForEach(Array((downloads.myQueue + downloads.myFailed).enumerated()), id: \.element.id) { index, song in
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
            // Only the progress bar spans the row by itself; waiting, the text alone left the
            // row squeezed to its width.
            .frame(maxWidth: .infinity, alignment: .leading)
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

/// One saved album, laid out like its page: the same hero, Play and Shuffle, songs by disc and
/// footer, from what was saved with it, so it looks the same offline. Hold a song to remove it.
private struct MusicDownloadedAlbumView: View {
    let album: MusicAlbum?
    let albumID: String?
    @Environment(\.dismiss) private var dismiss
    private var downloads: MusicDownloads { .shared }
    private var songs: [MusicSong] { downloads.albums.first { $0.songs.first?.albumId == albumID }?.songs ?? [] }

    private var discs: [(number: Int, songs: [MusicSong])] {
        Dictionary(grouping: songs) { $0.discNumber ?? 1 }
            .sorted { $0.key < $1.key }
            .map { ($0.key, $0.value) }
    }

    /// The cover saved with the songs first, so the page works offline.
    private func cover(width: Int) -> URL? {
        albumID.flatMap(downloads.coverURL(albumID:))
            ?? album.flatMap { MusicAPI.artworkURL($0, width: width) }
            ?? songs.first.flatMap { MusicAPI.artworkURL($0, width: width) }
    }

    private var albumArtist: String? { album?.albumArtist ?? songs.first?.albumArtist }

    var body: some View {
        ScrollView {
            VStack(spacing: DT.Spacing.lg) {
                MusicHero(play: { MusicActions.play(songs) }, shuffle: { MusicActions.shuffle(songs) }, canPlay: !songs.isEmpty) { _ in
                    MusicHeroImage(url: cover(width: 1200))
                } info: {
                    titles
                }
                trackList
                footer
            }
            .padding(.bottom, DT.Spacing.xl)
        }
        .ignoresSafeArea(edges: .top)
        .musicHeroBackground(cover(width: 300))
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

    private var titles: some View {
        VStack(spacing: DT.Spacing.xs) {
            Text(verbatim: album?.name ?? songs.first?.albumName ?? "")
                .font(.title2.weight(.bold))
                .foregroundStyle(DT.Color.textPrimary)
                .multilineTextAlignment(.center)
            if let albumArtist {
                Text(verbatim: albumArtist)
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
    }

    /// Genre · year, as on the album's page.
    private var detail: String? {
        let parts = [album?.genres.first, album?.productionYear.map(String.init)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var trackList: some View {
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
                ForEach(Array(disc.songs.enumerated()), id: \.element.id) { position, song in
                    MusicAlbumSongRow(song: song, number: song.trackNumber ?? position + 1, albumArtist: albumArtist) {
                        MusicActions.play(songs, from: songs.firstIndex(of: song) ?? 0)
                    }
                    .contextMenu {
                        Button("Remove Download", systemImage: "trash", role: .destructive) { downloads.remove([song]) }
                    }
                }
            }
        }
    }

    /// As on the album's page, with the space the saved songs take.
    private var footer: some View {
        let minutes = Int((songs.compactMap(\.duration).reduce(0, +) / 60).rounded())
        return VStack(alignment: .leading, spacing: 2) {
            if let released = album?.releaseDate {
                Text(released.formatted(date: .long, time: .omitted))
            } else if let year = album?.productionYear {
                Text(verbatim: String(year))
            }
            Text("\(songs.count) songs, \(minutes) minutes · \(StorageManagement.formatted(downloads.bytes(of: songs))) downloaded")
            if let label = album?.label {
                Text(verbatim: "℗ \(label)")
            }
        }
        .font(.footnote)
        .foregroundStyle(DT.Color.textSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DT.Spacing.pagePad)
    }
}
