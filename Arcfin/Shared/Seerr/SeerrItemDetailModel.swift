// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import SeerrAPI
import JellyfinAPI
import AuthCore

/// A Seerr or TMDB title's page: its full detail, the server's own copy, related titles and
/// what's open or being requested, shared by every platform's `SeerrItemDetailView`.
@MainActor @Observable
final class SeerrItemDetailModel {
    let item: SeerrItem

    /// The server's own copy of this title, when it has one — drives the "View in Library"
    /// action that takes the place of Request once there's nothing left to request.
    private(set) var libraryItem: MediaItem?
    private(set) var detail: SeerrMediaDetail?
    /// The title's age rating for this region, e.g. "PG-13".
    private(set) var certification: String?
    private(set) var isLoadingDetail = false
    private(set) var heroTint: Color?
    private(set) var moreLikeThis: [SeerrItem] = []
    private(set) var companyRow: (name: String, items: [SeerrItem])?
    private(set) var keywordRow: (name: String, items: [SeerrItem])?
    /// The film series this movie is part of, when it has more than one movie.
    private(set) var collection: SeerrCollection?
    private(set) var isRequestingCollection = false
    var isConfirmingCollectionRequest = false
    var collectionRequestMessage: String?
    var openLibraryItem: MediaItem?
    var openSeerrItem: SeerrItem?
    var requestingItem: SeerrItem?

    init(item: SeerrItem) {
        self.item = item
    }

    /// A blunt title match is all a basic SeerrItem gives us for a movie, but a series' full
    /// detail (once loaded) carries real per-season status — this used to hide the Request
    /// button entirely the moment ANY request existed for the title, even if only one of
    /// several seasons had been asked for. Falls back to the title match before the detail
    /// fetch resolves, same as before this existed.
    func hasRequestableContent(seerrRepo: SeerrRepository) -> Bool {
        guard item.mediaType == .tv, let rows = detail?.seasonRows else { return seerrRepo.matchingRequest(for: item) == nil }
        return !SeerrSeasonSelection.unrequested(rows).isEmpty
    }

    var isAvailable: Bool {
        item.availabilityStatus == .available || (item.mediaType == .movie && libraryItem != nil)
    }

    /// Requesting needs Seerr; a title shown from TMDB alone still links to the library copy.
    func canRequest(seerrRepo: SeerrRepository) -> Bool {
        seerrRepo.isConfigured && !isAvailable && hasRequestableContent(seerrRepo: seerrRepo)
    }

    func loadDetail(seerrRepo: SeerrRepository) async {
        isLoadingDetail = true
        detail = await seerrRepo.mediaDetail(mediaType: item.mediaType, tmdbId: item.id)
        isLoadingDetail = false
    }

    func loadHeroTint() async {
        if let url = item.backdropURL ?? item.posterURL { heroTint = await AverageColor.load(from: url) }
    }

    func loadCertification(seerrRepo: SeerrRepository) async {
        certification = await seerrRepo.certification(for: item)
    }

    func loadLibraryItem(authManager: AuthManager) async {
        guard let cred = authManager.state.credential else { return }
        let header = authManager.authClient.authHeader(token: cred.accessToken)
        libraryItem = try? await JellyfinMediaClient().findItem(
            credential: cred, authHeader: header, tmdbId: item.id, isSeries: item.mediaType == .tv,
            title: item.title, year: item.year.flatMap { Int($0.prefix(4)) })
    }

    /// Related titles, the studio's (or network's) other titles, and others sharing the
    /// title's main keyword — each already filtered by the profile's parental controls.
    func loadDiscovery(seerrRepo: SeerrRepository) async {
        async let related = seerrRepo.relatedMedia(mediaType: item.mediaType, mediaId: item.id)
        async let info = seerrRepo.relatedInfo(mediaType: item.mediaType, tmdbId: item.id)
        moreLikeThis = Array(await related.filter { $0.id != item.id }.prefix(20))
        guard let info = await info else { return }
        if let id = info.collection?.id, let collection = await seerrRepo.collection(id: id), collection.parts.count > 1 {
            self.collection = collection
        }
        if let company = info.companies.first {
            let items = await seerrRepo.discoverByCompany(company.id, mediaType: item.mediaType).filter { $0.id != item.id }
            if items.count >= 3 { companyRow = (company.name, Array(items.prefix(20))) }
        }
        // Keyword discovery covers movies only.
        if item.mediaType == .movie, let keyword = info.keywords.first {
            let items = await seerrRepo.discoverByKeyword(keyword.id).filter { $0.id != item.id }
            if items.count >= 3 { keywordRow = (keyword.name, Array(items.prefix(20))) }
        }
    }

    /// The collection's movies that aren't in the library or asked for yet.
    func requestableParts(seerrRepo: SeerrRepository) -> [SeerrItem] {
        (collection?.parts ?? []).filter {
            $0.availabilityStatus != .available && $0.availabilityStatus != .partiallyAvailable && !seerrRepo.isRequested($0)
        }
    }

    func requestCollection(seerrRepo: SeerrRepository) async {
        let parts = requestableParts(seerrRepo: seerrRepo)
        guard !parts.isEmpty, let current = collection else { return }
        isRequestingCollection = true
        let requested = await seerrRepo.requestAll(parts)
        isRequestingCollection = false
        collectionRequestMessage = requested == parts.count
            ? String(localized: "Requested \(requested) movies from \(current.name).")
            : String(localized: "Requested \(requested) of \(parts.count) movies. Try the others from their own pages.")
        collection = await seerrRepo.collection(id: current.id) ?? current
    }

    func toggleWatchlist(seerrRepo: SeerrRepository) {
        HapticManager.impact(.light)
        Task {
            if seerrRepo.isInWatchlist(item) {
                try? await seerrRepo.removeFromWatchlist(item)
            } else {
                try? await seerrRepo.addToWatchlist(item)
            }
        }
    }
}
