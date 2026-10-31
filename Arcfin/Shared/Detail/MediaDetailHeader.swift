// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI
import Persistence

struct MediaDetailHero: View {
    @Environment(MediaRepository.self) private var mediaRepo
    let item: MediaItem
    let metrics: DetailHeaderMetrics

    var body: some View {
        ZStack(alignment: .bottom) {
            if let url = mediaRepo.imageURL(for: item, type: .backdrop, fillWidth: metrics.backdropFillWidth) {
                RetryingAsyncImage(
                    url: url,
                    logCategory: "MediaDetailView",
                    logContext: "backdrop item=\(item.name)",
                    content: { img in
                        img
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    },
                    placeholder: { DetailFallbackHero(item: item) }
                )
            } else { DetailFallbackHero(item: item) }

            // Progressive blur: the material only shows toward the bottom edge, so the
            // image softens as it leaves the frame rather than being covered by a flat band.
            Rectangle()
                .fill(.ultraThinMaterial)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.35),
                            .init(color: .black, location: 1),
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )
        }
        .frame(height: metrics.heroHeight)
        // Exactly the screen's width: a fill-scaled backdrop is wider than a small phone, and
        // sized by its own width it pushed the whole page out past both edges.
        .containerRelativeFrame(.horizontal)
        // Fading the artwork's own opacity (instead of painting the page color over it)
        // blends into whatever is behind, including the artwork-tinted page background.
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.5),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
        )
        .clipped()
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
    let item: MediaItem
    let fileName: String

    var body: some View {
        let url = [item.id, item.seriesId].compactMap { $0 }
            .map { DownloadStore.directory(for: $0).appendingPathComponent(fileName) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
        if let url {
            CachedAsyncImage(url: url) { phase in
                if case .success(let image) = phase { image.resizable().scaledToFill() }
            }
        }
    }
}

/// Poster, name, year, rating, runtime, scores, quality and awards, overlapping the hero.
struct MediaDetailTitleBlock: View {
    @Environment(MediaRepository.self) private var mediaRepo
    let item: MediaItem
    let detail: MediaItemDetail?
    let awards: [WikidataAward]
    let metrics: DetailHeaderMetrics

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Portrait poster
            if let url = mediaRepo.imageURL(for: item, type: .primary, fillWidth: metrics.posterFillWidth) {
                RetryingAsyncImage(
                    url: url,
                    logCategory: "MediaDetailView",
                    logContext: "poster item=\(item.name)",
                    content: { img in img.resizable().scaledToFill() },
                    placeholder: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10).fill(DT.Color.backgroundSecondary)
                            SavedDownloadArtwork(item: item, fileName: "poster.jpg")
                        }
                    }
                )
                .frame(width: metrics.posterSize.width, height: metrics.posterSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(DT.Color.textPrimary.opacity(0.1), lineWidth: 1))
                .shadow(color: .black.opacity(0.6), radius: 12, y: 4)
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(DT.Color.backgroundSecondary)
                    .frame(width: metrics.posterSize.width, height: metrics.posterSize.height)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(item.name)
                    .font(.system(metrics.titleStyle, design: .default, weight: .heavy))
                    .foregroundStyle(DT.Color.textPrimary)
                    .tracking(-0.5)
                    .lineLimit(3)

                DetailMetaRow(item: item, detail: detail)
                DetailQualityRow(detail: detail)
                if !awards.isEmpty { DetailAwardsRow(awards: awards) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.top, -metrics.posterSize.height * 0.38)
        .padding(.bottom, DT.Spacing.md)
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
                    .font(.system(.caption, design: .default))
                    .foregroundStyle(DT.Color.textSecondary)
            }
            if let rating = detail?.officialRating, !rating.isEmpty {
                Text("·").accessibilityHidden(true).foregroundStyle(DT.Color.textPrimary.opacity(0.2)).font(.system(.caption, design: .default))
                Text(rating)
                    .font(.system(.caption2, design: .default, weight: .semibold))
                    .foregroundStyle(DT.Color.textSecondary)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(DT.Color.textSecondary.opacity(0.35), lineWidth: 1))
            }
            if let mins = detail?.runtimeMinutes {
                Text("·").accessibilityHidden(true).foregroundStyle(DT.Color.textPrimary.opacity(0.2)).font(.system(.caption, design: .default))
                Text("\(mins)m")
                    .font(.system(.caption, design: .default))
                    .foregroundStyle(DT.Color.textSecondary)
            }
            if let rating = item.communityRating {
                Text("·").accessibilityHidden(true).foregroundStyle(DT.Color.textPrimary.opacity(0.2)).font(.system(.caption, design: .default))
                HStack(spacing: 3) {
                    Image(systemName: "star.fill")
                        .font(.system(.caption2))
                        .foregroundStyle(DT.Color.accent)
                    Text(String(format: "%.1f", rating))
                        .font(.system(.caption2, design: .default, weight: .bold))
                        .foregroundStyle(DT.Color.accent)
                }
            }
            if let critics = detail?.criticRating {
                Text("·").accessibilityHidden(true).foregroundStyle(DT.Color.textPrimary.opacity(0.2)).font(.system(.caption, design: .default))
                HStack(spacing: 3) {
                    // Positive at 60% and up, the usual critics threshold.
                    Image(systemName: critics >= 60 ? "checkmark.seal.fill" : "xmark.seal.fill")
                        .font(.system(.caption2))
                    Text(Double(critics) / 100, format: .percent.precision(.fractionLength(0)))
                        .font(.system(.caption2, design: .default, weight: .bold))
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
        if names.count == 1 {
            label = "Won \(names[0])"
        } else if names.count <= 3 {
            label = "Won \(names.joined(separator: ", "))"
        } else {
            label = "Won \(names.count) Awards"
        }
        return HStack(spacing: 4) {
            Image(systemName: "trophy.fill")
                .font(.system(.caption2))
            Text(label)
                .font(.system(.caption2, design: .default, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(DT.Color.palette("f59e0b"))
    }

}

private struct DetailQualityBadge: View {
    let label: String
    let color: Color

    var body: some View {
        Text(label)
            .font(.system(.caption2, design: .default, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(color.opacity(0.35), lineWidth: 1))
    }
}

/// Sizes of the hero and the title block, set by each platform's title page.
struct DetailHeaderMetrics {
    let heroHeight: CGFloat
    let posterSize: CGSize
    let titleStyle: Font.TextStyle
    let backdropFillWidth: Int
    let posterFillWidth: Int
}
