// SPDX-License-Identifier: AGPL-3.0-or-later

#if os(iOS)
import AppIntents
import AuthCore
import CoreSpotlight
import Foundation
import JellyfinAPI

// MARK: - Session for intents

/// Intents run outside the view hierarchy (Siri, Shortcuts, Spotlight), so they can't reach
/// AuthManager. They read the active profile straight from the Keychain instead — and refuse
/// when that profile has an app-lock PIN, so Siri and Spotlight can't be used to browse a
/// library the lock screen is meant to protect.
nonisolated enum IntentSession {
    static func credential() -> ServerCredential? {
        let store = KeychainStore()
        guard let all = try? store.allServers(), !all.isEmpty else { return nil }
        let storedID = UserDefaults.standard.string(forKey: "arcfin.activeProfileID").flatMap { UUID(uuidString: $0) }
        guard let credential = all.first(where: { $0.id == storedID }) ?? all.first else { return nil }
        let pin = (try? store.loadPin(for: credential.id)) ?? nil
        return pin == nil ? credential : nil
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

    var subtitle: String? {
        [kind, year.map(String.init)].compactMap { $0 }.joined(separator: " · ")
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: subtitle.map { LocalizedStringResource(stringLiteral: $0) })
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

    @MainActor
    static func showDownloads() {
        // Views listening for this aren't mounted yet on a cold launch.
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            NotificationCenter.default.post(name: .arcfinShowDownloads, object: nil)
        }
    }
}

// MARK: - Spotlight

/// Contributes the user's recent titles to Spotlight's semantic index as App Entities, so
/// Siri and Spotlight can find them by description and hand them to OpenTitleIntent.
enum SpotlightIndexer {
    private static let maxEntities = 60

    static func index(_ items: [MediaItem]) async {
        guard IntentSession.credential() != nil else { return }
        let entities = items
            .filter { $0.type == .movie || $0.type == .series || $0.type == .episode }
            .prefix(maxEntities)
            .map(MediaEntity.init(item:))
        guard !entities.isEmpty else { return }
        try? await CSSearchableIndex.default().indexAppEntities(Array(entities))
    }

    /// Called on sign-out / profile switch so another user's titles don't linger.
    static func clear() async {
        try? await CSSearchableIndex.default().deleteAllSearchableItems()
    }
}
#endif
