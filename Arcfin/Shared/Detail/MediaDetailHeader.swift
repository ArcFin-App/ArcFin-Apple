// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI
import Persistence
import SwiftData

/// The top of a title's page: its artwork from the top of the screen (the poster on a phone,
/// the backdrops in turn on a wider screen) with its logo or name, details and badges at the
/// foot, as Home's hero and an artist's page open.
struct MediaDetailHero: View {
    @Environment(MediaRepository.self) private var mediaRepo
    let item: MediaItem
    let detail: MediaItemDetail?
    let awards: [WikidataAward]
    let metrics: DetailHeaderMetrics
    /// A narrow page, where the standing poster fills the top better than a strip of backdrop.
    let isNarrow: Bool
    /// The artwork shown first, for the page to take its tint from.
    var onArtwork: (URL?) -> Void = { _ in }

    private var showsPoster: Bool {
        isNarrow && [.movie, .series, .season, .boxSet].contains(item.type) && item.primaryImageTag != nil
    }

    private var urls: [URL] {
        if showsPoster {
            return [mediaRepo.imageURL(for: item, type: .primary, fillWidth: metrics.posterFillWidth)].compactMap { $0 }
        }
        let backdrops = mediaRepo.backdropURLs(for: detail?.item ?? item, fillWidth: metrics.backdropFillWidth)
        return backdrops.isEmpty
            ? [mediaRepo.imageURL(for: item, type: .backdrop, fillWidth: metrics.backdropFillWidth)].compactMap { $0 }
            : backdrops
    }

    /// A season's or an episode's show, whose logo stands in for theirs.
    private var titleName: String {
        item.type == .episode || item.type == .season ? (item.seriesName ?? item.name) : item.name
    }

    private var subtitle: String? {
        switch item.type {
        case .episode: [HomeText.episodeLabel(item), item.name].compactMap { $0 }.joined(separator: " · ")
        case .season: item.name
        default: nil
        }
    }

    var body: some View {
        ShowcaseHero(urls: urls, portrait: showsPoster, landscapeHeight: metrics.heroHeight) {
            DetailFallbackHero(item: item)
        } content: {
            ShowcaseTitle(logoURL: mediaRepo.logoURL(for: item, fillWidth: 600), name: titleName,
                          nameStyle: metrics.titleStyle)
            if let subtitle {
                Text(verbatim: subtitle)
                    .contentFont(.headline, design: .default, weight: .semibold)
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(2)
            }
            DetailMetaRow(item: item, detail: detail)
            DetailQualityRow(detail: detail)
            if !awards.isEmpty { DetailAwardsRow(awards: awards) }
        }
        .task(id: urls) { mediaRepo.prefetch(urls: urls) }
        .task(id: urls.first) { onArtwork(urls.first) }
    }
}

private struct DetailFallbackHero: View {
    let item: MediaItem

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [DT.Color.accentDeep, DT.Color.backgroundPrimary],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            SavedDownloadArtwork(item: item, fileName: "backdrop.jpg")
        }
    }

}

/// Artwork kept with a download, for when the server's can't be reached.
private struct SavedDownloadArtwork: View {
    @Environment(DownloadManager.self) private var downloadManager
    @Environment(\.modelContext) private var modelContext
    let item: MediaItem
    let fileName: String

    /// This profile's copy of the title, then the show's folder if this profile has an episode of it.
    private var folders: [URL] {
        var folders = downloadManager.ownDownload(itemId: item.id).map { [DownloadStore.directory(for: $0)] } ?? []
        let seriesId = item.seriesId ?? item.id
        let episodes = (try? modelContext.fetch(FetchDescriptor<DownloadedItem>(predicate: #Predicate { $0.seriesId == seriesId }))) ?? []
        if !downloadManager.ownDownloads(episodes).isEmpty { folders.append(DownloadStore.directory(for: seriesId)) }
        return folders
    }

    var body: some View {
        let url = folders.map { $0.appendingPathComponent(fileName) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
        if let url {
            CachedAsyncImage(url: url) { phase in
                if case .success(let image) = phase { image.resizable().scaledToFill() }
            }
        }
    }
}

private struct DetailMetaRow: View {
    let item: MediaItem
    let detail: MediaItemDetail?

    var body: some View {
        // lineLimit(1) cascades to every Text child, giving HStack's layout room to
        // compress/truncate them when every optional field (year, rating, runtime,
        // community score) is present at once — without it, none of these Text views have
        // a defined minimum width, so HStack can't shrink them and the row overflows past
        // the screen edge instead.
        HStack(spacing: 6) {
            if let year = item.productionYear {
                Text(String(year))
                    .contentFont(.caption, design: .default)
                    .foregroundStyle(DT.Color.textSecondary)
            }
            if let rating = detail?.officialRating, !rating.isEmpty {
                Text("·").accessibilityHidden(true).foregroundStyle(DT.Color.textPrimary.opacity(0.2)).contentFont(.caption, design: .default)
                Text(rating)
                    .contentFont(.caption2, design: .default, weight: .semibold)
                    .foregroundStyle(DT.Color.textSecondary)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(DT.Color.textSecondary.opacity(0.35), lineWidth: 1))
            }
            if let mins = detail?.runtimeMinutes {
                Text("·").accessibilityHidden(true).foregroundStyle(DT.Color.textPrimary.opacity(0.2)).contentFont(.caption, design: .default)
                Text(DurationText.minutes(mins))
                    .contentFont(.caption, design: .default)
                    .foregroundStyle(DT.Color.textSecondary)
            }
            if let rating = item.communityRating {
                Text("·").accessibilityHidden(true).foregroundStyle(DT.Color.textPrimary.opacity(0.2)).contentFont(.caption, design: .default)
                HStack(spacing: 3) {
                    Image(systemName: "star.fill")
                        .contentFont(.caption2)
                        .foregroundStyle(DT.Color.accent)
                    Text(rating.ratingText)
                        .contentFont(.caption2, design: .default, weight: .bold)
                        .foregroundStyle(DT.Color.accent)
                }
            }
            if let critics = detail?.criticRating {
                Text("·").accessibilityHidden(true).foregroundStyle(DT.Color.textPrimary.opacity(0.2)).contentFont(.caption, design: .default)
                HStack(spacing: 3) {
                    // Positive at 60% and up, the usual critics threshold.
                    Image(systemName: critics >= 60 ? "checkmark.seal.fill" : "xmark.seal.fill")
                        .contentFont(.caption2)
                    Text(Double(critics) / 100, format: .percent.precision(.fractionLength(0)))
                        .contentFont(.caption2, design: .default, weight: .bold)
                }
                .foregroundStyle(critics >= 60 ? DT.Color.palette("10b981") : DT.Color.palette("f59e0b"))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Critics score \(Int(critics.rounded())) percent")
            }
        }
        .lineLimit(1)
    }

}

private struct DetailQualityRow: View {
    let detail: MediaItemDetail?

    var body: some View {
        HStack(spacing: 6) {
            if detail?.is4K == true { DetailQualityBadge(label: "4K", color: DT.Color.palette("FF6A4D")) }
            if detail?.isHDR == true { DetailQualityBadge(label: "HDR", color: DT.Color.palette("F59E0B")) }
            if let codec = detail?.videoStream?.codec?.uppercased() {
                DetailQualityBadge(label: codec, color: DT.Color.palette("60A5FA"))
            }
        }
    }

}

/// One entry → that award's own name; a few → joined; many → just the count. Wikidata's
/// P166 ("award received") statements are wins, not nominations, so "Won" is accurate.
private struct DetailAwardsRow: View {
    let awards: [WikidataAward]

    var body: some View {
        let names = Array(Set(awards.map(\.name))).sorted()
        let label: String
        if names.count <= 3 {
            label = String(localized: "Won \(names.formatted(.list(type: .and)))")
        } else {
            label = String(localized: "Won \(names.count) Awards")
        }
        return HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: "trophy.fill")
                .contentFont(.caption2)
            Text(label)
                .contentFont(.caption2, design: .default, weight: .semibold)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(DT.Color.palette("f59e0b"))
    }

}

private struct DetailQualityBadge: View {
    let label: String
    let color: Color

    var body: some View {
        Text(label)
            .contentFont(.caption2, design: .default, weight: .bold)
            .tracking(0.5)
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(color.opacity(0.35), lineWidth: 1))
    }
}

/// Sizes of the hero, set by each platform's title page.
struct DetailHeaderMetrics {
    let heroHeight: CGFloat
    let titleStyle: Font.TextStyle
    let backdropFillWidth: Int
    let posterFillWidth: Int
}
