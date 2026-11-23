// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

/// Every title on one of Home's shelves, as a grid. Each platform's `ShelfSeeAllView` picks
/// the columns.
struct ShelfSeeAllGrid: View {
    let items: [MediaItem]
    let isLandscape: Bool
    let columns: [GridItem]
    /// The shelf's query: every title it covers, a page at a time, in place of the row's.
    var query: ShelfQuery? = nil
    let select: (MediaItem) -> Void

    @Environment(MediaRepository.self) private var mediaRepo
    @State private var list: MusicPagedList<MediaItem>?

    /// The row's titles until the first page is in, so the grid isn't empty meanwhile.
    private var shown: [MediaItem] {
        guard let list, list.hasLoaded, !list.hasFailed || !list.items.isEmpty else { return items }
        return list.items
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(shown) { item in
                    Button { select(item) } label: {
                        ShelfSeeAllCard(
                            imageURL: imageURL(for: item),
                            isLandscape: isLandscape,
                            title: cardTitle(item),
                            subtitle: cardSubtitle(item)
                        )
                    }
                    .buttonStyle(.plain)
                    .task { await list?.rowAppeared(item) }
                }
            }
            .padding(DT.Spacing.pagePad)
            if list?.isLoading == true, list?.hasLoaded == true {
                ProgressView().padding(.bottom, DT.Spacing.pagePad)
            }
        }
        .screenBackground()
        .task {
            guard let query, list == nil else { return }
            let pages = MusicPagedList<MediaItem> { start in
                let page = try await MusicAPI.call {
                    try await $0.getLibraryItems(
                        credential: $1, authHeader: $2, libraryId: query.parentID, startIndex: start, limit: 60,
                        includeItemTypes: query.itemTypes.isEmpty ? nil : query.itemTypes, genres: query.genres,
                        minCommunityRating: query.minCommunityRating, isPlayed: query.isPlayed,
                        isFavorite: query.isFavorite, sortBy: query.sortBy, sortOrder: query.sortOrder)
                }
                return (page.items, page.total)
            }
            list = pages
            await pages.loadIfNeeded()
        }
    }

    private func imageURL(for item: MediaItem) -> URL? {
        guard isLandscape else { return mediaRepo.imageURL(for: item) }
        if item.type == .episode {
            return mediaRepo.imageURL(for: item, type: .primary, fillWidth: 500)
        }
        return mediaRepo.imageURL(for: item, type: .thumb, fillWidth: 500)
            ?? mediaRepo.imageURL(for: item, type: .backdrop, fillWidth: 500)
    }

    private func cardTitle(_ item: MediaItem) -> String {
        item.type == .episode ? (item.seriesName ?? item.name) : item.name
    }

    private func cardSubtitle(_ item: MediaItem) -> String? {
        guard item.type == .episode else {
            return item.productionYear.map { String($0) }
        }
        let s = item.parentIndexNumber.map { "S\($0)" }
        let e = item.indexNumber.map { "E\($0)" }
        let code = [s, e].compactMap { $0 }.joined()
        return [code.isEmpty ? nil : code, item.name].compactMap { $0 }.joined(separator: " · ")
    }
}

// MARK: - Grid card

private struct ShelfSeeAllCard: View {
    let imageURL: URL?
    let isLandscape: Bool
    let title: String
    let subtitle: String?

    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack {
                if let imageURL {
                    CachedAsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFill()
                        default: DT.Color.backgroundSecondary
                        }
                    }
                    .clipped()
                } else {
                    DT.Color.backgroundSecondary
                }
            }
            .aspectRatio(isLandscape ? 16 / 9 : 2 / 3, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.card))
            .overlay(
                RoundedRectangle(cornerRadius: DT.Radius.card)
                    .stroke(hovered ? DT.Color.accent.opacity(0.35) : DT.Color.textPrimary.opacity(0.06), lineWidth: 1)
            )
            .scaleEffect(hovered ? 1.03 : 1)
            .shadow(color: hovered ? DT.Color.accent.opacity(0.2) : .clear, radius: hovered ? 12 : 0)

            Text(title)
                .contentFont(.caption, design: .default, weight: .semibold)
                .foregroundStyle(DT.Color.textPrimary)
                .lineLimit(1)
            if let subtitle {
                Text(subtitle)
                    .contentFont(.caption2, design: .default)
                    .foregroundStyle(DT.Color.textSecondary)
                    .lineLimit(1)
            }
        }
        .animation(DT.Animation.fast, value: hovered)
        .onPointerHover { hovered = $0 }
    }
}
