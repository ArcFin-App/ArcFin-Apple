import SwiftUI
import JellyfinAPI
import JellyseerrAPI
import AuthCore

struct SearchView: View {
    @Binding var query: String

    @Environment(AuthManager.self) private var authManager
    @Environment(MediaRepository.self) private var mediaRepo
    @Environment(JellyseerrRepository.self) private var seerrRepo

    @State private var jellyfinResults: [MediaItem] = []
    @State private var seerrResults: [SeerrItem] = []
    @State private var isSearching = false

    var body: some View {
        Group {
            if query.isEmpty {
                ContentUnavailableView(
                    "Search",
                    systemImage: "magnifyingglass",
                    description: Text("Find movies, shows, and more.")
                )
            } else if !isSearching && jellyfinResults.isEmpty && seerrResults.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                        // ── Library section ──────────────────────────────────
                        if !jellyfinResults.isEmpty {
                            ShelfRow(title: "Library", onSeeAll: nil) {
                                ForEach(jellyfinResults) { item in
                                    PosterCard(
                                        title: item.name,
                                        subtitle: item.productionYear.map { "\($0)" },
                                        imageURL: mediaRepo.imageURL(for: item)
                                    )
                                }
                            }
                        }

                        // ── Discover via Jellyseerr ──────────────────────────
                        if seerrRepo.isConfigured && !seerrResults.isEmpty {
                            ShelfRow(title: "Discover via Jellyseerr", onSeeAll: nil) {
                                ForEach(seerrResults) { item in
                                    PosterCard(
                                        title: item.title,
                                        subtitle: item.year,
                                        imageURL: item.posterURL
                                    )
                                }
                            }
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
        .background(DT.Color.backgroundPrimary)
        .onChange(of: query) { _, newValue in
            performSearch(query: newValue)
        }
    }

    private func performSearch(query: String) {
        guard !query.isEmpty else {
            jellyfinResults = []
            seerrResults = []
            return
        }
        isSearching = true
        Task {
            async let jellyTask: [MediaItem] = {
                if case .authenticated(let cred) = authManager.state {
                    return await mediaRepo.search(query: query, credential: cred, authClient: authManager.authClient)
                }
                return []
            }()
            async let seerrTask = seerrRepo.search(query: query)

            jellyfinResults = await jellyTask
            seerrResults    = await seerrTask
            isSearching = false
        }
    }
}
