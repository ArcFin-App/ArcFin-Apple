// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import JellyfinAPI
import SeerrAPI

/// Search's results and what's still loading, shared by every platform's `SearchView`.
@MainActor @Observable
final class SearchModel {
    private(set) var jellyfinResults: [MediaItem] = []
    private(set) var seerrResults: [SeerrItem] = []
    private(set) var isSearchingLibrary = false
    private(set) var isSearchingDiscover = false
    private var searchTask: Task<Void, Never>?

    var foundNothing: Bool {
        !isSearchingLibrary && !isSearchingDiscover && jellyfinResults.isEmpty && seerrResults.isEmpty
    }

    struct LibraryGroup {
        let title: String
        let items: [MediaItem]
        let isLandscape: Bool
    }

    /// Everything after the top result, by kind, in the server's order of relevance.
    var libraryGroups: [LibraryGroup] {
        let rest = Array(jellyfinResults.dropFirst())
        let groups = [
            LibraryGroup(title: "Movies", items: rest.filter { $0.type == .movie }, isLandscape: false),
            LibraryGroup(title: "Shows", items: rest.filter { $0.type == .series }, isLandscape: false),
            LibraryGroup(title: "Episodes", items: rest.filter { $0.type == .episode }, isLandscape: true),
            LibraryGroup(title: "Collections", items: rest.filter { ![.movie, .series, .episode].contains($0.type) }, isLandscape: false),
        ]
        return groups.filter { !$0.items.isEmpty }
    }

    /// Only what isn't on the server: anything it has is in the library results above.
    func discoverResults(in mediaRepo: MediaRepository) -> [SeerrItem] {
        seerrResults.filter { !mediaRepo.hasInLibrary($0) }
    }

    /// Waits for a short pause in typing, and drops any search still running for an older
    /// query: every keystroke used to fire both servers, and a slow response for "the" could
    /// land after the one for "the office" and replace the right results with stale ones.
    func search(_ query: String, authManager: AuthManager, mediaRepo: MediaRepository, seerrRepo: SeerrRepository) {
        searchTask?.cancel()
        guard !query.isEmpty else {
            jellyfinResults = []
            seerrResults = []
            isSearchingLibrary = false
            isSearchingDiscover = false
            return
        }
        isSearchingLibrary = true
        isSearchingDiscover = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            // Each server's results show as they arrive, so a slow one doesn't hold up the other.
            await withDiscardingTaskGroup { group in
                group.addTask { @MainActor in
                    let jellyfin = await mediaRepo.searchIfAuthenticated(
                        query: query,
                        authState: authManager.state,
                        authClient: authManager.authClient
                    )
                    guard !Task.isCancelled else { return }
                    self.jellyfinResults = jellyfin
                    self.isSearchingLibrary = false
                }
                group.addTask { @MainActor in
                    let seerr = await seerrRepo.search(query: query)
                    guard !Task.isCancelled else { return }
                    self.seerrResults = seerr
                    self.isSearchingDiscover = false
                }
            }
        }
    }
}

/// The recent searches list, stored as JSON in the "recentSearches" setting.
enum RecentSearches {
    static let key = "recentSearches"
    private static let limit = 8

    static func decode(_ data: Data) -> [String] {
        (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    /// `data` with `term` moved to the front, or unchanged for a term too short to keep.
    static func adding(_ term: String, to data: Data) -> Data {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return data }
        var updated = decode(data).filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
        updated.insert(trimmed, at: 0)
        return (try? JSONEncoder().encode(Array(updated.prefix(limit)))) ?? Data()
    }
}

enum SearchText {
    static func kindLabel(_ item: MediaItem) -> String {
        switch item.type {
        case .movie: "Movie"
        case .series: "Show"
        case .episode: "Episode"
        case .boxSet: "Collection"
        default: "Title"
        }
    }

    static func episodeCode(_ item: MediaItem) -> String? {
        guard let s = item.parentIndexNumber, let e = item.indexNumber else { return nil }
        return "S\(s)E\(e)"
    }

    /// An episode's own Primary image is a landscape screenshot — forced into this grid's
    /// portrait 2:3 cards it rendered badly (cards visually collided). Episodes use their
    /// series' portrait poster here instead, same as any other result.
    @MainActor
    static func posterImageURL(for item: MediaItem, in mediaRepo: MediaRepository) -> URL? {
        guard item.type == .episode, let seriesId = item.seriesId, let tag = item.seriesPrimaryImageTag,
              let base = mediaRepo.baseURL, let token = mediaRepo.accessToken
        else { return mediaRepo.imageURL(for: item) }
        return JellyfinMediaClient.imageURL(baseURL: base, itemID: seriesId, tag: tag, type: .primary, fillWidth: 300, token: token)
    }
}
