// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// One Wikidata "award received" (P166) statement for a title.
/// `nonisolated` opts out of the app target's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` —
/// without it, the synthesized Equatable/Hashable conformance is MainActor-isolated and can't
/// be used from inside WikidataAwardsClient's own (non-main) actor isolation domain.
public nonisolated struct WikidataAward: Sendable, Equatable, Hashable {
    public let name: String
    public let year: Int?
}

/// Deliberately its own tiny type rather than reusing JellyfinAPI.MediaType or
/// SeerrAPI.RequestMediaType — this client is called from both a Jellyfin MediaItem's detail
/// screen and a Seerr-sourced item's detail screen, and shouldn't need to import (or reconcile)
/// either package's own movie/tv enum just to pick a Wikidata property.
public nonisolated enum WikidataMediaKind: Sendable {
    case movie, tv
}

/// Pulls award data straight from Wikidata's public SPARQL endpoint, joined on the title's own
/// TMDB id (already decoded onto MediaItem/MediaItemDetail from Jellyfin's ProviderIds) — no
/// Jellyfin plugin, no extra server-side setup, nothing to configure.
public actor WikidataAwardsClient {
    public static let shared = WikidataAwardsClient()

    private let session: URLSession
    private var cache: [String: [WikidataAward]] = [:]
    private var inFlight: [String: Task<[WikidataAward], Never>] = [:]

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = true
        config.timeoutIntervalForResource = 20
        session = URLSession(configuration: config)
    }

    public func awards(tmdbId: Int, mediaType: WikidataMediaKind) async -> [WikidataAward] {
        let key = "\(mediaType):\(tmdbId)"
        if let cached = cache[key] { return cached }
        if let existing = inFlight[key] { return await existing.value }

        let task = Task<[WikidataAward], Never> { [weak self] in
            await self?.fetch(tmdbId: tmdbId, mediaType: mediaType) ?? []
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        cache[key] = result
        return result
    }

    private func fetch(tmdbId: Int, mediaType: WikidataMediaKind) async -> [WikidataAward] {
        // P4947 = TMDB movie ID, P4983 = TMDB TV series ID — Wikidata keeps these separate
        // per-media-type, same split Seerr/TMDB itself makes.
        let tmdbProperty = mediaType == .tv ? "P4983" : "P4947"
        let query = """
        SELECT ?awardLabel ?pointInTime WHERE {
          ?item wdt:\(tmdbProperty) "\(tmdbId)".
          ?item p:P166 ?statement.
          ?statement ps:P166 ?award.
          OPTIONAL { ?statement pq:P585 ?pointInTime. }
          SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
        }
        """
        var comps = URLComponents(string: "https://query.wikidata.org/sparql")!
        comps.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "format", value: "json"),
        ]
        guard let url = comps.url else { return [] }
        var request = URLRequest(url: url)
        // Wikidata's own etiquette asks for an identifying User-Agent on query service traffic —
        // https://meta.wikimedia.org/wiki/User-Agent_policy
        request.setValue("Arcfin/1.0 (https://github.com/ArcFin/ArcFin)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/sparql-results+json", forHTTPHeaderField: "Accept")

        await withCheckedContinuation { PathWait(continuation: $0).start(timeoutSeconds: 6) }
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode)
        else { return [] }

        struct SPARQLResponse: Decodable {
            struct Results: Decodable { let bindings: [Binding] }
            struct Binding: Decodable {
                struct Value: Decodable { let value: String }
                let awardLabel: Value?
                let pointInTime: Value?
            }
            let results: Results
        }
        guard let decoded = try? JSONDecoder().decode(SPARQLResponse.self, from: data) else { return [] }

        let formatter = ISO8601DateFormatter()
        var seen = Set<WikidataAward>()
        var ordered: [WikidataAward] = []
        for binding in decoded.results.bindings {
            guard let name = binding.awardLabel?.value else { continue }
            // Parenthesized: `a?.b.flatMap{}` lets the `?` propagate through the whole chain,
            // leaving `.value` non-optional at the point `.flatMap` is called — which then
            // resolves to String's own Sequence.flatMap (over Character), not Optional.flatMap.
            let year = (binding.pointInTime?.value)
                .flatMap { formatter.date(from: $0) }
                .map { Calendar(identifier: .gregorian).component(.year, from: $0) }
            let award = WikidataAward(name: name, year: year)
            if seen.insert(award).inserted { ordered.append(award) }
        }
        return ordered
    }
}
