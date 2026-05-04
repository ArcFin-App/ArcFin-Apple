import SwiftUI
import JellyfinAPI

struct SearchView: View {
    @Binding var query: String
    @Environment(MediaRepository.self) private var mediaRepo

    private var results: [MediaItem] {
        guard !query.isEmpty else { return [] }
        let q = query.lowercased()
        let pool = (mediaRepo.recentlyAdded + mediaRepo.continueWatching)
        // deduplicate by id
        var seen = Set<String>()
        return pool.filter {
            guard seen.insert($0.id).inserted else { return false }
            return $0.name.lowercased().contains(q)
                || ($0.seriesName?.lowercased().contains(q) ?? false)
        }
    }

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: DT.Spacing.shelfGap)]

    var body: some View {
        Group {
            if query.isEmpty {
                emptyState
            } else if results.isEmpty {
                noResults
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: DT.Spacing.shelfGap) {
                        ForEach(results) { item in
                            PosterCard(
                                title: item.name,
                                subtitle: item.productionYear.map { "\($0)" },
                                imageURL: mediaRepo.imageURL(for: item)
                            )
                        }
                    }
                    .padding(DT.Spacing.pagePad)
                }
            }
        }
        .background(DT.Color.backgroundPrimary)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "Search Arcfin",
            systemImage: "magnifyingglass",
            description: Text("Find movies, shows, and more from your Jellyfin library.")
        )
    }

    private var noResults: some View {
        ContentUnavailableView.search(text: query)
    }
}
