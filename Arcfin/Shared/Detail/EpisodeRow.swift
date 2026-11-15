// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

/// One episode on a show's title page: thumbnail with watched state or progress, number,
/// badge, name, download button and overview.
struct EpisodeRow: View {
    @Environment(MediaRepository.self) private var mediaRepo
    let episode: MediaItem
    /// "NEW", "FINALE" or why it can't be played.
    let badge: String?
    let spoilerProtection: Bool
    let onSelect: () -> Void
    let onToggleWatched: () -> Void

    var body: some View {
        let ep = episode
        let isWatched = ep.userData?.played == true
        let pct = ep.userData?.playedPercentage ?? 0
        // Settings › Appearance › Spoiler Protection: nothing from an episode not yet started.
        let hidesSpoilers = spoilerProtection && !isWatched && pct == 0

        return Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        if let url = mediaRepo.episodeThumbnailURL(for: ep) {
                            CachedAsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let img): img.resizable().scaledToFill()
                                default: EpisodeThumbPlaceholder()
                                }
                            }
                        } else {
                            EpisodeThumbPlaceholder()
                        }

                        if isWatched {
                            Color.black.opacity(0.45)
                            Image(systemName: "checkmark.circle.fill")
                                .contentFont(.title2)
                                .foregroundStyle(DT.Color.palette("10b981"))
                        } else if pct > 0 {
                            VStack(spacing: 0) {
                                Spacer()
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Rectangle().fill(.white.opacity(0.25)).frame(height: 3)
                                        Rectangle()
                                            .fill(DT.Color.accent)
                                            .frame(width: geo.size.width * CGFloat(min(pct / 100.0, 1.0)), height: 3)
                                    }
                                }
                                .frame(height: 3)
                            }
                        }
                    }
                    .frame(width: 120, height: 68)
                    .blur(radius: hidesSpoilers ? 14 : 0)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            if let epNum = ep.indexNumber {
                                Text("E\(epNum)")
                                    .contentFont(.caption2, design: .default, weight: .semibold)
                                    .foregroundStyle(DT.Color.accent)
                            }
                            if let badge {
                                Text(badge)
                                    .contentFont(.caption2, design: .default, weight: .bold)
                                    .padding(.horizontal, 6).padding(.vertical, 1)
                                    .background(DT.Color.accent.opacity(0.18), in: Capsule())
                                    .foregroundStyle(DT.Color.accent)
                            }
                        }
                        Text(ep.name)
                            .contentFont(.footnote, design: .default, weight: .semibold)
                            .foregroundStyle(DT.Color.textPrimary)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if !ep.isVirtual { DownloadButton(item: ep) }
                }

                if !hidesSpoilers, let overview = ep.overview, !overview.isEmpty {
                    Text(overview)
                        .contentFont(.caption2, design: .default)
                        .foregroundStyle(DT.Color.textSecondary)
                        .lineLimit(3)
                        .padding(.top, 8)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(DT.Color.textPrimary.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(DT.Color.textPrimary.opacity(0.05), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .contextMenu(menuItems: {
            Button {
                HapticManager.impact(.light)
                onToggleWatched()
            } label: {
                Label(isWatched ? "Mark as Unwatched" : "Mark as Watched",
                      systemImage: isWatched ? "eye.slash" : "checkmark")
            }
        }, preview: {
            EpisodeRowPreview(episode: ep, imageURL: mediaRepo.episodeThumbnailURL(for: ep))
        })
    }
}

/// Gets its image URL handed in: a context menu's preview is drawn outside the app's
/// environment, so reading MediaRepository from it there traps.
private struct EpisodeRowPreview: View {
    let episode: MediaItem
    let imageURL: URL?

    var body: some View {
        let ep = episode
        return VStack(alignment: .leading, spacing: 8) {
            Group {
                if let url = imageURL {
                    CachedAsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFill()
                        default: EpisodeThumbPlaceholder()
                        }
                    }
                } else {
                    EpisodeThumbPlaceholder()
                }
            }
            .frame(width: 240, height: 135)
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.card))

            Text(ep.name)
                .contentFont(.footnote, design: .default, weight: .semibold)
                .foregroundStyle(DT.Color.textPrimary)
                .lineLimit(2)
                .frame(width: 240, alignment: .leading)
        }
        .padding(DT.Spacing.sm)
    }
}

private struct EpisodeThumbPlaceholder: View {
    var body: some View {
        Rectangle()
            .fill(DT.Color.backgroundSecondary)
            .overlay(
                Image(systemName: "play.rectangle")
                    .contentFont(.title3)
                    .foregroundStyle(DT.Color.textSecondary.opacity(0.3))
            )
    }
}

/// From an episode's page, a link to its show.
struct DetailSeriesLink<Link: View>: View {
    let series: MediaItem
    /// Each platform's link around the show's row.
    @ViewBuilder let link: (DetailSeriesLabel) -> Link

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DetailSectionTitle(title: "Series")
            link(DetailSeriesLabel(series: series))
                .buttonStyle(.plain)
        }
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.bottom, DT.Spacing.md)
    }
}

struct DetailSeriesLabel: View {
    let series: MediaItem

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "tv")
                .contentFont(.subheadline)
                .foregroundStyle(DT.Color.accent)
            Text(series.name)
                .contentFont(.footnote, design: .default, weight: .semibold)
                .foregroundStyle(DT.Color.textPrimary)
                .lineLimit(1)
            Spacer()
            Image(systemName: "chevron.right")
                .contentFont(.caption2)
                .foregroundStyle(DT.Color.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(DT.Color.textPrimary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(DT.Color.textPrimary.opacity(0.05), lineWidth: 1))
    }
}
