// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import Persistence
import JellyfinAPI

/// A downloaded title's page state, shared by every platform's `DownloadedItemDetailView`.
@MainActor @Observable
final class DownloadedItemDetailModel {
    var playingItem: DownloadedItem?
    private(set) var startOverride: Int64?
    var showDeleteConfirm = false
    private(set) var heroTint: Color?
    /// The server's full page, kept with the download.
    private(set) var saved: MediaItemDetail?

    func load(_ item: DownloadedItem, downloadManager: DownloadManager) async {
        saved = downloadManager.savedDetail(itemId: item.itemId)
        if let url = Self.heroURL(for: item) { heroTint = await AverageColor.load(from: url) }
    }

    enum DeleteOnClose { case delete, deleteAndIgnore }
    /// Picked in the delete confirmation, and done once the page has gone: until then it still
    /// reads the record, and reading a deleted SwiftData model is unsafe.
    var deleteOnClose: DeleteOnClose?

    func pageClosed(_ item: DownloadedItem, downloadManager: DownloadManager) {
        switch deleteOnClose {
        case .delete: downloadManager.deleteDownload(item)
        case .deleteAndIgnore: downloadManager.deleteAndIgnore(itemIds: [item.itemId])
        case nil: break
        }
        deleteOnClose = nil
    }

    /// Plays from the saved position, or from `startOverride` (0 for Start Over).
    func play(_ item: DownloadedItem, startOverride: Int64?) {
        self.startOverride = startOverride
        playingItem = item
    }

    static func fileURL(_ name: String?, of item: DownloadedItem) -> URL? {
        guard let name, !name.isEmpty else { return nil }
        return DownloadStore.directory(for: item.itemId).appendingPathComponent(name)
    }

    /// An episode rarely has its own backdrop: the show's, saved with its first download, is
    /// the better hero; the episode's own still comes last.
    static func heroURL(for item: DownloadedItem) -> URL? {
        if let backdrop = fileURL(item.backdropFileName, of: item) { return backdrop }
        if let seriesId = item.seriesId {
            let seriesBackdrop = DownloadStore.directory(for: seriesId).appendingPathComponent("backdrop.jpg")
            if FileManager.default.fileExists(atPath: seriesBackdrop.path) { return seriesBackdrop }
        }
        return fileURL(item.posterFileName, of: item)
    }
}

/// A downloaded movie or episode, laid out like its page online (hero, poster and title,
/// play, overview, details, cast) from what was saved with the download, so it reads the
/// same with no connection.
struct DownloadedItemDetailPage: View {
    let item: DownloadedItem
    let model: DownloadedItemDetailModel

    private var isResumable: Bool { item.playbackPositionTicks > 0 && !item.played }
    private var isEpisode: Bool { item.seriesId != nil }

    private func fileURL(_ name: String?) -> URL? { DownloadedItemDetailModel.fileURL(name, of: item) }

    var body: some View {
        GeometryReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    DetailHeroBackdrop(url: DownloadedItemDetailModel.heroURL(for: item))
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
                        Button(role: .destructive) { model.showDeleteConfirm = true } label: {
                            Label("Delete Download", systemImage: "trash")
                                .font(.system(.subheadline, weight: .semibold))
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .tint(DT.Color.palette("F43F5E"))
                    }
                    .padding(.horizontal, DT.Spacing.pagePad)
                    .padding(.top, DT.Spacing.md)
                    .padding(.bottom, DT.Spacing.xl)
                }
                // A page-wide frame from the GeometryReader, not containerRelativeFrame: it follows an
                // iPhone turn (#325) and, on the Mac, can't feed the page's width back into the
                // window's layout (#345).
                .frame(width: proxy.size.width)
            }
        }
        .detailPageBackground(tint: model.heroTint)
        .ignoresSafeArea(edges: .top)
        .navigationTitle("")
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
        if let score = item.communityRating, score > 0 { parts.append("★ \(score.formatted(.number.precision(.fractionLength(1))))") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Play

    private var playRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    model.play(item, startOverride: nil)
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
                        model.play(item, startOverride: 0)
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
                                .lineLimit(2, reservesSpace: true)
                                .multilineTextAlignment(.center)
                            Text(item.castRoles[safe: index] ?? "")
                                .font(.caption2)
                                .foregroundStyle(DT.Color.textSecondary)
                                .lineLimit(1, reservesSpace: true)
                        }
                        .frame(width: 84)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .shelfScrollButtons()
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
                let saved = model.saved
                if !item.genres.isEmpty { detailRow("Genres", item.genres.joined(separator: ", ")) }
                if let original = saved?.originalTitle, !original.isEmpty, original != item.name {
                    detailRow("Original Title", original)
                }
                if let premiere = saved?.premiereDate ?? saved?.item.premiereDate {
                    detailRow("Released", premiere.formatted(date: .long, time: .omitted))
                }
                if let critics = saved?.criticRating { detailRow("Critics", (Double(critics) / 100).formatted(.percent.precision(.fractionLength(0)))) }
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

    private func detailRow(_ label: LocalizedStringKey, _ value: String) -> some View {
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
