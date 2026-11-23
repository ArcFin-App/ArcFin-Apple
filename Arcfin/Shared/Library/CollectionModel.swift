// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI
import AuthCore

enum CollectionSort: String, CaseIterable, Identifiable {
    case release = "Release Order", title = "Title", rating = "Rating"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .release: String(localized: "Release Order")
        case .title: String(localized: "Title")
        case .rating: String(localized: "Rating")
        }
    }
}

/// A collection's titles, cast and playback, shared by the iPhone, iPad and Mac `CollectionDetailView`.
@MainActor @Observable
final class CollectionModel {
    private(set) var detail: MediaItemDetail?
    private(set) var items: [MediaItem] = []
    private(set) var isLoading = true
    var selectedItem: MediaItem?
    var selectedPerson: MediaPerson?
    private(set) var heroTint: Color?
    var playbackRequest: MediaDetailView.PlaybackRequest?

    private let client = JellyfinMediaClient()

    func sortedItems(by sort: CollectionSort) -> [MediaItem] {
        switch sort {
        case .release:
            items.sorted { ($0.premiereDate ?? .distantFuture, $0.productionYear ?? .max) < ($1.premiereDate ?? .distantFuture, $1.productionYear ?? .max) }
        case .title:
            items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .rating:
            items.sorted { ($0.communityRating ?? 0) > ($1.communityRating ?? 0) }
        }
    }

    /// Movies and episodes can be played straight through; a series in a collection opens instead.
    func playable(by sort: CollectionSort) -> [MediaItem] {
        sortedItems(by: sort).filter { $0.type == .movie || $0.type == .episode }
    }

    var watchedCount: Int { items.filter { $0.userData?.played == true }.count }

    var yearSpan: String? {
        let years = items.compactMap(\.productionYear)
        guard let first = years.min(), let last = years.max() else { return nil }
        return first == last ? "\(first)" : "\(first)–\(last)"
    }

    func nextToPlay(by sort: CollectionSort) -> MediaItem? {
        playable(by: sort).first { $0.userData?.played != true }
    }

    func playLabel(by sort: CollectionSort) -> String {
        guard let next = nextToPlay(by: sort) else { return String(localized: "Play from Start") }
        if (next.userData?.playbackPositionTicks ?? 0) > 0 { return String(localized: "Resume \(next.name)") }
        return watchedCount == 0 ? String(localized: "Play") : String(localized: "Continue with \(next.name)")
    }

    func playThrough(by sort: CollectionSort) {
        let playable = playable(by: sort)
        guard let start = nextToPlay(by: sort) ?? playable.first, let index = playable.firstIndex(of: start) else { return }
        PlayQueue.start(Array(playable[index...]))
        let resume = start.userData?.played == true ? 0 : (start.userData?.playbackPositionTicks ?? 0)
        playbackRequest = MediaDetailView.PlaybackRequest(item: start, startTicks: resume)
    }

    func shuffle(by sort: CollectionSort) {
        let shuffled = playable(by: sort).shuffled()
        guard let first = shuffled.first else { return }
        PlayQueue.start(shuffled)
        playbackRequest = MediaDetailView.PlaybackRequest(item: first, startTicks: 0)
    }

    func load(_ collection: MediaItem, authManager: AuthManager) async {
        guard let cred = authManager.state.credential else {
            isLoading = false
            return
        }
        let header = authManager.authClient.authHeader(token: cred.accessToken)
        async let fetchedDetail = client.getItemDetail(credential: cred, authHeader: header, itemId: collection.id)
        async let fetchedItems = allItems(in: collection.id, credential: cred, header: header)
        detail = try? await fetchedDetail
        if let fetched = try? await fetchedItems { items = fetched }
        isLoading = false
    }

    /// Every title, a page at a time: one page of 200 cut large collections off silently, and
    /// Play All and Shuffle with them.
    private func allItems(in collectionId: String, credential cred: ServerCredential, header: String) async throws -> [MediaItem] {
        var items: [MediaItem] = []
        var offset = 0
        var total = 0
        repeat {
            let page = try await client.getLibraryItems(
                credential: cred, authHeader: header, libraryId: collectionId, startIndex: offset, limit: 200,
                recursive: false, sortBy: "PremiereDate,ProductionYear,SortName"
            )
            items += page.items
            total = page.total
            offset += page.consumed
            if page.consumed == 0 { break }
        } while offset < total
        return items
    }

    func loadHeroTint(_ collection: MediaItem, mediaRepo: MediaRepository) async {
        guard let url = mediaRepo.imageURL(for: collection, type: .backdrop, fillWidth: 120) else { return }
        heroTint = await AverageColor.load(from: url)
    }
}
