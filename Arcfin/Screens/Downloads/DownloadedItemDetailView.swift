// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import Persistence
import JellyfinAPI

/// A downloaded movie or episode, laid out like its page online (hero, poster and title,
/// play, overview, details, cast) from what was saved with the download, so it reads the
/// same with no connection.
struct DownloadedItemDetailView: View {
    let item: DownloadedItem

    @Environment(DownloadManager.self) private var downloadManager
    @Environment(\.dismiss) private var dismiss
    @State private var playingItem: DownloadedItem?
    @State private var startOverride: Int64?
    @State private var showDeleteConfirm = false
    @State private var heroTint: Color?
    /// The server's full page, kept with the download.
    @State private var saved: MediaItemDetail?

    private var isResumable: Bool { item.playbackPositionTicks > 0 && !item.played }
    private var isEpisode: Bool { item.seriesId != nil }

    private var dir: URL { DownloadStore.directory(for: item.itemId) }

    private func fileURL(_ name: String?) -> URL? {
        guard let name, !name.isEmpty else { return nil }
        return dir.appendingPathComponent(name)
    }

    /// An episode rarely has its own backdrop: the show's, saved with its first download, is
    /// the better hero; the episode's own still comes last.
    private var heroURL: URL? {
        if let backdrop = fileURL(item.backdropFileName) { return backdrop }
        if let seriesId = item.seriesId {
            let seriesBackdrop = DownloadStore.directory(for: seriesId).appendingPathComponent("backdrop.jpg")
            if FileManager.default.fileExists(atPath: seriesBackdrop.path) { return seriesBackdrop }
        }
        return fileURL(item.posterFileName)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                DetailHeroBackdrop(url: heroURL)
                titleBlock
                VStack(alignment: .leading, spacing: DT.Spacing.lg) {
                    playRow
                    if let tagline = item.tagline, !tagline.isEmpty {
                        Text(tagline)
                            .font(.system(.subheadline, weight: .medium))
                            .italic()
                            .foregroundStyle(DT.Color.textPrimary.opacity(0.9))
                    }
                    if let overview = item.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.system(.footnote))
                            .foregroundStyle(DT.Color.textPrimary.opacity(0.85))
                            .lineSpacing(3)
                    }
                    if !item.castNames.isEmpty { castSection }
                    detailsSection
                    Button(role: .destructive) { showDeleteConfirm = true } label: {
                        Label("Delete Download", systemImage: "trash")
                            .font(.system(.subheadline, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
                .padding(.horizontal, DT.Spacing.pagePad)
                .padding(.top, DT.Spacing.md)
                .padding(.bottom, DT.Spacing.xl)
            }
            // Re-fits after the player hands the screen back in landscape (see MediaDetailView).
            .containerRelativeFrame(.horizontal)
        }
        .detailPageBackground(tint: heroTint)
        .ignoresSafeArea(edges: .top)
        .navigationTitle("")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        #endif
        .task(id: item.itemId) {
            saved = downloadManager.savedDetail(itemId: item.itemId)
            if let url = heroURL { heroTint = await AverageColor.load(from: url) }
        }
        #if os(iOS)
        .fullScreenCover(item: $playingItem) { item in
            OfflinePlayerView(downloadedItem: item, startPositionOverride: startOverride)
        }
        #elseif os(macOS)
        // fullScreenCover is unavailable on macOS — OfflinePlayerView has its own in-window
        // fullscreen (F key) now that it has a real macOS video surface, so a sheet is enough.
        .sheet(item: $playingItem) { item in
            OfflinePlayerView(downloadedItem: item, startPositionOverride: startOverride)
                .frame(minWidth: 900, minHeight: 560)
        }
        #endif
        .alert("Delete this download?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                downloadManager.deleteDownload(item)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Title

    private var titleBlock: some View {
        HStack(alignment: .bottom, spacing: 14) {
            CachedAsyncImage(url: fileURL(item.posterFileName)) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                default: DT.Color.backgroundSecondary
                }
            }
            .frame(width: isEpisode ? 150 : 90, height: isEpisode ? 84 : 132)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(DT.Color.textPrimary.opacity(0.1), lineWidth: 1))
            .shadow(color: .black.opacity(0.6), radius: 12, y: 4)

            VStack(alignment: .leading, spacing: 5) {
                if isEpisode, let series = item.seriesName {
                    Text(series)
                        .font(.system(.caption, weight: .semibold))
                        .foregroundStyle(DT.Color.accent)
                        .lineLimit(1)
                }
                Text(item.name)
                    .font(.system(.title3, weight: .heavy))
                    .foregroundStyle(DT.Color.textPrimary)
                    .lineLimit(3)
                Text(metaLine)
                    .font(.system(.caption))
                    .foregroundStyle(DT.Color.textSecondary)
                    .lineLimit(2)
                Label("Downloaded", systemImage: "arrow.down.circle.fill")
                    .font(.system(.caption2, weight: .semibold))
                    .foregroundStyle(DT.Color.accent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.top, -60)
    }

    private var metaLine: String {
        var parts: [String] = []
        if isEpisode {
            let code = [item.seasonNumber.map { "S\($0)" }, item.episodeNumber.map { "E\($0)" }].compactMap { $0 }.joined(separator: " · ")
            if !code.isEmpty { parts.append(code) }
        }
        if let year = item.productionYear { parts.append(String(year)) }
        if item.runtimeTicks > 0 { parts.append("\(Int(item.runtimeTicks / 10_000_000 / 60)) min") }
        if let rating = item.officialRating, !rating.isEmpty { parts.append(rating) }
        if let score = item.communityRating, score > 0 { parts.append("★ \(String(format: "%.1f", score))") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Play

    private var playRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    startOverride = nil
                    playingItem = item
                } label: {
                    Label(isResumable ? "Resume" : "Play", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 30)
                }
                .buttonStyle(.glassProminent)
                .tint(DT.Color.accent)
                .foregroundStyle(DT.Color.onAccent)

                if isResumable {
                    Button {
                        startOverride = 0
                        playingItem = item
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.headline)
                            .frame(minWidth: 30, minHeight: 30)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("Start Over")
                }
            }
            .controlSize(.large)

            if isResumable, item.runtimeTicks > 0 {
                let fraction = min(Double(item.playbackPositionTicks) / Double(item.runtimeTicks), 1)
                ProgressView(value: fraction).tint(DT.Color.accent)
                Text("\(max(Int(Double(item.runtimeTicks - item.playbackPositionTicks) / 600_000_000), 1)) min left")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }
        }
    }

    // MARK: - Cast

    private var castSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Cast")
                .font(DT.Font.cardTitle)
                .foregroundStyle(DT.Color.textPrimary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(Array(item.castNames.enumerated()), id: \.offset) { index, name in
                        VStack(spacing: 6) {
                            CachedAsyncImage(url: fileURL(item.castPhotoFileNames[safe: index])) { phase in
                                switch phase {
                                case .success(let image): image.resizable().scaledToFill()
                                default:
                                    ZStack {
                                        DT.Color.backgroundSecondary
                                        Image(systemName: "person.fill").foregroundStyle(DT.Color.textSecondary.opacity(0.5))
                                    }
                                }
                            }
                            .frame(width: 72, height: 72)
                            .clipShape(Circle())
                            Text(name)
                                .font(.system(.caption, weight: .semibold))
                                .foregroundStyle(DT.Color.textPrimary)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                            if let role = item.castRoles[safe: index], !role.isEmpty {
                                Text(role)
                                    .font(.caption2)
                                    .foregroundStyle(DT.Color.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                        .frame(width: 84)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .padding(.horizontal, -DT.Spacing.pagePad)
            .contentMargins(.horizontal, DT.Spacing.pagePad, for: .scrollContent)
        }
    }

    // MARK: - Details

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Details")
                .font(DT.Font.cardTitle)
                .foregroundStyle(DT.Color.textPrimary)
            VStack(spacing: 0) {
                if !item.genres.isEmpty { detailRow("Genres", item.genres.joined(separator: ", ")) }
                if let original = saved?.originalTitle, !original.isEmpty, original != item.name {
                    detailRow("Original Title", original)
                }
                if let premiere = saved?.premiereDate ?? saved?.item.premiereDate {
                    detailRow("Released", premiere.formatted(date: .long, time: .omitted))
                }
                if let critics = saved?.criticRating { detailRow("Critics", "\(Int(critics))%") }
                if !item.directors.isEmpty { detailRow("Director", item.directors.joined(separator: ", ")) }
                if let writers = saved?.writers, !writers.isEmpty {
                    detailRow("Writers", writers.map(\.name).joined(separator: ", "))
                }
                if let countries = saved?.productionLocations, !countries.isEmpty {
                    detailRow("Country", countries.joined(separator: ", "))
                }
                if !item.studios.isEmpty { detailRow("Studio", item.studios.prefix(2).joined(separator: ", ")) }
                if let video = item.videoSummary { detailRow("Video", video) }
                if let audio = item.audioSummary { detailRow("Audio", audio) }
                if !item.subtitleLanguages.isEmpty { detailRow("Subtitles", item.subtitleLanguages.joined(separator: ", ")) }
                detailRow("Size", ByteCountFormatter.string(fromByteCount: item.fileSizeBytes, countStyle: .file))
                detailRow("Downloaded", item.downloadedAt.formatted(date: .abbreviated, time: .omitted))
            }
            .background(DT.Color.backgroundSecondary.opacity(0.7), in: RoundedRectangle(cornerRadius: DT.Radius.md))
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(.footnote, weight: .semibold))
                .foregroundStyle(DT.Color.textSecondary)
            Spacer(minLength: 16)
            Text(value)
                .font(.footnote)
                .foregroundStyle(DT.Color.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
