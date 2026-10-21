// SPDX-License-Identifier: AGPL-3.0-or-later

#if os(iOS)
import AppIntents
import CoreSpotlight
import Foundation
import SeerrAPI

// MARK: - Snapshot

/// The personal slice of Seerr that Spotlight and Siri can see: the signed-in user's watchlist
/// and their requests. Kept as a small JSON snapshot so an intent running outside the app can
/// answer without logging in to Seerr. The rest of Seerr's catalog is far too large to index.
nonisolated struct SeerrSpotlightEntry: Codable, Equatable {
    var tmdbId: Int
    var mediaType: String
    var title: String
    var year: String?
    var posterPath: String?
    var backdropPath: String?
    var availability: Int?
    /// "On your watchlist", "Requested", "Approved", "Declined" or "Available".
    var status: String

    var id: String { "\(mediaType)-\(tmdbId)" }

    var seerrItem: SeerrItem? {
        guard let type = RequestMediaType(rawValue: mediaType) else { return nil }
        return SeerrItem(
            id: tmdbId, title: title, mediaType: type, posterPath: posterPath,
            backdropPath: backdropPath, year: year,
            availabilityStatus: availability.flatMap(SeerrAvailabilityStatus.init(rawValue:)))
    }
}

nonisolated enum SeerrSpotlightStore {
    private static let key = "arcfin.seerrSpotlight"

    static func load() -> [SeerrSpotlightEntry] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let entries = try? JSONDecoder().decode([SeerrSpotlightEntry].self, from: data)
        else { return [] }
        return entries
    }

    static func save(_ entries: [SeerrSpotlightEntry]) {
        if let data = try? JSONEncoder().encode(entries) { UserDefaults.standard.set(data, forKey: key) }
    }

    static func clear() { UserDefaults.standard.removeObject(forKey: key) }

    static func entry(id: String) -> SeerrSpotlightEntry? { load().first { $0.id == id } }
}

// MARK: - Entity

/// A title on the user's Seerr watchlist or requests, as Spotlight and Siri see it. Distinct
/// from `MediaEntity` because it usually isn't in the library yet: opening it shows Seerr's
/// page (with Request), not a playable title.
struct SeerrTitleEntity: AppEntity, IndexedEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("Seerr Title"),
        numericFormat: LocalizedStringResource("\(placeholder: .int) Seerr titles"))
    static let defaultQuery = SeerrTitleQuery()

    let id: String

    @Property(title: "Title")
    var title: String

    @Property(title: "Status")
    var status: String

    var kind: String = ""
    var posterURL: URL?
    var thumbnailData: Data?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: LocalizedStringResource(stringLiteral: "Seerr · \(kind) · \(status)"),
            image: thumbnailData.map { DisplayRepresentation.Image(data: $0) })
    }

    var attributeSet: CSSearchableItemAttributeSet {
        let set = defaultAttributeSet
        set.contentDescription = "Seerr · \(status)"
        set.thumbnailData = thumbnailData
        set.keywords = ["Seerr", kind, status]
        return set
    }

    init(entry: SeerrSpotlightEntry) {
        id = entry.id
        title = entry.title
        status = entry.status
        kind = entry.mediaType == "tv" ? "Series" : "Movie"
        posterURL = entry.posterPath.flatMap { URL(string: "https://image.tmdb.org/t/p/w342\($0)") }
    }
}

struct SeerrTitleQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [SeerrTitleEntity] {
        let wanted = Set(identifiers)
        return SeerrSpotlightStore.load().filter { wanted.contains($0.id) }.map(SeerrTitleEntity.init(entry:))
    }

    func entities(matching string: String) async throws -> [SeerrTitleEntity] {
        SeerrSpotlightStore.load()
            .filter { $0.title.localizedCaseInsensitiveContains(string) }
            .map(SeerrTitleEntity.init(entry:))
    }

    func suggestedEntities() async throws -> [SeerrTitleEntity] {
        SeerrSpotlightStore.load().prefix(10).map(SeerrTitleEntity.init(entry:))
    }
}

struct OpenSeerrTitleIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Seerr Title"
    static let description = IntentDescription("Opens a title from your Seerr watchlist or requests.")

    @Parameter(title: "Title")
    var target: SeerrTitleEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        ArcfinRouting.openSeerrTitle(id: target.id)
        return .result()
    }
}

// MARK: - Indexing

enum SeerrSpotlightIndexer {
    /// Replaces what Spotlight holds for Seerr with the current watchlist and requests.
    static func index(watchlist: [SeerrItem], requests: [SeerrRequestItem]) async {
        var entries: [String: SeerrSpotlightEntry] = [:]
        for item in watchlist {
            let status = item.availabilityStatus == .available ? "Available" : "On your watchlist"
            let entry = SeerrSpotlightEntry(
                tmdbId: item.id, mediaType: item.mediaType.rawValue, title: item.title, year: item.year,
                posterPath: item.posterPath, backdropPath: item.backdropPath,
                availability: item.availabilityStatus?.rawValue, status: status)
            entries[entry.id] = entry
        }
        // A request is more specific than the watchlist, so it wins when a title is on both.
        for request in requests {
            guard let tmdbId = request.tmdbId, request.mediaTitle != "Unknown" else { continue }
            let status: String
            if request.mediaStatus == .available { status = "Available" }
            else {
                switch request.status {
                case .pending: status = "Requested"
                case .approved: status = "Approved"
                case .declined: status = "Declined"
                }
            }
            let entry = SeerrSpotlightEntry(
                tmdbId: tmdbId, mediaType: request.mediaType.rawValue, title: request.mediaTitle, year: nil,
                posterPath: request.posterPath, backdropPath: request.backdropPath,
                availability: request.mediaStatus?.rawValue, status: status)
            entries[entry.id] = entry
        }
        let all = Array(entries.values).sorted { $0.title < $1.title }.prefix(120)
        SeerrSpotlightStore.save(Array(all))

        let entities = await withTaskGroup(of: SeerrTitleEntity.self) { group in
            for entry in all {
                group.addTask {
                    var entity = SeerrTitleEntity(entry: entry)
                    if let url = entity.posterURL, let (data, _) = try? await URLSession.shared.data(from: url) {
                        entity.thumbnailData = data
                    }
                    return entity
                }
            }
            var result: [SeerrTitleEntity] = []
            for await entity in group { result.append(entity) }
            return result
        }
        guard !entities.isEmpty else { return }
        try? await CSSearchableIndex.default().indexAppEntities(entities)
    }
}
#endif
