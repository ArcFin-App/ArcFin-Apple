// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI
import SeerrAPI

/// Recent searches; tapping one searches it again.
struct RecentSearchesList<Row: View>: View {
    let terms: [String]
    let clear: () -> Void
    /// Each platform's button around a term's label.
    @ViewBuilder let row: (String, SearchRecentLabel) -> Row

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DT.Spacing.sm) {
                HStack {
                    Text("Recent")
                        .font(DT.Font.cardTitle)
                        .foregroundStyle(DT.Color.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button("Clear", action: clear)
                        .contentFont(.footnote, weight: .semibold)
                        .foregroundStyle(DT.Color.accent)
                }
                ForEach(terms, id: \.self) { term in
                    row(term, SearchRecentLabel(term: term))
                }
            }
            .padding(.horizontal, DT.Spacing.pagePad)
            .padding(.top, 12)
        }
    }
}

struct SearchRecentLabel: View {
    let term: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(DT.Color.textSecondary)
                .accessibilityHidden(true)
            Text(term)
                .contentFont(.body)
                .foregroundStyle(DT.Color.textPrimary)
            Spacer()
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

/// Nothing typed yet, or nothing found.
struct SearchEmptyState: View {
    let query: String
    var failed = false
    var retry: () -> Void = {}

    var body: some View {
        if failed, !query.isEmpty {
            ContentUnavailableView {
                Label("Couldn't Search Your Library", systemImage: "exclamationmark.triangle")
            } description: {
                Text("Couldn't reach your server. Check your connection, then try again.")
            } actions: {
                Button("Try Again", action: retry)
            }
        } else if query.isEmpty {
            ContentUnavailableView(
                "Search",
                systemImage: "magnifyingglass",
                description: Text("Find movies, shows, and more.")
            )
        } else {
            ContentUnavailableView.search(text: query)
        }
    }
}

struct SearchingRow: View {
    let text: LocalizedStringKey

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(text)
                .contentFont(.subheadline)
                .foregroundStyle(DT.Color.textSecondary)
        }
        .padding(.horizontal, DT.Spacing.pagePad)
    }
}

struct SearchSectionHeader: View {
    let title: String
    var count: Int?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(DT.Font.sectionTitle)
                .foregroundStyle(DT.Color.textPrimary)
            if let count {
                Text("\(count)")
                    .contentFont(.subheadline, weight: .semibold)
                    .foregroundStyle(DT.Color.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .padding(.horizontal, DT.Spacing.pagePad)
    }
}

/// The best match, large, over its backdrop.
struct SearchTopResultCard: View {
    @Environment(MediaRepository.self) private var mediaRepo
    let item: MediaItem
    let height: CGFloat

    var body: some View {
        let details = [SearchText.kindLabel(item), item.seriesName, SearchText.episodeCode(item), item.productionYear.map(String.init)].compactMap { $0 }
        ZStack(alignment: .bottomLeading) {
            RetryingAsyncImage(
                url: mediaRepo.imageURL(for: item, type: .backdrop, fillWidth: 1000) ?? SearchText.posterImageURL(for: item, in: mediaRepo),
                logCategory: "SearchView", logContext: "top result item=\(item.name)",
                content: { $0.resizable().scaledToFill() },
                placeholder: { DT.Color.backgroundTertiary })
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .clipped()
            .allowsHitTesting(false)

            LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 4) {
                Text("TOP RESULT")
                    .contentFont(.caption2, weight: .bold)
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.75))
                Text(item.name)
                    .contentFont(.title2, weight: .bold)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(details.joined(separator: " · "))
                    .contentFont(.footnote, weight: .medium)
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
            }
            .padding(DT.Spacing.md)
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.lg, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: DT.Radius.lg, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Top result: \(item.name), \(details.joined(separator: ", "))")
    }
}

/// A library result in a shelf: a poster, or a wide thumbnail for an episode.
struct SearchShelfCard: View {
    @Environment(MediaRepository.self) private var mediaRepo
    let item: MediaItem
    let isLandscape: Bool
    let posterWidth: CGFloat
    let landscapeWidth: CGFloat

    var body: some View {
        if isLandscape {
            SearchResultCard(title: item.name,
                             subtitle: [item.seriesName, SearchText.episodeCode(item)].compactMap { $0 }.joined(separator: " · ").nilIfEmpty,
                             imageURL: mediaRepo.episodeThumbnailURL(for: item, fillWidth: 480) ?? SearchText.posterImageURL(for: item, in: mediaRepo),
                             aspectRatio: 16 / 9)
                .frame(width: landscapeWidth)
        } else {
            SearchResultCard(title: item.name, subtitle: item.productionYear.map { String($0) },
                             imageURL: SearchText.posterImageURL(for: item, in: mediaRepo))
                .frame(width: posterWidth)
        }
    }
}

/// Seerr's results for titles the server doesn't have, each row with its request status.
struct SearchDiscoverSection<Row: View>: View {
    let items: [SeerrItem]
    let isSearching: Bool
    let posterWidth: CGFloat
    /// Each platform's button around a result's row.
    @ViewBuilder let row: (SeerrItem) -> Row

    var body: some View {
        VStack(alignment: .leading, spacing: DT.Spacing.sm) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .contentFont(.subheadline, weight: .bold)
                    .foregroundStyle(DT.Color.onAccent)
                    .frame(width: 30, height: 30)
                    .background(LinearGradient(colors: [DT.Color.accentDeep, DT.Color.accent],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: DT.Radius.sm, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Discover")
                        .font(DT.Font.sectionTitle)
                        .foregroundStyle(DT.Color.textPrimary)
                    Text("Not in your library yet · from Seerr")
                        .contentFont(.caption)
                        .foregroundStyle(DT.Color.textSecondary)
                }
                Spacer(minLength: 0)
                if isSearching { ProgressView() }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Divider().overlay(DT.Color.textPrimary.opacity(0.06))
                            .padding(.leading, posterWidth + DT.Spacing.sm)
                    }
                    row(item)
                }
            }
        }
        .padding(DT.Spacing.md)
        .background(
            LinearGradient(colors: [DT.Color.accent.opacity(0.12), DT.Color.backgroundSecondary.opacity(0.6)],
                           startPoint: .topLeading, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: DT.Radius.xl, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DT.Radius.xl, style: .continuous)
            .stroke(DT.Color.accent.opacity(0.2), lineWidth: 1))
        .padding(.horizontal, DT.Spacing.pagePad)
    }
}

struct SearchDiscoverRow: View {
    let item: SeerrItem
    let posterWidth: CGFloat

    var body: some View {
        HStack(alignment: .center, spacing: DT.Spacing.sm) {
            RetryingAsyncImage(
                url: item.posterURL, logCategory: "SearchView", logContext: "discover item=\(item.title)",
                content: { $0.resizable().scaledToFill() },
                placeholder: { DT.Color.backgroundTertiary })
            .frame(width: posterWidth, height: posterWidth * 1.5)
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.sm, style: .continuous))
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .contentFont(.subheadline, weight: .semibold)
                    .foregroundStyle(DT.Color.textPrimary)
                    .lineLimit(2)
                Text([item.mediaType == .movie ? "Movie" : "Show", item.year].compactMap { $0 }.joined(separator: " · "))
                    .contentFont(.caption, weight: .medium)
                    .foregroundStyle(DT.Color.textSecondary)
                if let overview = item.overview, !overview.isEmpty {
                    Text(overview)
                        .contentFont(.caption)
                        .foregroundStyle(DT.Color.textSecondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            SearchDiscoverStatus(item: item)
        }
        .padding(.vertical, DT.Spacing.xs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(item.availabilityStatus == nil ? "Request from Seerr" : "")
    }
}

/// Request for anything Seerr hasn't heard of; otherwise where it is.
private struct SearchDiscoverStatus: View {
    let item: SeerrItem

    var body: some View {
        if let status = item.availabilityStatus, status != .unknown {
            Text(status == .pending || status == .processing ? "Requested" : status.label)
                .contentFont(.caption2, weight: .bold)
                .foregroundStyle(DT.Color.palette(status.colorHex))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(DT.Color.palette(status.colorHex).opacity(0.15), in: Capsule())
        } else {
            Text("Request")
                .contentFont(.caption, weight: .bold)
                .foregroundStyle(DT.Color.onAccent)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(DT.Color.accent, in: Capsule())
        }
    }
}

/// The plain grid's heading for Discover, in its tinted box.
struct SearchClassicDiscover<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: DT.Spacing.sectionGap) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .contentFont(.footnote, weight: .semibold)
                    .foregroundStyle(DT.Color.accent)
                Text("Discover")
                    .font(DT.Font.cardTitle)
                    .foregroundStyle(DT.Color.textPrimary)
            }
            content()
        }
        .padding(DT.Spacing.sm)
        .background(DT.Color.backgroundSecondary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: DT.Radius.lg).stroke(DT.Color.accent.opacity(0.2), lineWidth: 1))
    }
}

// MARK: - Grid card

struct SearchResultCard: View {
    let title: String
    let subtitle: String?
    let imageURL: URL?
    var aspectRatio: CGFloat = 2 / 3

    @State private var hovered = false
    @Environment(\.isFocused) private var isFocused

    private var highlighted: Bool { hovered || isFocused }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack {
                RetryingAsyncImage(
                    url: imageURL, logCategory: "SearchView", logContext: "result item=\(title)",
                    content: { $0.resizable().scaledToFill() },
                    placeholder: { DT.Color.backgroundSecondary })
                .clipped()
            }
            .aspectRatio(aspectRatio, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.card))
            .overlay(
                RoundedRectangle(cornerRadius: DT.Radius.card)
                    .stroke(isFocused ? DT.Color.accent : (hovered ? DT.Color.accent.opacity(0.35) : DT.Color.textPrimary.opacity(0.06)),
                            lineWidth: isFocused ? 3 : 1)
            )
            .scaleEffect(isFocused ? 1.06 : (hovered ? 1.03 : 1))
            .shadow(color: highlighted ? DT.Color.accent.opacity(isFocused ? 0.4 : 0.2) : .clear, radius: highlighted ? 12 : 0)

            Text(title)
                .contentFont(.caption, design: .default, weight: .semibold)
                .foregroundStyle(DT.Color.textPrimary)
                .lineLimit(1)
            // Every card keeps the subtitle's line, so a row stays level without one.
            Text(subtitle ?? "")
                .contentFont(.caption2)
                .foregroundStyle(DT.Color.textSecondary)
                .lineLimit(1, reservesSpace: true)
        }
        .animation(DT.Animation.fast, value: highlighted)
        .onPointerHover { hovered = $0 }
    }
}
