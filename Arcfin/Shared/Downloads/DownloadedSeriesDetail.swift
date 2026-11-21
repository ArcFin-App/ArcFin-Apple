// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import Persistence

/// A downloaded show's page state, shared by every platform's `DownloadedSeriesDetailView`.
@MainActor @Observable
final class DownloadedSeriesDetailModel {
    var selectedSeason: Int?
    var playingItem: DownloadedItem?
    private(set) var playStartOverride: Int64?
    var pendingDelete: DownloadedItem?
    var selection = Set<String>()
    var showBulkDeleteConfirm = false
    private(set) var heroTint: Color?

    static func series(_ seriesId: String, in allSeries: [DownloadedSeries]) -> DownloadedSeries? { allSeries.first { $0.seriesId == seriesId } }
    static func episodes(of seriesId: String, in allItems: [DownloadedItem]) -> [DownloadedItem] { allItems.filter { $0.seriesId == seriesId } }
    static func seasonNumbers(of episodes: [DownloadedItem]) -> [Int] { Array(Set(episodes.compactMap(\.seasonNumber))).sorted() }
    func episodesInSelectedSeason(of episodes: [DownloadedItem]) -> [DownloadedItem] {
        episodes.filter { $0.seasonNumber == selectedSeason }
    }

    func loadHeroTint(seriesId: String, series: DownloadedSeries?) async {
        if let url = Self.heroURL(seriesId: seriesId, series: series) { heroTint = await AverageColor.load(from: url) }
    }

    /// Plays from the saved position, or from `startOverride` (0 for Start Over).
    func play(_ episode: DownloadedItem, startOverride: Int64?) {
        playStartOverride = startOverride
        playingItem = episode
    }

    func toggleSelection(_ id: String) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    func deleteSelection(of episodes: [DownloadedItem], downloadManager: DownloadManager) {
        let toDelete = episodes.filter { selection.contains($0.itemId) }
        downloadManager.deleteDownloads(toDelete)
        selection.removeAll()
    }

    static func fileURL(_ name: String?, seriesId: String) -> URL? {
        guard let name, !name.isEmpty else { return nil }
        return DownloadStore.directory(for: seriesId).appendingPathComponent(name)
    }

    static func heroURL(seriesId: String, series: DownloadedSeries?) -> URL? {
        fileURL(series?.backdropFileName, seriesId: seriesId) ?? fileURL(series?.posterFileName, seriesId: seriesId)
    }
}

/// The hero, poster and title, details and season picker at the top of a downloaded show.
struct DownloadedSeriesHeader: View {
    let seriesId: String
    let model: DownloadedSeriesDetailModel
    let series: DownloadedSeries?
    let episodes: [DownloadedItem]

    private var seasonNumbers: [Int] { DownloadedSeriesDetailModel.seasonNumbers(of: episodes) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            backdrop

            VStack(alignment: .leading, spacing: DT.Spacing.md) {
                HStack(spacing: 8) {
                    Text("Series")
                        .font(.system(.caption2, design: .default, weight: .semibold))
                        .foregroundStyle(DT.Color.textSecondary)
                    if let year = series?.productionYear {
                        Text("· \(String(year))")
                            .font(.system(.caption2))
                            .foregroundStyle(DT.Color.textSecondary)
                    }
                    if let rating = series?.communityRating, rating > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill").font(.system(.caption2)).accessibilityHidden(true)
                            Text(String(format: "%.1f", rating))
                        }
                        .font(.system(.caption2))
                        .foregroundStyle(DT.Color.palette("f59e0b"))
                    }
                }

                if let genres = series?.genres, !genres.isEmpty {
                    Text(genres.joined(separator: " · "))
                        .font(.system(.caption))
                        .foregroundStyle(DT.Color.textSecondary)
                }

                if let overview = series?.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.system(.footnote))
                        .foregroundStyle(DT.Color.textPrimary.opacity(0.85))
                        .lineSpacing(3)
                }

                if seasonNumbers.count > 1 {
                    seasonPicker
                }
            }
            .padding(.horizontal, DT.Spacing.pagePad)
            .padding(.top, DT.Spacing.md)
        }
    }

    /// The same hero and poster-and-title block as a show's page online.
    private var backdrop: some View {
        VStack(alignment: .leading, spacing: 0) {
            DetailHeroBackdrop(url: DownloadedSeriesDetailModel.heroURL(seriesId: seriesId, series: series))
            HStack(alignment: .bottom, spacing: 14) {
                CachedAsyncImage(url: DownloadedSeriesDetailModel.fileURL(series?.posterFileName, seriesId: seriesId)) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    default: DT.Color.backgroundSecondary
                    }
                }
                .frame(width: 90, height: 132)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(DT.Color.textPrimary.opacity(0.1), lineWidth: 1))
                .shadow(color: .black.opacity(0.6), radius: 12, y: 4)

                VStack(alignment: .leading, spacing: 5) {
                    Text(series?.name ?? episodes.first?.seriesName ?? "Show")
                        .font(.system(.title3, weight: .heavy))
                        .foregroundStyle(DT.Color.textPrimary)
                        .lineLimit(3)
                    Label(episodes.count == 1 ? "1 episode downloaded" : "\(episodes.count) episodes downloaded", systemImage: "arrow.down.circle.fill")
                        .font(.system(.caption2, weight: .semibold))
                        .foregroundStyle(DT.Color.accent)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, DT.Spacing.pagePad)
            .padding(.top, -60)
        }
    }

    private var seasonPicker: some View {
        Menu {
            ForEach(seasonNumbers, id: \.self) { season in
                Button("Season \(String(season))") { model.selectedSeason = season }
            }
        } label: {
            HStack(spacing: 5) {
                Text(model.selectedSeason.map { "Season \(String($0))" } ?? "Season")
                    .font(.system(.footnote, design: .default, weight: .semibold))
                    .foregroundStyle(DT.Color.textPrimary)
                Image(systemName: "chevron.down")
                    .font(.system(.caption2, weight: .semibold))
                    .foregroundStyle(DT.Color.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(DT.Color.textPrimary.opacity(0.08), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// The check beside an episode while picking several.
struct DownloadedEpisodeSelectionIndicator: View {
    let isSelected: Bool

    var body: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(.title3))
            .foregroundStyle(isSelected ? DT.Color.accent : DT.Color.textSecondary.opacity(0.5))
            .accessibilityHidden(true)
    }
}

/// A downloaded episode's still, code, name, size and whether it's been watched.
struct DownloadedEpisodeRowContent: View {
    let episode: DownloadedItem

    var body: some View {
        HStack(spacing: 12) {
            episodeThumbnail
            VStack(alignment: .leading, spacing: 3) {
                Text(episodeLabel)
                    .font(.system(.caption2, design: .default, weight: .semibold))
                    .foregroundStyle(DT.Color.accent)
                Text(episode.name)
                    .font(.system(.footnote, design: .default, weight: .semibold))
                    .foregroundStyle(DT.Color.textPrimary)
                    .lineLimit(1)
                Text(ByteCountFormatter.string(fromByteCount: episode.fileSizeBytes, countStyle: .file))
                    .font(.system(.caption2))
                    .foregroundStyle(DT.Color.textSecondary)
            }
            Spacer()
            Image(systemName: episode.played ? "checkmark.circle.fill" : "play.circle")
                .font(.system(.title3))
                .foregroundStyle(episode.played ? DT.Color.palette("10b981") : DT.Color.textSecondary)
                .accessibilityLabel(episode.played ? "Watched" : "Not watched")
        }
    }

    private var episodeThumbnail: some View {
        Group {
            if let fileName = episode.posterFileName,
               let image = PlatformImage.from(contentsOfFile: DownloadStore.directory(for: episode.itemId).appendingPathComponent(fileName).path) {
                Image(platformImage: image).resizable().scaledToFill()
            } else {
                DT.Color.backgroundSecondary
            }
        }
        .frame(width: 80, height: 46)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(DT.Color.textPrimary.opacity(0.06), lineWidth: 1))
    }

    private var episodeLabel: String {
        let s = episode.seasonNumber.map { "S\($0)" } ?? ""
        let e = episode.episodeNumber.map { "E\($0)" } ?? ""
        return s + e
    }
}

/// The larger still and name shown while pressing an episode for its menu.
struct DownloadedEpisodeRowPreview: View {
    let episode: DownloadedItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if let fileName = episode.posterFileName,
                   let image = PlatformImage.from(contentsOfFile: DownloadStore.directory(for: episode.itemId).appendingPathComponent(fileName).path) {
                    Image(platformImage: image).resizable().scaledToFill()
                } else {
                    DT.Color.backgroundSecondary
                }
            }
            .frame(width: 240, height: 135)
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.card))

            Text(episode.name)
                .font(.system(.footnote, design: .default, weight: .semibold))
                .foregroundStyle(DT.Color.textPrimary)
                .lineLimit(2)
                .frame(width: 240, alignment: .leading)
        }
        .padding(DT.Spacing.sm)
    }
}
