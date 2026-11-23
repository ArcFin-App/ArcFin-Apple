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

    /// The foreground, a network change and the player closing can each ask at once: one runs
    /// at a time, and one asked for meanwhile runs again after it instead of alongside.
    @MainActor private static var isSyncing = false
    @MainActor private static var syncRequestedMeanwhile = false

    /// The saved profile a download is for: its own, or the same user on the same server
    /// signed in again since.
    public static func credential(for profile: DownloadProfile, in profiles: [ServerCredential]) -> ServerCredential? {
        profiles.first { $0.id.uuidString == profile.id && $0.userID == profile.userId }
            ?? profiles.first { profile.owns(DownloadProfile($0)) }
    }

    @MainActor
    public static func syncPending(
        modelContext: ModelContext,
        profiles: [ServerCredential],
        authHeader: (ServerCredential) -> String
    ) async {
        guard !isSyncing else {
            syncRequestedMeanwhile = true
            return
        }
        isSyncing = true
        defer { isSyncing = false }
        repeat {
            syncRequestedMeanwhile = false
            await syncOnce(modelContext: modelContext, profiles: profiles, authHeader: authHeader)
        } while syncRequestedMeanwhile
    }

    @MainActor
    private static func syncOnce(
        modelContext: ModelContext,
        profiles: [ServerCredential],
        authHeader: (ServerCredential) -> String
    ) async {
        let client = JellyfinMediaClient()
        await sendKeptProgress(profiles: profiles, authHeader: authHeader, client: client)
        let descriptor = FetchDescriptor<DownloadedItem>(predicate: #Predicate { $0.needsSync })
        guard let pending = try? modelContext.fetch(descriptor), !pending.isEmpty else { return }

        var syncedCount = 0
        // serverId is the ServerCredential's own id (see DownloadManager, where it's stored as
        // credential.id.uuidString) — matched against currently saved profiles rather than
        // requiring the item's original server to still be the active one.
        let byProfile = Dictionary(grouping: pending) { "\($0.serverId)|\($0.userId)" }
        for items in byProfile.values {
            guard let first = items.first,
                  let credential = credential(for: first.profile, in: profiles)
            else { continue }
            let header = authHeader(credential)
            // What's being sent: a save that lands while a request is out is newer than it, so
            // that row stays marked for the next sync instead of being cleared or overwritten.
            let changedAt = Dictionary(items.map { ($0.itemId, $0.progressChangedAt) }, uniquingKeysWith: { first, _ in first })
            // The server's state first: the title may have been watched elsewhere meanwhile,
            // and sending this device's older "part-way through" would mark it unwatched.
            guard let server = try? await client.getUserData(
                credential: credential, authHeader: header, itemIds: items.map(\.itemId))
            else { continue }
            for item in items {
                guard item.progressChangedAt == changedAt[item.itemId] ?? nil else { continue }
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
                guard item.progressChangedAt == changedAt[item.itemId] ?? nil else { continue }
                item.needsSync = false
                syncedCount += 1
            }
        }
        try? modelContext.save()
        if syncedCount > 0 {
            log.notice("Synced \(syncedCount) offline-played item(s) back to their server")
        }
    }

    /// Watched anywhere is never undone by a position from here; otherwise whichever was
    /// played last wins. A download from before change times were kept defers to a watch.
    @MainActor
    static func serverIsNewer(_ remote: UserData, than item: DownloadedItem) -> Bool {
        serverIsNewer(remote, played: item.played, changedAt: item.progressChangedAt)
    }

    static func serverIsNewer(_ remote: UserData, played: Bool, changedAt: Date?) -> Bool {
        if remote.played && !played { return true }
        guard !played, let serverTime = remote.lastPlayedDate, let localTime = changedAt else { return false }
        return serverTime > localTime
    }

    // MARK: Progress of deleted downloads

    /// What was watched here on a download deleted before it reached the server. The row that
    /// carried it is gone, so it waits here until a sync sends it.
    struct KeptProgress: Codable, Equatable {
        let itemId: String
        let serverId: String
        let userId: String
        let positionTicks: Int64
        let played: Bool
        let changedAt: Date?
    }

    static let keptProgressKey = "arcfin.offlineProgressOfDeletedDownloads"

    /// Call before deleting a download: progress it hasn't sent yet is kept for the next sync.
    @MainActor
    public static func keepUnsyncedProgress(of item: DownloadedItem, defaults: UserDefaults = .standard) {
        guard item.needsSync else { return }
        let entry = KeptProgress(itemId: item.itemId, serverId: item.serverId, userId: item.userId,
                                 positionTicks: item.playbackPositionTicks, played: item.played, changedAt: item.progressChangedAt)
        storeKeptProgress(keptProgress(defaults: defaults).filter { !($0.itemId == entry.itemId && $0.userId == entry.userId) } + [entry],
                          defaults: defaults)
    }

    static func keptProgress(defaults: UserDefaults = .standard) -> [KeptProgress] {
        guard let data = defaults.data(forKey: keptProgressKey),
              let decoded = try? JSONDecoder().decode([KeptProgress].self, from: data)
        else { return [] }
        return decoded
    }

    static func storeKeptProgress(_ entries: [KeptProgress], defaults: UserDefaults = .standard) {
        if entries.isEmpty {
            defaults.removeObject(forKey: keptProgressKey)
        } else if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: keptProgressKey)
        }
    }

    /// Sends the kept progress of deleted downloads, the same way as a row's, and forgets each
    /// once the server has it or has something newer.
    @MainActor
    private static func sendKeptProgress(profiles: [ServerCredential], authHeader: (ServerCredential) -> String,
                                         client: JellyfinMediaClient) async {
        let kept = keptProgress()
        guard !kept.isEmpty else { return }
        var settled: [KeptProgress] = []
        for entries in Dictionary(grouping: kept, by: { "\($0.serverId)|\($0.userId)" }).values {
            guard let first = entries.first,
                  let credential = profiles.first(where: { $0.id.uuidString == first.serverId && $0.userID == first.userId })
            else { continue }
            let header = authHeader(credential)
            guard let server = try? await client.getUserData(credential: credential, authHeader: header, itemIds: entries.map(\.itemId))
            else { continue }
            for entry in entries {
                if let remote = server[entry.itemId], serverIsNewer(remote, played: entry.played, changedAt: entry.changedAt) {
                    settled.append(entry)
                    continue
                }
                guard (try? await client.updateUserData(credential: credential, authHeader: header, itemId: entry.itemId,
                                                        positionTicks: entry.positionTicks, played: entry.played,
                                                        lastPlayed: entry.changedAt ?? Date())) != nil
                else { continue }
                settled.append(entry)
            }
        }
        guard !settled.isEmpty else { return }
        // Read again: a download deleted while this ran added to the list.
        storeKeptProgress(keptProgress().filter { !settled.contains($0) })
    }
}

extension DownloadProfile {
    public init(_ credential: ServerCredential) {
        self.init(id: credential.id.uuidString, userId: credential.userID, serverBaseURL: credential.baseURL.absoluteString)
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
public enum SettingsSyncValueType: String, Sendable, Codable {
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
        .init("skipCommercials", .bool),
        .init("subtitlesWhenMuted", .bool),
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
        .init("musicVisualizer", .bool),
        .init("musicVisualizerTint", .bool),
        .init("musicStreamQuality", .string),
        .init("musicMobileStreamQuality", .string),
        .init("musicDownloadQuality", .string),
        .init("musicDownloadOnMobileData", .bool),
        .init("musicSoundCheck", .bool),
        .init("musicEqualizer", .string),
        .init("musicCrossfadeSeconds", .int),
        .init("musicAutoplay", .bool),
        .init("musicRememberQueue", .bool),
        .init("musicKeepFavoritesDownloaded", .bool),
        .init("musicKeepRecentCount", .int),
        .init("musicDownloadNewAlbums", .bool),
        .init("musicStorageLimitGB", .int),
        .init("musicNotifyDownloads", .bool),
        .init("musicFindLyricsOnline", .bool),
        .init("musicIdentifySongs", .bool),
        .init("musicAppleMusic", .bool),
        // Downloads
        .init("wifiOnly", .bool),
        .init("downloadQuality", .string),
        // offlineModeEnabled is left out: it says what this device is doing right now.
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
        .init("downloadWhilePlaying", .bool),
        .init("removeDownloadsAfterDays", .int),
        .init("removeWatchedWhenLowOnSpace", .bool),
        // Appearance
        .init("reduceMotion", .bool),
        .init("hapticsEnabled", .bool),
        .init("mergeContinueWatchingAndUpNext", .bool),
        .init("showUnwatchedCount", .bool),
        .init("homeEpisodeArtwork", .string),
        .init("raiseQuietAudio", .bool),
        .init("notifyNewEpisodes", .bool),
        .init("notifyNewFilms", .bool),
        .init("notifyServerEvents", .bool),
        .init("showStreamsOnAppIcon", .bool),
        .init("animationUpscaling", .bool),
        .init("subtitleReachLater", .int),
        .init("subtitleReachEarlier", .int),
        .init("heroVideoBackdropsEnabled", .bool),
        .init("heroTrailerSound", .bool),
        .init("modernHome", .bool),
        .init("shuffleHomeShelves", .bool),
        .init("spoilerProtection", .bool),
        .init("libraryHideWatched", .bool),
        .init("saveSearchHistory", .bool),
        .init("modernSearch", .bool),
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
        .init("ignoreEdgeSwipes", .bool),
        .init("playerOpeningOrientation", .string),
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
        .init("seerrAuthMethod", .string)
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

    /// The values this device and the server last agreed on, so a sync can tell which side
    /// changed a setting since.
    /// Before 0.5.0, one record for the whole device; now each profile keeps its own.
    static let lastSyncedKey = "arcfin.settingsSync.lastSynced"
    static func lastSyncedKey(profile: String) -> String { "\(lastSyncedKey).\(profile)" }
    /// The profile that synced last on this device.
    private static let lastProfileKey = "arcfin.settingsSync.lastProfile"

    /// Which values to take from the server and which to send it. `base` is what both last
    /// agreed on, nil before the first sync that kept it.
    /// `adoptRemote`: this device's values belong to another profile (its first sync here after
    /// a switch), so the server's are taken and nothing is sent.
    static func merge(local: [String: String], remote: [String: String], base: [String: String]?,
                      locked: Set<String>, adoptRemote: Bool = false) -> (apply: [String: String], push: [String: String]) {
        var toApply: [String: String] = [:]
        var toPush: [String: String] = [:]
        for key in Set(remote.keys).union(local.keys) where SettingsSyncRegistry.allKeys.contains(key) {
            let remoteValue = remote[key], localValue = local[key]
            if adoptRemote {
                if let remoteValue, remoteValue != localValue { toApply[key] = remoteValue }
                continue
            }
            if locked.contains(key) {
                if let remoteValue, remoteValue != localValue { toApply[key] = remoteValue }
                continue
            }
            let changedHere = localValue != nil && localValue != base?[key]
            if let localValue, remoteValue == nil || (changedHere && localValue != remoteValue) {
                toPush[key] = localValue
            } else if let remoteValue, remoteValue != localValue {
                toApply[key] = remoteValue
            }
        }
        return (toApply, toPush)
    }

    static func lockedKey(profile: String) -> String { "arcfin.settingsSync.locked.\(profile)" }

    /// The keys the server last said were locked for this profile, kept so they stay locked at
    /// launch, offline and while a sync runs.
    public static func lockedKeys(profile: String, defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.stringArray(forKey: lockedKey(profile: profile)) ?? [])
    }

    /// For a server that says it no longer has the plugin.
    public static func forgetLockedKeys(profile: String, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: lockedKey(profile: profile))
    }

    /// What this profile and the server last agreed on, in the wire format.
    static func lastSynced(profile: String, defaults: UserDefaults) -> [String: String]? {
        defaults.dictionary(forKey: lastSyncedKey(profile: profile)) as? [String: String]
    }

    /// Whether this device has a setting the server hasn't heard yet.
    public static func hasLocalChanges(profile: String, defaults: UserDefaults = .standard) -> Bool {
        guard let base = defaults.dictionary(forKey: lastSyncedKey(profile: profile)) as? [String: String] else { return false }
        return collectLocalPayload(defaults: defaults).settings != base
    }

    /// A three-way merge against what was last agreed: a setting changed on this device since
    /// then is sent to the server, one changed only on the server is taken from it, and one an
    /// administrator locked always comes from the server. Before, the server's value always won,
    /// so anything changed here was put back at the next sync unless the server had never had it.
    /// Returns the set of admin-locked keys, so the caller can disable those controls in Settings,
    /// or nil when the server's settings couldn't be read: nothing was merged, and the locks last
    /// seen (`lockedKeys(profile:)`) still apply.
    /// `isCurrent` says whether the profile is still the one in use: a sync that finishes after
    /// a switch would read and write the next profile's settings, so it stops there.
    @discardableResult
    public static func sync(credential: ServerCredential, authHeader: String, defaults: UserDefaults = .standard,
                            isCurrent: @Sendable () async -> Bool = { true }) async -> Set<String>? {
        let pluginClient = ArcfinPluginSyncClient(credential: credential, authHeader: authHeader)
        let profile = credential.id.uuidString

        // One read gives both the values and the locks, so a merge never runs with the locks
        // missing and sends this device's value for a locked key.
        guard let settings = try? await ArcfinSyncClient().fetchSettings(credential: credential, authHeader: authHeader)
        else { return nil }
        var remote: [String: String] = [:]
        for setting in settings {
            if let value = setting.value { remote[setting.key] = value }
        }
        let locked = Set(settings.filter { $0.isLocked }.map { $0.key })
        defaults.set(locked.sorted(), forKey: lockedKey(profile: profile))
        guard await isCurrent() else { return nil }
        let local = collectLocalPayload(defaults: defaults).settings
        let (base, adoptRemote) = startingPoint(profile: profile, defaults: defaults)

        let (toApply, toPush) = merge(local: local, remote: remote, base: base, locked: locked, adoptRemote: adoptRemote)
        apply(SyncPayload(settings: toApply), defaults: defaults)
        var agreed = collectLocalPayload(defaults: defaults).settings
        if !toPush.isEmpty, (try? await pluginClient.push(SyncPayload(settings: toPush))) == nil {
            // Not sent: keep those as changed here, so the next sync sends them again.
            for key in toPush.keys { agreed[key] = base?[key] }
        }
        guard await isCurrent() else { return locked }
        defaults.set(agreed, forKey: lastSyncedKey(profile: profile))
        defaults.set(profile, forKey: lastProfileKey)
        return locked
    }

    /// What this profile last agreed on here, and whether the device's values are someone
    /// else's: another profile synced last and this one has no record here yet, so sending them
    /// would put that profile's settings (its Seerr server, say) into this one's.
    static func startingPoint(profile: String, defaults: UserDefaults) -> (base: [String: String]?, adoptRemote: Bool) {
        if let base = defaults.dictionary(forKey: lastSyncedKey(profile: profile)) as? [String: String] {
            return (base, false)
        }
        let previous = defaults.string(forKey: lastProfileKey)
        // The device-wide record from before 0.5.0 belongs to whoever is active at the update.
        if previous == nil, let legacy = defaults.dictionary(forKey: lastSyncedKey) as? [String: String] {
            defaults.removeObject(forKey: lastSyncedKey)
            return (legacy, false)
        }
        if let previous, previous != profile { return (nil, true) }
        // No record at all: a value set here counts as this device's choice.
        return (nil, false)
    }
}
