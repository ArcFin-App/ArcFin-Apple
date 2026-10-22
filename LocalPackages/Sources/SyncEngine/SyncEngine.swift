// SPDX-License-Identifier: AGPL-3.0-or-later

import AuthCore
import Foundation
import JellyfinAPI
import Persistence
import SwiftData
import Telemetry

// MARK: - Offline playback progress sync

/// Pushes playback progress/watched-status recorded while offline back to each item's
/// server, using the standard Sessions/Playing/Stopped and PlayedItems endpoints — the same
/// ones the online player already reports through, just called after the fact instead of
/// live. Best-effort per item: a failure (server unreachable, item deleted server-side, that
/// server's profile no longer saved) leaves needsSync set for a later retry rather than
/// failing the whole batch.
public enum OfflineProgressSync {
    private static let log = Telemetry.logger(category: "OfflineProgressSync")

    @MainActor
    public static func syncPending(
        modelContext: ModelContext,
        profiles: [ServerCredential],
        authHeader: (ServerCredential) -> String
    ) async {
        let descriptor = FetchDescriptor<DownloadedItem>(predicate: #Predicate { $0.needsSync })
        guard let pending = try? modelContext.fetch(descriptor), !pending.isEmpty else { return }

        let client = JellyfinMediaClient()
        var syncedCount = 0
        // serverId is the ServerCredential's own id (see DownloadManager, where it's stored as
        // credential.id.uuidString) — matched against currently saved profiles rather than
        // requiring the item's original server to still be the active one.
        let byProfile = Dictionary(grouping: pending) { "\($0.serverId)|\($0.userId)" }
        for items in byProfile.values {
            guard let first = items.first,
                  let credential = profiles.first(where: { $0.id.uuidString == first.serverId && $0.userID == first.userId })
            else { continue }
            let header = authHeader(credential)
            // The server's state first: the title may have been watched elsewhere meanwhile,
            // and sending this device's older "part-way through" would mark it unwatched.
            guard let server = try? await client.getUserData(
                credential: credential, authHeader: header, itemIds: items.map(\.itemId))
            else { continue }
            for item in items {
                if let remote = server[item.itemId], serverIsNewer(remote, than: item) {
                    item.played = remote.played
                    item.playbackPositionTicks = remote.played ? 0 : remote.playbackPositionTicks
                    item.needsSync = false
                    continue
                }
                do {
                    try await client.updateUserData(
                        credential: credential, authHeader: header, itemId: item.itemId,
                        positionTicks: item.playbackPositionTicks, played: item.played,
                        lastPlayed: item.progressChangedAt ?? Date()
                    )
                } catch {
                    // Left marked, so the next sync tries again.
                    continue
                }
                item.needsSync = false
                syncedCount += 1
            }
        }
        try? modelContext.save()
        if syncedCount > 0 {
            log.info("Synced \(syncedCount) offline-played item(s) back to their server")
        }
    }

    /// Watched anywhere is never undone by a position from here; otherwise whichever was
    /// played last wins. A download from before change times were kept defers to a watch.
    @MainActor
    static func serverIsNewer(_ remote: UserData, than item: DownloadedItem) -> Bool {
        if remote.played && !item.played { return true }
        guard !item.played, let serverTime = remote.lastPlayedDate, let localTime = item.progressChangedAt else { return false }
        return serverTime > localTime
    }
}

// MARK: - Sync client protocol

public protocol SyncClientProtocol: Sendable {
    func push(_ payload: SyncPayload) async throws
    func pull() async throws -> SyncPayload
    func resolveConflict(local: SyncPayload, remote: SyncPayload) -> SyncPayload
}

// MARK: - Sync payload

public struct SyncPayload: Sendable, Codable, Equatable {
    public var schemaVersion: Int
    public var lastModified: Date
    public var settings: [String: String]

    public init(schemaVersion: Int = 1, lastModified: Date = .now, settings: [String: String] = [:]) {
        self.schemaVersion = schemaVersion
        self.lastModified = lastModified
        self.settings = settings
    }
}

// MARK: - Sync source priority

public enum SyncSource: Sendable {
    case jellyfinPlugin   // companion server plugin
    case cloudKit         // iCloud fallback
}

// MARK: - Conflict resolution strategy

public enum ConflictResolution: Sendable {
    case lastWriteWins
    case serverWins
    case clientWins
}

// MARK: - Arcfin Sync plugin client

/// Wraps ArcfinSyncClient (JellyfinAPI) behind SyncClientProtocol. Conflict resolution is
/// last-write-wins at the payload level — this plugin doesn't track a per-key timestamp, so a
/// full sync is pull-then-push: apply whatever the server has, then push this device's current
/// values for any key the server doesn't have yet. Good enough for the common case (one device
/// active at a time); a genuine simultaneous edit on two devices between syncs isn't reconciled
/// field-by-field.
public struct ArcfinPluginSyncClient: SyncClientProtocol {
    private let credential: ServerCredential
    private let authHeader: String
    private let client = ArcfinSyncClient()

    public init(credential: ServerCredential, authHeader: String) {
        self.credential = credential
        self.authHeader = authHeader
    }

    public func push(_ payload: SyncPayload) async throws {
        _ = try await client.updateSettings(credential: credential, authHeader: authHeader, values: payload.settings)
    }

    public func pull() async throws -> SyncPayload {
        let settings = try await client.fetchSettings(credential: credential, authHeader: authHeader)
        var values: [String: String] = [:]
        for setting in settings {
            if let value = setting.value {
                values[setting.key] = value
            }
        }
        return SyncPayload(settings: values)
    }

    public func resolveConflict(local: SyncPayload, remote: SyncPayload) -> SyncPayload {
        remote.lastModified >= local.lastModified ? remote : local
    }
}

// MARK: - Settings sync registry

/// The UserDefaults / @AppStorage keys eligible for cross-device sync via the Arcfin Sync
/// plugin, and how to read/write each one. Deliberately excludes two keys that exist in the app
/// but shouldn't sync: `seerrPassword` (a secret, never belongs in a generic settings payload)
/// and `appLockUseFaceID` (biometric availability is per-device, not something to carry across).
public enum SettingsSyncValueType: Sendable {
    case bool
    case int
    case string
}

public struct SettingsSyncEntry: Sendable {
    public let key: String
    public let type: SettingsSyncValueType

    public init(_ key: String, _ type: SettingsSyncValueType) {
        self.key = key
        self.type = type
    }
}

public enum SettingsSyncRegistry {
    public static let entries: [SettingsSyncEntry] = [
        // Playback
        .init("videoQuality", .string),
        .init("playbackEngine", .string),
        .init("autoPlayNext", .bool),
        .init("skipIntro", .bool),
        .init("skipCredits", .bool),
        .init("skipRecap", .bool),
        .init("subtitleDefault", .bool),
        .init("trailersEnabled", .bool),
        .init("youtubeTrailersEnabled", .bool),
        .init("preferredAudioLanguage", .string),
        .init("preferredSubtitleLanguage", .string),
        .init("skipForwardSeconds", .int),
        .init("skipBackwardSeconds", .int),
        .init("rememberPlaybackSpeed", .bool),
        .init("rememberTracksPerShow", .bool),
        .init("mobileVideoQuality", .string),
        .init("upNextCountdownSeconds", .int),
        .init("resumeBehavior", .string),
        .init("markWatchedAt", .string),
        // Downloads
        .init("wifiOnly", .bool),
        .init("downloadQuality", .string),
        .init("offlineModeEnabled", .bool),
        .init("deleteDownloadsAfterWatching", .bool),
        .init("smartDownloadsEnabled", .bool),
        .init("smartDownloadsEpisodeCount", .int),
        .init("smartDownloadsStorageBudgetGB", .int),
        .init("smartDownloadsAllowMobileData", .bool),
        .init("concurrentDownloads", .int),
        .init("downloadSubtitles", .string),
        .init("downloadTrickplay", .bool),
        .init("seasonDownloadUnwatchedOnly", .bool),
        .init("pauseDownloadsInLowPowerMode", .bool),
        .init("pauseDownloadsInLowDataMode", .bool),
        .init("removeDownloadsAfterDays", .int),
        .init("removeWatchedWhenLowOnSpace", .bool),
        // Appearance
        .init("reduceMotion", .bool),
        .init("hapticsEnabled", .bool),
        .init("mergeContinueWatchingAndUpNext", .bool),
        .init("heroVideoBackdropsEnabled", .bool),
        .init("shuffleHomeShelves", .bool),
        .init("spoilerProtection", .bool),
        .init("libraryHideWatched", .bool),
        .init("saveSearchHistory", .bool),
        // Notifications
        .init("notifyNewContent", .bool),
        .init("notifyRequestUpdates", .bool),
        .init("notifyWatchlistAvailable", .bool),
        .init("notifyDownload", .bool),
        .init("quietHoursEnabled", .bool),
        .init("quietHoursStart", .int),
        .init("quietHoursEnd", .int),
        // Player features
        .init("chapterListEnabled", .bool),
        .init("syncPlayEnabled", .bool),
        .init("castEnabled", .bool),
        .init("stillWatchingPromptEnabled", .bool),
        .init("matchContentFrameRate", .bool),
        .init("autoPictureInPicture", .bool),
        .init("swipeGesturesEnabled", .bool),
        .init("doubleTapToSkip", .bool),
        // Subtitle style
        .init("subtitleTextSize", .string),
        .init("subtitleTextColor", .string),
        .init("subtitleBackgroundStyle", .string),
        // Codec profile keys (codecAllowHEVCDirectPlay, codecAllowSurroundAudioDirectPlay) are
        // deliberately excluded — CodecProfileSettingsView's own doc comment explains why:
        // they describe this device's decode/output hardware, not a preference. Syncing them
        // would carry a receiver-connected Apple TV's surround setting onto a phone with no
        // receiver and produce silent audio, exactly what that screen's footer text warns about.
        // Integrations
        .init("seerrDiscoverEnabled", .bool),
        .init("seerrURL", .string),
        .init("seerrUsername", .string),
        .init("seerrAuthMethod", .string),
        .init("streamystatsURL", .string)
    ]

    public static let allKeys: Set<String> = Set(entries.map { $0.key })
}

// MARK: - Settings sync engine

public enum SettingsSyncEngine {
    /// Reads every registered key out of UserDefaults into a wire-format [String: String]
    /// payload. Bool/Int are stringified; the app's RawRepresentable-String @AppStorage enums
    /// (VideoQuality, PlaybackEngineKind, etc.) already store their rawValue as a plain string,
    /// so `.string` covers those too.
    public static func collectLocalPayload(defaults: UserDefaults = .standard) -> SyncPayload {
        var values: [String: String] = [:]
        for entry in SettingsSyncRegistry.entries {
            switch entry.type {
            case .bool:
                if defaults.object(forKey: entry.key) != nil {
                    values[entry.key] = defaults.bool(forKey: entry.key) ? "true" : "false"
                }
            case .int:
                if defaults.object(forKey: entry.key) != nil {
                    values[entry.key] = String(defaults.integer(forKey: entry.key))
                }
            case .string:
                if let value = defaults.string(forKey: entry.key) {
                    values[entry.key] = value
                }
            }
        }
        return SyncPayload(settings: values)
    }

    /// Writes a payload's values back into UserDefaults, respecting each key's declared type.
    public static func apply(_ payload: SyncPayload, defaults: UserDefaults = .standard) {
        let byKey = Dictionary(uniqueKeysWithValues: SettingsSyncRegistry.entries.map { ($0.key, $0.type) })
        for (key, value) in payload.settings {
            guard let type = byKey[key] else { continue }
            switch type {
            case .bool:
                defaults.set(value == "true", forKey: key)
            case .int:
                if let intValue = Int(value) {
                    defaults.set(intValue, forKey: key)
                }
            case .string:
                defaults.set(value, forKey: key)
            }
        }
    }

    /// Pull-then-push: applies the server's current values locally, then pushes back this
    /// device's values for any registered key the server doesn't have yet (first sync from a
    /// fresh install/profile populates the server). Returns the set of admin-locked keys, so the
    /// caller can disable those controls in Settings — an empty set (including on any failure)
    /// means nothing is locked, which is also the correct fallback when the plugin isn't
    /// reachable: settings stay fully local-editable rather than erroring.
    @discardableResult
    public static func sync(credential: ServerCredential, authHeader: String, defaults: UserDefaults = .standard) async -> Set<String> {
        let pluginClient = ArcfinPluginSyncClient(credential: credential, authHeader: authHeader)

        guard let remote = try? await pluginClient.pull() else { return [] }
        apply(remote, defaults: defaults)

        let local = collectLocalPayload(defaults: defaults)
        let missingOnServer = local.settings.filter { remote.settings[$0.key] == nil }
        if !missingOnServer.isEmpty {
            try? await pluginClient.push(SyncPayload(settings: missingOnServer))
        }

        guard let fullSettings = try? await ArcfinSyncClient().fetchSettings(credential: credential, authHeader: authHeader) else {
            return []
        }
        return Set(fullSettings.filter { $0.isLocked }.map { $0.key })
    }
}
