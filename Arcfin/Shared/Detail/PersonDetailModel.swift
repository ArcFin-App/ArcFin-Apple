// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import JellyfinAPI
import SeerrAPI
import AuthCore

/// A person's page: their titles in the library, their bio, and Seerr's list of their work,
/// shared by every platform's `PersonDetailView`.
@MainActor @Observable
final class PersonDetailModel {
    let person: MediaPerson

    private(set) var items: [MediaItem] = []
    private(set) var isLoading = true
    private(set) var detail: MediaPersonDetail?
    private(set) var seerrCredits: [SeerrPersonCredit] = []

    private let client = JellyfinMediaClient()

    init(person: MediaPerson) {
        self.person = person
    }

    /// Titles Seerr knows this person appears in that aren't already in the Jellyfin library,
    /// already available/processing there, or already requested — matched as
    /// SeerrRepository.matchingRequest does. Worked out after loading
    /// and when the requests change, not on every redraw.
    private(set) var missingCredits: [SeerrPersonCredit] = []

    func refreshMissingCredits(requests: [SeerrRequestItem]) {
        missingCredits = Self.missingCredits(seerrCredits, library: items, requests: requests)
    }

    static func missingCredits(_ credits: [SeerrPersonCredit], library: [MediaItem],
                               requests: [SeerrRequestItem]) -> [SeerrPersonCredit] {
        struct Key: Hashable { let type: RequestMediaType; let tmdbId: Int?; let title: String? }
        let libraryTmdbIds = Set(library.compactMap(\.tmdbId))
        // By tmdbId, or by title for a request without one.
        let requested = Set(requests.map { Key(type: $0.mediaType, tmdbId: $0.tmdbId, title: $0.tmdbId == nil ? $0.mediaTitle : nil) })
        return credits.filter { credit in
            !libraryTmdbIds.contains(credit.id)
                && credit.mediaStatus != .available
                && credit.mediaStatus != .processing
                && credit.mediaStatus != .partiallyAvailable
                && !requested.contains(Key(type: credit.mediaType, tmdbId: credit.id, title: nil))
                && !requested.contains(Key(type: credit.mediaType, tmdbId: nil, title: credit.title))
        }
    }

    func load(authManager: AuthManager, seerrRepo: SeerrRepository) async {
        isLoading = true
        defer { isLoading = false }
        guard let cred = authManager.state.credential else { return }
        let header = authManager.authClient.authHeader(token: cred.accessToken)
        async let fetchedItems = client.getPersonItems(credential: cred, authHeader: header, personId: person.id)
        async let fetchedDetail = client.getPersonDetail(credential: cred, authHeader: header, personId: person.id)
        items = (try? await fetchedItems) ?? []
        detail = try? await fetchedDetail
        if let tmdbId = detail?.tmdbId, seerrRepo.isConfigured {
            seerrCredits = await seerrRepo.personCredits(tmdbId: tmdbId) ?? []
        }
        refreshMissingCredits(requests: seerrRepo.requests)
    }
}
