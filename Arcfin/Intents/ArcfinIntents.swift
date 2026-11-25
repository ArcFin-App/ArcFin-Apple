// SPDX-License-Identifier: AGPL-3.0-or-later

#if !os(tvOS)
import AppIntents
import AuthCore
import CoreImage
import CoreSpotlight
import Foundation
import JellyfinAPI
import Security
import Vision
// Not in the simulator SDK.
#if canImport(VisualIntelligence)
import VisualIntelligence
#endif

// MARK: - Session for intents

/// Intents run outside the view hierarchy (Siri, Shortcuts, Spotlight), so they can't reach
/// AuthManager. They read the active profile straight from the Keychain instead — and refuse
/// when that profile has an app-lock PIN, so Siri and Spotlight can't be used to browse a
/// library the lock screen is meant to protect.
nonisolated enum IntentSession {
    static func credential() -> ServerCredential? {
        profile().flatMap { $0.pinLocked ? nil : $0.credential }
    }

    /// The active profile even when it has an app-lock PIN, for news that shows nothing from the
    /// library, or hides its titles when `pinLocked`.
    static func profile() -> (credential: ServerCredential, pinLocked: Bool)? {
        let store = KeychainStore()
        guard let all = try? store.allServers(), !all.isEmpty else { return nil }
        let storedID = UserDefaults.standard.string(forKey: "arcfin.activeProfileID").flatMap { UUID(uuidString: $0) }
        guard let credential = all.first(where: { $0.id == storedID }) ?? all.first else { return nil }
        // While the device is locked the PIN can't be read yet, and that counts as one.
        do {
            return (credential, try store.loadPin(for: credential.id) != nil)
        } catch KeychainError.unexpectedStatus(let status) where status == errSecInteractionNotAllowed {
            return (credential, true)
        } catch {
            return (credential, false)
        }
    }

    static func authHeader(for credential: ServerCredential) -> String {
        JellyfinAuthClient().authHeader(token: credential.accessToken)
    }
}

// MARK: - Entity

/// A movie, series or episode as Siri, Shortcuts and Spotlight see it. Indexed entities feed
/// Spotlight's semantic index, so people can find a title by describing it.
struct MediaEntity: AppEntity, IndexedEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("Title"),
        numericFormat: LocalizedStringResource("\(placeholder: .int) titles"))
    static let defaultQuery = MediaEntityQuery()

    let id: String

    @Property(title: "Title")
    var title: String

    @Property(title: "Kind")
    var kind: String

    @Property(title: "Year")
    var year: Int?

    /// Not exposed as properties — they only enrich how the entity is presented and indexed.
    var overview: String?
    var rating: Double?
    var thumbnailData: Data?

    var subtitle: String? {
        [kind, year.map(String.init)].compactMap { $0 }.joined(separator: " · ")
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: subtitle.map { LocalizedStringResource(stringLiteral: $0) },
            image: thumbnailData.map { DisplayRepresentation.Image(data: $0) })
    }

    /// What Spotlight shows and matches on: a description, a poster, and the kind of title as
    /// keywords so "movie" or "series" in a search finds it.
    var attributeSet: CSSearchableItemAttributeSet {
        let set = defaultAttributeSet
        set.contentDescription = overview
        set.thumbnailData = thumbnailData
        set.rating = rating.map { NSNumber(value: $0) }
        set.keywords = [kind, kind == "Series" ? "show" : "film"]
        return set
    }

    init(item: MediaItem) {
        self.id = item.id
        self.title = item.type == .episode ? (item.seriesName.map { "\($0) – \(item.name)" } ?? item.name) : item.name
        switch item.type {
        case .movie: self.kind = "Movie"
        case .series: self.kind = "Series"
        case .episode: self.kind = "Episode"
        default: self.kind = "Title"
        }
        self.year = item.productionYear
        self.overview = item.overview
        self.rating = item.communityRating
    }
}

struct MediaEntityQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [MediaEntity] {
        guard let credential = IntentSession.credential() else { return [] }
        let header = IntentSession.authHeader(for: credential)
        let client = JellyfinMediaClient()
        var result: [MediaEntity] = []
        for id in identifiers {
            if let detail = try? await client.getItemDetail(credential: credential, authHeader: header, itemId: id) {
                result.append(MediaEntity(item: detail.item))
            }
        }
        return result
    }

    func entities(matching string: String) async throws -> [MediaEntity] {
        guard let credential = IntentSession.credential() else { return [] }
        let items = try await JellyfinMediaClient().search(
            credential: credential, authHeader: IntentSession.authHeader(for: credential), query: string, limit: 15)
        return items
            .filter { $0.type == .movie || $0.type == .series || $0.type == .episode }
            .map(MediaEntity.init(item:))
    }

    func suggestedEntities() async throws -> [MediaEntity] {
        guard let credential = IntentSession.credential() else { return [] }
        let items = try await JellyfinMediaClient().getContinueWatching(
            credential: credential, authHeader: IntentSession.authHeader(for: credential), limit: 8)
        return items.map(MediaEntity.init(item:))
    }
}

/// A live TV channel as Siri and Shortcuts see it.
struct ChannelEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("Channel"),
        numericFormat: LocalizedStringResource("\(placeholder: .int) channels"))
    static let defaultQuery = ChannelEntityQuery()

    let id: String

    @Property(title: "Name")
    var name: String

    var number: String?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: number.map { LocalizedStringResource(stringLiteral: $0) })
    }

    init(channel: LiveTVChannel) {
        id = channel.id
        name = channel.name
        number = channel.number
    }
}

struct ChannelEntityQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [ChannelEntity] {
        guard let credential = IntentSession.credential() else { return [] }
        let header = IntentSession.authHeader(for: credential)
        let client = JellyfinMediaClient()
        var result: [ChannelEntity] = []
        for id in identifiers {
            if let channel = try? await client.getLiveTVChannel(credential: credential, authHeader: header, channelId: id) {
                result.append(ChannelEntity(channel: channel))
            }
        }
        return result
    }

    func entities(matching string: String) async throws -> [ChannelEntity] {
        guard let credential = IntentSession.credential() else { return [] }
        let found = try await JellyfinMediaClient().searchLiveTV(
            credential: credential, authHeader: IntentSession.authHeader(for: credential),
            query: string, includePrograms: false, limit: 15)
        return found.channels.map(ChannelEntity.init(channel:))
    }

    /// The channels watched most recently on this device.
    func suggestedEntities() async throws -> [ChannelEntity] {
        guard let credential = IntentSession.credential() else { return [] }
        let recents = await MainActor.run { LiveTVRecents.channels(for: credential.userID) }
        return recents.map(ChannelEntity.init(channel:))
    }
}

// MARK: - Intents

/// Opening an entity is also what a tap on its Spotlight result runs. It reuses the same
/// pending-item buffer + notification the Top Shelf deep link and widgets use, so it lands
/// on the title's detail screen cold or warm.
struct OpenTitleIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Title"
    static let description = IntentDescription("Opens a movie, series or episode in Arcfin.")

    @Parameter(title: "Title")
    var target: MediaEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        ArcfinRouting.openItem(id: target.id)
        return .result()
    }
}

struct ContinueWatchingIntent: AppIntent {
    static let title: LocalizedStringResource = "Continue Watching"
    static let description = IntentDescription("Opens whatever you were watching most recently.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let credential = IntentSession.credential() else {
            return .result(dialog: "Open Arcfin and sign in first.")
        }
        let items = try await JellyfinMediaClient().getContinueWatching(
            credential: credential, authHeader: IntentSession.authHeader(for: credential), limit: 1)
        guard let first = items.first else {
            return .result(dialog: "You have nothing to continue watching.")
        }
        ArcfinRouting.openItem(id: first.id)
        return .result(dialog: "Opening \(first.name).")
    }
}

struct ShowDownloadsIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Downloads"
    static let description = IntentDescription("Opens your downloaded titles.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        ArcfinRouting.showDownloads()
        return .result()
    }
}

struct PlayTitleIntent: AppIntent {
    static let title: LocalizedStringResource = "Play Title"
    static let description = IntentDescription("Plays a movie or episode from where you left off, or a series from its next episode.")
    static let openAppWhenRun = true

    @Parameter(title: "Title")
    var target: MediaEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        WatchRoute.open(id: target.id)
        return .result()
    }
}

/// Plays a live TV channel; opening it by id plays rather than showing a page (HomeModel).
struct PlayChannelIntent: AppIntent {
    static let title: LocalizedStringResource = "Play Channel"
    static let description = IntentDescription("Plays a live TV channel from your server.")
    static let openAppWhenRun = true

    @Parameter(title: "Channel")
    var channel: ChannelEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        ArcfinRouting.openItem(id: channel.id)
        return .result()
    }
}

struct PlayRandomMovieIntent: AppIntent {
    static let title: LocalizedStringResource = "Play a Random Movie"
    static let description = IntentDescription("Plays a movie you haven't watched yet, picked at random.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let credential = IntentSession.credential() else {
            return .result(dialog: "Open Arcfin and sign in first.")
        }
        let page = try await JellyfinMediaClient().getLibraryItems(
            credential: credential, authHeader: IntentSession.authHeader(for: credential), libraryId: "",
            limit: 1, includeItemTypes: "Movie", isPlayed: false, sortBy: "Random")
        guard let movie = page.items.first else {
            return .result(dialog: "You've watched every movie in your library.")
        }
        WatchRoute.open(id: movie.id)
        return .result(dialog: "Playing \(movie.name).")
    }
}

struct DownloadNextEpisodeIntent: AppIntent {
    static let title: LocalizedStringResource = "Download Next Episode"
    static let description = IntentDescription("Downloads the next episode of a series to watch.")
    static let openAppWhenRun = true

    @Parameter(title: "Series")
    var target: MediaEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let credential = IntentSession.credential() else {
            return .result(dialog: "Open Arcfin and sign in first.")
        }
        let header = IntentSession.authHeader(for: credential)
        let client = JellyfinMediaClient()
        let detail = try await client.getItemDetail(credential: credential, authHeader: header, itemId: target.id).item
        let seriesId = detail.type == .episode ? detail.seriesId : detail.id
        guard let seriesId, let next = try await client.getNextEpisode(credential: credential, authHeader: header, seriesId: seriesId) else {
            return .result(dialog: "There's no next episode of \(target.title) to download.")
        }
        DownloadRoute.open(id: next.id)
        return .result(dialog: "Downloading \(next.name).")
    }
}

struct ShowDiscoverIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Discover"
    static let description = IntentDescription("Opens Discover, to find something new to request.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        ArcfinRouting.showDiscover()
        return .result()
    }
}

// MARK: - Shortcuts

struct ArcfinShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ContinueWatchingIntent(),
            phrases: [
                "Continue watching in \(.applicationName)",
                "Resume my show in \(.applicationName)",
                "What was I watching in \(.applicationName)",
            ],
            shortTitle: "Continue Watching",
            systemImageName: "play.circle")
        AppShortcut(
            intent: PlayTitleIntent(),
            phrases: [
                "Play \(\.$target) in \(.applicationName)",
                "Watch \(\.$target) in \(.applicationName)",
                "Put on \(\.$target) in \(.applicationName)",
            ],
            shortTitle: "Play Title",
            systemImageName: "play.fill")
        AppShortcut(
            intent: PlayChannelIntent(),
            phrases: [
                "Play \(\.$channel) channel in \(.applicationName)",
                "Watch \(\.$channel) live in \(.applicationName)",
                "Tune to \(\.$channel) in \(.applicationName)",
            ],
            shortTitle: "Play Channel",
            systemImageName: "antenna.radiowaves.left.and.right")
        AppShortcut(
            intent: PlayRandomMovieIntent(),
            phrases: [
                "Play a random movie in \(.applicationName)",
                "Surprise me in \(.applicationName)",
                "Pick a movie in \(.applicationName)",
            ],
            shortTitle: "Random Movie",
            systemImageName: "shuffle")
        AppShortcut(
            intent: DownloadNextEpisodeIntent(),
            phrases: [
                "Download the next episode of \(\.$target) in \(.applicationName)",
                "Download \(\.$target) in \(.applicationName)",
            ],
            shortTitle: "Download Next Episode",
            systemImageName: "arrow.down.to.line")
        AppShortcut(
            intent: OpenTitleIntent(),
            phrases: [
                "Open \(\.$target) in \(.applicationName)",
                "Show \(\.$target) in \(.applicationName)",
            ],
            shortTitle: "Open Title",
            systemImageName: "film")
        AppShortcut(
            intent: ShowDownloadsIntent(),
            phrases: [
                "Show my downloads in \(.applicationName)",
                "Open downloads in \(.applicationName)",
            ],
            shortTitle: "Downloads",
            systemImageName: "arrow.down.circle")
        AppShortcut(
            intent: ShowDiscoverIntent(),
            phrases: [
                "Open Discover in \(.applicationName)",
                "What's new to request in \(.applicationName)",
            ],
            shortTitle: "Discover",
            systemImageName: "sparkles")
    }
}

// MARK: - Handoff

enum ArcfinActivity {
    /// Also listed under NSUserActivityTypes in Info.plist, which Handoff requires.
    static let viewTitle = "com.psmattas.arcfin.viewTitle"
}

// MARK: - Routing

/// One place that turns "open this" requests into the app's existing deep-link plumbing.
enum ArcfinRouting {
    @MainActor
    static func openItem(id: String) {
        UserDefaults.standard.set(id, forKey: "arcfin.pendingPlayID")
        NotificationCenter.default.post(name: .arcfinPlayItem, object: nil, userInfo: ["itemID": id])
    }

    /// Opens a Seerr watchlist/request title found through Spotlight or Siri.
    @MainActor
    static func openSeerrTitle(id: String) {
        UserDefaults.standard.set(id, forKey: "arcfin.pendingSeerrTitle")
        Task {
            try? await Task.sleep(for: .seconds(0.6))
            NotificationCenter.default.post(name: .arcfinOpenSeerrTitle, object: nil, userInfo: ["id": id])
        }
    }

    /// Discover, then its Requests list, for a request waiting for approval or one that failed.
    @MainActor
    static func showSeerrRequests() {
        UserDefaults.standard.set(true, forKey: SeerrLinks.pendingRequestsKey)
        showDiscover()
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            NotificationCenter.default.post(name: .arcfinShowSeerrRequests, object: nil)
        }
    }

    /// Discover, then the Seerr issue a notification was about.
    @MainActor
    static func openSeerrIssue(id: Int) {
        UserDefaults.standard.set(id, forKey: SeerrLinks.pendingIssueKey)
        showDiscover()
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            NotificationCenter.default.post(name: .arcfinOpenSeerrIssue, object: nil)
        }
    }

    @MainActor
    static func showDiscover() {
        // Read by the tab bar when it first appears, for a cold launch.
        UserDefaults.standard.set(true, forKey: "arcfin.pendingDiscover")
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            NotificationCenter.default.post(name: .arcfinShowDiscover, object: nil)
        }
    }

    /// Shows in-app search results for `term`. The term is also buffered, because the Browse
    /// tab that owns the search field isn't mounted yet on a cold launch.
    @MainActor
    static func search(_ term: String) {
        UserDefaults.standard.set(term, forKey: "arcfin.pendingSearch")
        Task {
            try? await Task.sleep(for: .seconds(0.4))
            NotificationCenter.default.post(name: .arcfinSearch, object: nil, userInfo: ["term": term])
        }
    }

    /// Buffered like the arcfin://downloads link: the Browse tab that shows Downloads may not
    /// be mounted yet, and reads the flag when it appears.
    @MainActor
    static func showDownloads() {
        UserDefaults.standard.set(true, forKey: "arcfin.pendingShowDownloads")
        NotificationCenter.default.post(name: .arcfinShowDownloads, object: nil)
    }
}

// MARK: - Spotlight

/// Contributes the user's recent titles to Spotlight's semantic index as App Entities, so
/// Siri and Spotlight can find them by description and hand them to OpenTitleIntent.
enum SpotlightIndexer {
    private static let maxEntities = 60
    /// What was last handed to Spotlight; Home reloads often and usually nothing changed.
    private static var lastIndexed: [String] = []

    static func index(_ items: [MediaItem]) async {
        guard let credential = IntentSession.credential() else { return }
        var seen = Set<String>()
        let wanted = items
            .filter { $0.type == .movie || $0.type == .series || $0.type == .episode }
            .filter { seen.insert($0.id).inserted }
            .prefix(maxEntities)
        let ids = wanted.map(\.id)
        guard ids != lastIndexed else { return }
        lastIndexed = ids
        let thumbnails = await Thumbnails.fetch(for: Array(wanted), credential: credential)
        let entities = wanted.map { item -> MediaEntity in
            var entity = MediaEntity(item: item)
            entity.thumbnailData = thumbnails[item.id]
            return entity
        }
        guard !entities.isEmpty else { return }
        try? await CSSearchableIndex.default().indexAppEntities(Array(entities))
    }

    /// Called on sign-out / profile switch so another user's titles don't linger.
    static func clear() async {
        lastIndexed = []
        try? await CSSearchableIndex.default().deleteAllSearchableItems()
    }
}

// MARK: - Poster thumbnails

/// Small poster images for Spotlight and visual search results. Cached for the session so
/// re-indexing on every Home load doesn't download the same posters again.
enum Thumbnails {
    private actor Store {
        var cache: [String: Data] = [:]
        func data(for id: String) -> Data? { cache[id] }
        func set(_ data: Data, for id: String) { cache[id] = data }
    }

    private static let store = Store()

    static func fetch(for items: [MediaItem], credential: ServerCredential) async -> [String: Data] {
        await withTaskGroup(of: (String, Data?).self) { group in
            for item in items {
                group.addTask {
                    if let cached = await store.data(for: item.id) { return (item.id, cached) }
                    guard let tag = item.primaryImageTag else { return (item.id, nil) }
                    let url = JellyfinMediaClient.imageURL(
                        baseURL: credential.baseURL, itemID: item.id, tag: tag,
                        type: .primary, fillWidth: 240, token: credential.accessToken)
                    guard let data = await URLSession.arcfin.imageData(from: url)
                    else { return (item.id, nil) }
                    await store.set(data, for: item.id)
                    return (item.id, data)
                }
            }
            var result: [String: Data] = [:]
            for await (id, data) in group { if let data { result[id] = data } }
            return result
        }
    }
}

// MARK: - Visual intelligence

#if canImport(VisualIntelligence)
/// Point the camera at a movie poster, a DVD case or a screenshot and the titles it spells out
/// are looked up in the library. Visual intelligence only supplies generic labels ("poster",
/// "book"), never a title, so the text in the picture is read instead and searched.
@available(macOS 27.0, *)
struct ArcfinVisualSearchQuery: IntentValueQuery {
    func values(for input: SemanticContentDescriptor) async throws -> [MediaEntity] {
        guard let credential = IntentSession.credential(), let pixelBuffer = input.pixelBuffer else { return [] }
        let terms = Self.recognizedTitles(in: pixelBuffer)
        guard !terms.isEmpty else { return [] }

        let header = IntentSession.authHeader(for: credential)
        let client = JellyfinMediaClient()
        var found: [MediaItem] = []
        var seen = Set<String>()
        for term in terms {
            let hits = (try? await client.search(credential: credential, authHeader: header, query: term, limit: 5)) ?? []
            for hit in hits where hit.type == .movie || hit.type == .series {
                if seen.insert(hit.id).inserted { found.append(hit) }
            }
            if found.count >= 10 { break }
        }
        let thumbnails = await Thumbnails.fetch(for: found, credential: credential)
        return found.prefix(10).map { item in
            var entity = MediaEntity(item: item)
            entity.thumbnailData = thumbnails[item.id]
            return entity
        }
    }

    /// The most prominent text first: poster titles are the largest lettering in the shot.
    nonisolated private static func recognizedTitles(in pixelBuffer: CVReadOnlyPixelBuffer) -> [String] {
        pixelBuffer.withUnsafeBuffer { buffer -> [String] in
            let image = CIImage(cvPixelBuffer: buffer)
            guard let cgImage = CIContext().createCGImage(image, from: image.extent) else { return [] }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            guard (try? VNImageRequestHandler(cgImage: cgImage).perform([request])) != nil else { return [] }
            return (request.results ?? [])
                .sorted { $0.boundingBox.height > $1.boundingBox.height }
                .compactMap { $0.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.count >= 3 && $0.contains(where: \.isLetter) }
                .prefix(3)
                .map { $0 }
        }
    }
}
#endif
#endif
