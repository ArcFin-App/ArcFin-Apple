// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import AuthCore

// MARK: - Hidden from Continue Watching and Next Up

public struct HiddenEntry: Sendable, Decodable, Equatable {
    public let itemId: String
    public let hidden: Date
}

public struct HiddenLists: Sendable, Decodable, Equatable {
    public var continueWatching: [HiddenEntry]
    public var nextUp: [HiddenEntry]

    public init(continueWatching: [HiddenEntry] = [], nextUp: [HiddenEntry] = []) {
        self.continueWatching = continueWatching
        self.nextUp = nextUp
    }

    /// IDs as Jellyfin's own API spells them (no dashes, lowercase), to match against items.
    public var continueWatchingIDs: Set<String> { Set(continueWatching.map { ArcfinCompanionClient.normalized($0.itemId) }) }
    public var nextUpIDs: Set<String> { Set(nextUp.map { ArcfinCompanionClient.normalized($0.itemId) }) }
}

public enum HiddenRow: String, Sendable {
    case continueWatching, nextUp
}

// MARK: - Signed commands

public struct ServerSigningKey: Sendable, Decodable, Equatable {
    /// SubjectPublicKeyInfo DER, base64.
    public let publicKey: String
    public let fingerprint: String
    public let previousPublicKey: String?
    /// The previous key's signature over this key's DER, so a pinned key can move to it.
    public let rotationSignature: String?
    /// Every key after the one this device holds, oldest first and ending with this one, each
    /// signed by the one before: how a device that missed rotations catches up.
    public var chain: [ServerSigningKey]?
    /// Set when the admin replaced the key completely: nothing links it to the one before.
    public var resetAt: Date?
    /// The admin lets devices on plain HTTP trust the key without a fingerprint check.
    public var trustOverHttp: Bool?

    public init(publicKey: String, fingerprint: String, previousPublicKey: String?, rotationSignature: String?, chain: [ServerSigningKey]? = nil,
                resetAt: Date? = nil) {
        self.resetAt = resetAt
        self.publicKey = publicKey
        self.fingerprint = fingerprint
        self.previousPublicKey = previousPublicKey
        self.rotationSignature = rotationSignature
        self.chain = chain
    }
}

public struct SignedServerCommand: Sendable, Decodable, Equatable {
    /// Base64 of the signed JSON bytes; only these are trusted, never the plain fields beside them.
    public let payload: String
    /// ECDSA P-256 SHA-256, raw r‖s, base64.
    public let signature: String
}

// MARK: - Trusted devices

public struct TrustState: Sendable, Decodable, Equatable {
    public let trusted: Bool
    /// While waiting: the code to check on the trusted device.
    public let code: String?
}

public struct TrustRequest: Sendable, Decodable, Equatable, Identifiable {
    public let id: String
    public let deviceName: String
    public let code: String
    public let created: Date
}

// MARK: - Household

public struct DownloadAllowance: Sendable, Decodable, Equatable {
    public let limited: Bool
    public let maxTitles: Int?
    public let maxBytes: Int64?
    public let usedTitles: Int
    public let usedBytes: Int64
    public let musicLimited: Bool
    public let musicMaxAlbums: Int?
    public let musicMaxSongs: Int?
    public let musicMaxBytes: Int64?
    public let musicUsedAlbums: Int
    public let musicUsedSongs: Int
    public let musicUsedBytes: Int64
}

/// A downloaded song: its ID, its album (so albums can be counted) and size.
public struct DownloadedSong: Sendable, Encodable, Equatable {
    public let itemId: String
    public let albumId: String?
    public let bytes: Int64

    public init(itemId: String, albumId: String?, bytes: Int64) {
        self.itemId = itemId
        self.albumId = albumId
        self.bytes = bytes
    }
}

public struct DownloadCheck: Sendable, Decodable, Equatable {
    public let allowed: Bool
    public let message: String?
}

public struct SharedAccountInfo: Sendable, Decodable, Equatable {
    public struct Person: Sendable, Decodable, Equatable, Identifiable, Hashable {
        public let id: String
        public let name: String
    }

    public let isShared: Bool
    public let members: [Person]
    /// Who was last picked as watching on this device.
    public let watching: [String]
}

public struct Announcement: Sendable, Codable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var message: String
    /// info or warning.
    public var style: String
    public var starts: Date?
    public var ends: Date?
    /// Empty for everyone.
    public var users: [String]

    public init(id: String = UUID().uuidString, title: String = "", message: String = "", style: String = "info",
                starts: Date? = nil, ends: Date? = nil, users: [String] = []) {
        self.id = id
        self.title = title
        self.message = message
        self.style = style
        self.starts = starts
        self.ends = ends
        self.users = users
    }
}

public struct MaintenanceWindow: Sendable, Codable, Equatable, Identifiable {
    public var id: String
    public var starts: Date
    public var ends: Date
    public var message: String

    public init(id: String = UUID().uuidString, starts: Date, ends: Date, message: String = "") {
        self.id = id
        self.starts = starts
        self.ends = ends
        self.message = message
    }
}

public struct ServerNotices: Sendable, Decodable, Equatable {
    public let announcements: [Announcement]
    public let maintenance: [MaintenanceWindow]
}

/// The plugin's news since `cursor`: Seerr request changes it saw, plus the announcements and
/// maintenance showing now.
public struct ServerEventFeed: Sendable, Decodable, Equatable {
    public let cursor: Int64
    public let events: [ServerEvent]

    public init(cursor: Int64, events: [ServerEvent]) {
        self.cursor = cursor
        self.events = events
    }
}

public struct ServerEvent: Sendable, Decodable, Equatable, Identifiable {
    /// The same on every device for the same news, e.g. "seerr-approved.42".
    public let id: String
    /// seerr-approved, seerr-declined, seerr-available, announcement, maintenance or test.
    public let kind: String
    public let title: String
    public let body: String?
    public let requestId: Int?
    public let starts: Date?
    public let ends: Date?

    public init(id: String, kind: String, title: String = "", body: String? = nil, requestId: Int? = nil, starts: Date? = nil, ends: Date? = nil) {
        self.id = id
        self.kind = kind
        self.title = title
        self.body = body
        self.requestId = requestId
        self.starts = starts
        self.ends = ends
    }
}

public struct DownloadLimitSettings: Sendable, Codable, Equatable {
    public struct UserOverride: Sendable, Codable, Equatable, Identifiable {
        public var userId: String
        /// inherit, off or custom.
        public var mode: String
        public var maxTitles: Int?
        public var maxGigabytes: Double?
        /// inherit, off or custom, for music.
        public var musicMode: String
        public var musicMaxAlbums: Int?
        public var musicMaxSongs: Int?
        public var musicMaxGigabytes: Double?

        public var id: String { userId }

        public init(userId: String, mode: String = "inherit", maxTitles: Int? = nil, maxGigabytes: Double? = nil,
                    musicMode: String = "inherit", musicMaxAlbums: Int? = nil, musicMaxSongs: Int? = nil, musicMaxGigabytes: Double? = nil) {
            self.userId = userId
            self.mode = mode
            self.maxTitles = maxTitles
            self.maxGigabytes = maxGigabytes
            self.musicMode = musicMode
            self.musicMaxAlbums = musicMaxAlbums
            self.musicMaxSongs = musicMaxSongs
            self.musicMaxGigabytes = musicMaxGigabytes
        }
    }

    public var enabled: Bool
    public var maxTitles: Int?
    public var maxGigabytes: Double?
    public var users: [UserOverride]
    /// Caps on downloaded music, apart from movies and episodes.
    public var musicEnabled: Bool
    public var musicMaxAlbums: Int?
    public var musicMaxSongs: Int?
    public var musicMaxGigabytes: Double?

    public init(enabled: Bool = false, maxTitles: Int? = nil, maxGigabytes: Double? = nil, users: [UserOverride] = [],
                musicEnabled: Bool = false, musicMaxAlbums: Int? = nil, musicMaxSongs: Int? = nil, musicMaxGigabytes: Double? = nil) {
        self.enabled = enabled
        self.maxTitles = maxTitles
        self.maxGigabytes = maxGigabytes
        self.users = users
        self.musicEnabled = musicEnabled
        self.musicMaxAlbums = musicMaxAlbums
        self.musicMaxSongs = musicMaxSongs
        self.musicMaxGigabytes = musicMaxGigabytes
    }
}

public struct SharedAccountSetting: Sendable, Codable, Equatable, Identifiable {
    public var userId: String
    public var members: [String]

    public var id: String { userId }

    public init(userId: String, members: [String] = []) {
        self.userId = userId
        self.members = members
    }
}

public struct HouseholdAdmin: Sendable, Decodable, Equatable {
    public struct Use: Sendable, Decodable, Equatable {
        public let titles: Int
        public let bytes: Int64
        public let albums: Int
        public let songs: Int
        public let musicBytes: Int64
    }

    public let downloads: DownloadLimitSettings
    public let downloadUse: [String: Use]
    public let sharedAccounts: [SharedAccountSetting]
    public let announcements: [Announcement]
    public let maintenance: [MaintenanceWindow]

    public func use(_ userID: String) -> Use? {
        downloadUse.first { ArcfinCompanionClient.normalized($0.key) == ArcfinCompanionClient.normalized(userID) }?.value
    }
}

// MARK: - Watch time

public struct WatchTimeStatus: Sendable, Decodable, Equatable {
    public let hasLimits: Bool
    public let allowed: Bool
    /// "bedtime" or "dailyLimit" when not allowed.
    public let reason: String?
    public let minutesLeft: Int?
    public let until: Date?
    public let usedMinutes: Int
    public let dailyMinutes: Int?
    public let bedtimeStart: String?
    public let bedtimeEnd: String?

    public var isBedtime: Bool { reason == "bedtime" }
}

// MARK: - Recommendations

public struct RecommendationRow: Sendable, Decodable, Equatable, Identifiable {
    public let id: String
    /// forYou, becauseYouWatched or popularOnServer.
    public let kind: String
    public let seedId: String?
    public let seedName: String?
    public let itemIds: [String]
}

public struct Recommendations: Sendable, Decodable, Equatable {
    public let rows: [RecommendationRow]
}

// MARK: - Integrations

public struct ServerIntegrations: Sendable, Decodable, Equatable {
    public let seerr: Bool
    public let tmdb: Bool

    public init(seerr: Bool = false, tmdb: Bool = false) {
        self.seerr = seerr
        self.tmdb = tmdb
    }
}

// MARK: - Watch parties

public struct PartyPerson: Sendable, Decodable, Equatable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let deviceName: String
    public let isHost: Bool
    public let isMe: Bool
    public let ready: Bool
    public let isAway: Bool
    /// The person's device's time zone (IANA id), so the host sees what a planned start is there.
    public let timeZone: String?
}

public struct WatchPartyState: Sendable, Decodable, Equatable {
    public let code: String
    /// lobby, starting or started.
    public let phase: String
    public let isHost: Bool
    public let locked: Bool
    public let itemId: String
    public let itemName: String
    public let itemType: String
    /// The SyncPlay group to join, once the host has made it.
    public let groupId: String?
    /// Its name, for people joining from another app with SyncPlay.
    public let groupName: String?
    public let startTicks: Int64
    public let people: [PartyPerson]
    /// The planned start, for a scheduled party.
    public let scheduledFor: Date?
    /// When a scheduled party's lobby opens, 15 minutes before the start.
    public let lobbyOpens: Date?

    /// Scheduled, and the lobby isn't open yet: people can join and wait.
    public var isWaiting: Bool { phase == "scheduled" }
    public var isLobby: Bool { phase == "lobby" }
    public var isStarting: Bool { phase == "starting" }
    public var isStarted: Bool { phase == "started" }
    public var me: PartyPerson? { people.first(where: \.isMe) }
}

// MARK: - Admin

public struct IntegrationsAdmin: Sendable, Decodable, Equatable {
    public struct Queued: Sendable, Decodable, Equatable, Identifiable {
        public let id: String
        public let userId: String
        public let created: Date
        public let attempts: Int
        public let lastError: String?
    }

    public let seerrUrl: String?
    public let seerrPublicUrl: String?
    public let seerrKeySet: Bool
    public let tmdbKeySet: Bool
    public let addSeerrUsers: Bool
    /// ok, keyRejected, unreachable or error.
    public let seerrState: String?
    public let seerrMessage: String?
    public let seerrChecked: Date?
    /// environment, file or generated.
    public let vaultKeySource: String
    public let queue: [Queued]
}

/// Keys are write-only: nil keeps the saved one, an empty string removes it.
public struct IntegrationsAdminChange: Sendable, Encodable {
    public var seerrUrl: String?
    public var seerrPublicUrl: String?
    public var seerrApiKey: String?
    public var tmdbKey: String?
    public var addSeerrUsers: Bool

    public init(seerrUrl: String?, seerrPublicUrl: String?, seerrApiKey: String? = nil, tmdbKey: String? = nil, addSeerrUsers: Bool) {
        self.seerrUrl = seerrUrl
        self.seerrPublicUrl = seerrPublicUrl
        self.seerrApiKey = seerrApiKey
        self.tmdbKey = tmdbKey
        self.addSeerrUsers = addSeerrUsers
    }
}

public struct SecurityAdmin: Sendable, Decodable, Equatable {
    public struct Command: Sendable, Decodable, Equatable {
        public let userId: String
        public let kind: String
        public let counter: Int64
        public let expires: Date
    }

    public struct Key: Sendable, Decodable, Equatable {
        public let fingerprint: String
        public let created: Date
        /// The admin's own key: it can't be rotated automatically.
        public let imported: Bool?
    }

    /// An Arcfin device that has told the server which key it holds.
    public struct Device: Sendable, Decodable, Equatable, Identifiable {
        public let userId: String
        public let deviceId: String
        public let deviceName: String
        public let lastCheckIn: Date
        public let upToDate: Bool
        public let appVersion: String?
        public let build: String?
        public let signedOut: Date?
        public let action: String?
        /// Arcfin is locked on this one device until an admin unlocks it.
        public let locked: Bool
        /// trust (waiting for approval), pinTries, wipe, or nil for falling behind.
        public let lockReason: String?
        /// off, signOut or lock, with the user's override applied.
        public let rule: String
        /// When it'll be signed out if it's still behind.
        public let signOutAfter: Date?
        /// When it reported getting a key that isn't this server's, and that key's fingerprint.
        public let mismatchAt: Date?
        public let mismatchFingerprint: String?

        public var id: String { userId + "/" + deviceId }
    }

    public let key: Key?
    public let vaultKeySource: String
    public let settings: SecuritySettings
    public let nextRotation: Date?
    public let lockedUsers: [String]
    /// Accounts disabled in Jellyfin by an Arcfin Sync lock.
    public let disabledUsers: [String]
    public let commands: [Command]
    public let devices: [Device]
    /// Arcfin devices signed in that have never checked in: too old for key changes and locks.
    public let olderDevices: [OlderDevice]
    /// New devices waiting for a trusted device or an admin to approve them.
    public let trustRequests: [TrustRequest]
    public let trustedDevices: [DeviceRef]
    /// Wipes sent that the device hasn't carried out yet.
    public let pendingWipes: [DeviceRef]

    public struct TrustRequest: Sendable, Decodable, Equatable, Identifiable {
        public let id: String
        public let userId: String
        public let deviceId: String
        public let deviceName: String
        public let code: String
        public let created: Date
    }

    public struct DeviceRef: Sendable, Decodable, Equatable, Hashable {
        public let userId: String
        public let deviceId: String
    }

    public struct OlderDevice: Sendable, Decodable, Equatable, Identifiable {
        public let userId: String
        public let deviceId: String
        public let deviceName: String
        public let appVersion: String
        public let lastActivity: Date?

        public var id: String { userId + "/" + deviceId }
    }

    public func isDisabled(_ userID: String) -> Bool {
        disabledUsers.contains { ArcfinCompanionClient.normalized($0) == ArcfinCompanionClient.normalized(userID) }
    }

    public func isLocked(_ userID: String) -> Bool {
        lockedUsers.contains { ArcfinCompanionClient.normalized($0) == ArcfinCompanionClient.normalized(userID) }
    }
}

public enum ServerCommandKind: String, Sendable, Codable {
    case resetPin, lock, unlock, wipe, policy
}

/// The admin's PIN rules: who needs one, how long, and how many tries before the profile locks.
public struct PinRules: Sendable, Codable, Equatable {
    /// none, everyone or chosen.
    public var requiredFor: String
    public var users: [String]
    /// 4 to 8 digits.
    public var minLength: Int
    /// Tries before the profile locks on that device until an admin unlocks it; nil for the usual waits.
    public var maxTries: Int?

    public static let longest = 8

    public init(requiredFor: String = "none", users: [String] = [], minLength: Int = 4, maxTries: Int? = nil) {
        self.requiredFor = requiredFor
        self.users = users
        self.minLength = minLength
        self.maxTries = maxTries
    }
}

/// Automatic key rotation and the rule for devices that fall behind.
public struct SecuritySettings: Sendable, Codable, Equatable {
    public struct UserOverride: Sendable, Codable, Equatable, Identifiable {
        public var userId: String
        /// inherit, off, signOut or lock.
        public var staleAction: String
        /// This user's own days, or nil for everyone's.
        public var staleAfterDays: Int?
        /// inherit, on or off: whether this person's new devices need approving.
        public var trustedDevices: String

        public var id: String { userId }

        public init(userId: String, staleAction: String = "inherit", staleAfterDays: Int? = nil, trustedDevices: String = "inherit") {
            self.userId = userId
            self.staleAction = staleAction
            self.staleAfterDays = staleAfterDays
            self.trustedDevices = trustedDevices
        }
    }

    /// Signed commands and everything built on them; off until the admin turns it on.
    public var enabled: Bool
    /// A new Arcfin device waits until a trusted one of the person's, or an admin, approves it.
    public var requireTrustedDevices: Bool
    /// Arcfin won't use plain HTTP unless the address is on the local network.
    public var requireHttpsAway: Bool
    public var pins: PinRules
    /// Devices on plain HTTP trust the key without anyone checking the fingerprint.
    public var trustOverHttp: Bool
    public var autoRotate: Bool
    public var rotateEveryDays: Int
    /// off, signOut or lock.
    public var staleAction: String
    public var staleAfterDays: Int
    public var users: [UserOverride]
    /// allow, or signOut: Arcfin versions too old to check in are signed out a day after they're first seen.
    public var olderApps: String

    public init(autoRotate: Bool = false, rotateEveryDays: Int = 1, staleAction: String = "off", staleAfterDays: Int = 14, users: [UserOverride] = [],
                olderApps: String = "allow", trustOverHttp: Bool = false, enabled: Bool = false, requireTrustedDevices: Bool = false,
                requireHttpsAway: Bool = false, pins: PinRules = PinRules()) {
        self.enabled = enabled
        self.requireTrustedDevices = requireTrustedDevices
        self.requireHttpsAway = requireHttpsAway
        self.pins = pins
        self.olderApps = olderApps
        self.trustOverHttp = trustOverHttp
        self.autoRotate = autoRotate
        self.rotateEveryDays = rotateEveryDays
        self.staleAction = staleAction
        self.staleAfterDays = staleAfterDays
        self.users = users
    }
}

public struct WatchLimitRule: Sendable, Codable, Equatable, Identifiable {
    public var userId: String
    public var dailyMinutes: Int
    public var weekendMinutes: Int?
    /// "HH:mm", or nil for no bedtime.
    public var bedtimeStart: String?
    public var bedtimeEnd: String?
    /// This person's own time zone, or nil for the one set for everyone.
    public var timeZone: String?

    public var id: String { userId }

    public init(userId: String, dailyMinutes: Int = 120, weekendMinutes: Int? = nil, bedtimeStart: String? = nil, bedtimeEnd: String? = nil,
                timeZone: String? = nil) {
        self.userId = userId
        self.dailyMinutes = dailyMinutes
        self.weekendMinutes = weekendMinutes
        self.bedtimeStart = bedtimeStart
        self.bedtimeEnd = bedtimeEnd
        self.timeZone = timeZone
    }
}

public struct LimitsAdmin: Sendable, Decodable, Equatable {
    public let timeZone: String?
    public let serverTime: String
    public let serverTimeZone: String
    public var rules: [WatchLimitRule]
    public let usedToday: [String: Int]
    /// Arcfin warns 10 and 5 minutes before time's up or bedtime.
    public let warnBeforeEnd: Bool

    public func used(_ userID: String) -> Int? {
        usedToday.first { ArcfinCompanionClient.normalized($0.key) == ArcfinCompanionClient.normalized(userID) }?.value
    }
}

public struct LimitsAdminChange: Sendable, Encodable {
    public var timeZone: String?
    public var rules: [WatchLimitRule]
    public var warnBeforeEnd: Bool

    public init(timeZone: String?, rules: [WatchLimitRule], warnBeforeEnd: Bool = true) {
        self.timeZone = timeZone
        self.rules = rules
        self.warnBeforeEnd = warnBeforeEnd
    }
}

// MARK: - Live sessions and history (admin)

public struct LivePerson: Sendable, Decodable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let deviceName: String
    public let isHost: Bool
    public let ready: Bool
    public let swiped: Int
    public let isAway: Bool
}

public struct LiveParty: Sendable, Decodable, Equatable, Identifiable {
    public let code: String
    /// scheduled, lobby, starting or started.
    public let phase: String
    public let itemId: String
    public let itemName: String
    public let created: Date
    public let scheduledFor: Date?
    public let locked: Bool
    public let people: [LivePerson]

    public var id: String { code }
    /// The time can still move: not started yet.
    public var canReschedule: Bool { phase == "scheduled" || phase == "lobby" }
}

public struct LiveTitle: Sendable, Decodable, Equatable, Identifiable {
    public let id: String
    public let name: String
}

public struct LivePickSession: Sendable, Decodable, Equatable, Identifiable {
    public let code: String
    public let round: Int
    public let created: Date
    public let locked: Bool
    public let matches: [LiveTitle]
    /// What they're watching together, once they are.
    public let watchingTogether: String?
    public let people: [LivePerson]

    public var id: String { code }
}

public struct LiveSessions: Sendable, Decodable, Equatable {
    public let watchParties: [LiveParty]
    public let pickSessions: [LivePickSession]
}

public struct HistorySettings: Sendable, Codable, Equatable {
    public var enabled: Bool
    /// Days to keep; nil keeps everything.
    public var keepDays: Int?

    public init(enabled: Bool, keepDays: Int?) {
        self.enabled = enabled
        self.keepDays = keepDays
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enabled, forKey: .enabled)
        // Sent even when nil: nil means keep for ever, not "leave as it was".
        try container.encode(keepDays, forKey: .keepDays)
    }
}

public struct HistoryEntry: Sendable, Decodable, Equatable, Identifiable {
    public let id: String
    /// watchParty or pickTogether.
    public let kind: String
    public let code: String
    public let created: Date
    public let scheduledFor: Date?
    public let startedWatching: Date?
    public let ended: Date
    public let hostName: String
    public let people: [String]
    public let itemName: String?
    public let matches: [String]
    /// watched, ended, cancelled, notStarted or left.
    public let outcome: String

    public var isWatchParty: Bool { kind == "watchParty" }
}

// MARK: - Client

/// The Arcfin Sync plugin's per-user features beyond settings: hidden titles, signed admin
/// commands, watch time, recommendations, watch parties, and Seerr and TMDB through the server;
/// and the admin side of each. Same sign-in and errors (`PickTogetherError`) as Pick Together.
public struct ArcfinCompanionClient: Sendable {
    public init() {}

    private let http = PickTogetherClient()

    /// Jellyfin's item and user IDs come with or without dashes depending on who wrote them.
    public static func normalized(_ id: String) -> String {
        id.replacingOccurrences(of: "-", with: "").lowercased()
    }

    // MARK: Hidden

    public func hidden(credential: ServerCredential, authHeader: String) async throws -> HiddenLists {
        try await http.send("GET", "ArcfinSync/Hidden", base: "", credential: credential, authHeader: authHeader)
    }

    public func hide(_ itemID: String, from row: HiddenRow, credential: ServerCredential, authHeader: String) async throws -> HiddenLists {
        try await http.send("PUT", "ArcfinSync/Hidden/\(row.rawValue)/\(PickTogetherClient.component(itemID))", base: "",
                            credential: credential, authHeader: authHeader)
    }

    public func unhide(_ itemID: String, from row: HiddenRow, credential: ServerCredential, authHeader: String) async throws -> HiddenLists {
        try await http.send("DELETE", "ArcfinSync/Hidden/\(row.rawValue)/\(PickTogetherClient.component(itemID))", base: "",
                            credential: credential, authHeader: authHeader)
    }

    // MARK: Signed commands

    /// The server's signing key, or nil before an admin has made one.
    /// `holding` is the fingerprint of the key this device trusts, so the server sends the keys since.
    public func signingKey(holding: String? = nil, credential: ServerCredential, authHeader: String) async throws -> ServerSigningKey? {
        let query = holding.flatMap { $0.addingPercentEncoding(withAllowedCharacters: .alphanumerics) }.map { "?from=\($0)" } ?? ""
        do {
            return try await http.send("GET", "ArcfinSync/Security/Key" + query, base: "", credential: credential, authHeader: authHeader)
        } catch let error as PickTogetherError where error.status == 404 {
            return nil
        }
    }

    /// Tells the server which key this device holds, so it isn't signed out as behind.
    /// `fingerprint` is the trusted key's, or "unverified" while none is trusted yet. The version
    /// and build let the server tell this Arcfin from older ones that can't check in at all.
    /// Whether this device is trusted; while it waits for approval, the code to check on a trusted one.
    public func checkIn(fingerprint: String, appVersion: String, build: String, credential: ServerCredential, authHeader: String) async throws -> TrustState {
        struct Body: Encodable { let fingerprint: String; let appVersion: String; let build: String }
        return try await http.send("POST", "ArcfinSync/Security/CheckIn", base: "",
                                   body: Body(fingerprint: fingerprint, appVersion: appVersion, build: build),
                                   credential: credential, authHeader: authHeader)
    }

    /// The person's other devices waiting for this one (a trusted device) to approve them.
    public func trustRequests(credential: ServerCredential, authHeader: String) async throws -> [TrustRequest] {
        try await http.send("GET", "ArcfinSync/Security/TrustRequests", base: "", credential: credential, authHeader: authHeader)
    }

    /// Trust the waiting device, or don't (which signs it out).
    public func answerTrust(_ trust: Bool, requestID: String, credential: ServerCredential, authHeader: String) async throws {
        struct Body: Encodable { let trust: Bool }
        let _: PickTogetherClient.Empty = try await http.send("POST", "ArcfinSync/Security/TrustRequests/\(PickTogetherClient.component(requestID))", base: "",
                                                              body: Body(trust: trust), credential: credential, authHeader: authHeader)
    }

    /// This device carried out a wipe; the server signs it out.
    public func reportWiped(credential: ServerCredential, authHeader: String) async throws {
        let _: PickTogetherClient.Empty = try await http.send("POST", "ArcfinSync/Security/Wiped", base: "", credential: credential, authHeader: authHeader)
    }

    /// Too many wrong PINs here under the admin's rules: Arcfin stays locked on this device until an admin unlocks it.
    public func reportPinLockout(credential: ServerCredential, authHeader: String) async throws {
        let _: PickTogetherClient.Empty = try await http.send("POST", "ArcfinSync/Security/PinLockout", base: "", credential: credential, authHeader: authHeader)
    }

    /// Someone here compared the key with the fingerprint they were shown and it didn't match.
    public func reportMismatch(fingerprint: String, credential: ServerCredential, authHeader: String) async throws {
        struct Body: Encodable { let fingerprint: String }
        let _: PickTogetherClient.Empty = try await http.send("POST", "ArcfinSync/Security/Mismatch", base: "", body: Body(fingerprint: fingerprint),
                                                              credential: credential, authHeader: authHeader)
    }

    public func commands(credential: ServerCredential, authHeader: String) async throws -> [SignedServerCommand] {
        try await http.send("GET", "ArcfinSync/Security/Commands", base: "", credential: credential, authHeader: authHeader)
    }

    // MARK: Watch time

    public func watchTime(credential: ServerCredential, authHeader: String) async throws -> WatchTimeStatus {
        try await http.send("GET", "ArcfinSync/Limits/Me", base: "", credential: credential, authHeader: authHeader)
    }

    // MARK: Recommendations

    public func recommendations(refresh: Bool = false, credential: ServerCredential, authHeader: String) async throws -> Recommendations {
        try await http.send("GET", "ArcfinSync/Recommendations" + (refresh ? "?refresh=true" : ""), base: "",
                            credential: credential, authHeader: authHeader)
    }

    // MARK: Notifications

    /// Events after `since`, or nil when the server's notifications are off or its plugin is
    /// older than 0.7. Without `since`, only the cursor and what's showing now.
    public func events(since: Int64?, credential: ServerCredential, authHeader: String) async throws -> ServerEventFeed? {
        do {
            return try await http.send("GET", "ArcfinSync/Notifications/Events" + (since.map { "?since=\($0)" } ?? ""), base: "",
                                       credential: credential, authHeader: authHeader)
        } catch let error as PickTogetherError where error.status == 404 {
            return nil
        }
    }

    // MARK: Integrations

    public func integrations(credential: ServerCredential, authHeader: String) async throws -> ServerIntegrations {
        try await http.send("GET", "ArcfinSync/Integrations", base: "", credential: credential, authHeader: authHeader)
    }

    /// Where Seerr's API is reached through the server: requests go to `<this>/api/v1/...`.
    public static func seerrProxyBase(_ baseURL: URL) -> URL {
        directory(baseURL).appendingPathComponent("ArcfinSync/Seerr")
    }

    /// Where TMDB's v3 API is reached through the server.
    public static func tmdbProxyBase(_ baseURL: URL) -> URL {
        directory(baseURL).appendingPathComponent("ArcfinSync/Tmdb/3/")
    }

    // MARK: Watch parties

    public func partyAvailability(credential: ServerCredential, authHeader: String) async throws -> PickAvailability {
        try await http.send("GET", "ArcfinSync/WatchParty", base: "", credential: credential, authHeader: authHeader)
    }

    /// A party on now, or one scheduled for `scheduledFor` (up to 30 days ahead).
    public func createParty(itemID: String, scheduledFor: Date? = nil, timeZone: String? = nil,
                            credential: ServerCredential, authHeader: String) async throws -> WatchPartyState {
        struct Body: Encodable { let itemId: String; let scheduledFor: String?; let timeZone: String? }
        return try await http.send("POST", "ArcfinSync/WatchParty/Parties", base: "",
                                   body: Body(itemId: itemID, scheduledFor: scheduledFor.map(Self.iso), timeZone: timeZone),
                                   credential: credential, authHeader: authHeader)
    }

    /// The parties this device is in, soonest first: scheduled ones to come back to, and any on now.
    public func myParties(credential: ServerCredential, authHeader: String) async throws -> [WatchPartyState] {
        try await http.send("GET", "ArcfinSync/WatchParty/Parties", base: "", credential: credential, authHeader: authHeader)
    }

    /// The host moves the start, or passes nil to make it a party that's on now.
    public func scheduleParty(_ scheduledFor: Date?, code: String, credential: ServerCredential, authHeader: String) async throws -> WatchPartyState {
        struct Body: Encodable { let scheduledFor: String? }
        return try await http.send("POST", party(code, "/Schedule"), base: "", body: Body(scheduledFor: scheduledFor.map(Self.iso)),
                                   credential: credential, authHeader: authHeader)
    }

    /// The host calls the party off for everyone.
    public func endParty(code: String, credential: ServerCredential, authHeader: String) async throws {
        let _: PickTogetherClient.Empty = try await http.send("POST", party(code, "/End"), base: "", credential: credential, authHeader: authHeader)
    }

    private static func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    public func joinParty(code: String, timeZone: String? = nil, credential: ServerCredential, authHeader: String) async throws -> WatchPartyState {
        struct Body: Encodable { let timeZone: String? }
        return try await http.send("POST", party(code, "/Join"), base: "", body: Body(timeZone: timeZone), credential: credential, authHeader: authHeader)
    }

    /// `timeZone` keeps this device's zone up to date for the others' planned-start times.
    public func party(code: String, timeZone: String? = nil, credential: ServerCredential, authHeader: String) async throws -> WatchPartyState {
        let query = timeZone.flatMap { $0.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) }.map { "?tz=\($0)" } ?? ""
        return try await http.send("GET", party(code) + query, base: "", credential: credential, authHeader: authHeader)
    }

    public func setReady(_ ready: Bool, code: String, credential: ServerCredential, authHeader: String) async throws -> WatchPartyState {
        struct Body: Encodable { let ready: Bool }
        return try await http.send("POST", party(code, "/Ready"), base: "", body: Body(ready: ready), credential: credential, authHeader: authHeader)
    }

    public func setPartyLocked(_ locked: Bool, code: String, credential: ServerCredential, authHeader: String) async throws -> WatchPartyState {
        struct Body: Encodable { let ready: Bool }
        return try await http.send("POST", party(code, "/Lock"), base: "", body: Body(ready: locked), credential: credential, authHeader: authHeader)
    }

    public func startParty(code: String, startTicks: Int64, credential: ServerCredential, authHeader: String) async throws -> WatchPartyState {
        struct Body: Encodable { let startTicks: Int64 }
        return try await http.send("POST", party(code, "/Start"), base: "", body: Body(startTicks: startTicks), credential: credential, authHeader: authHeader)
    }

    public func partyGroup(_ groupID: String, name: String? = nil, code: String, credential: ServerCredential, authHeader: String) async throws -> WatchPartyState {
        struct Body: Encodable { let groupId: String; let groupName: String? }
        return try await http.send("POST", party(code, "/Group"), base: "", body: Body(groupId: groupID, groupName: name),
                                   credential: credential, authHeader: authHeader)
    }

    public func resetParty(code: String, credential: ServerCredential, authHeader: String) async throws -> WatchPartyState {
        try await http.send("POST", party(code, "/Reset"), base: "", credential: credential, authHeader: authHeader)
    }

    public func removeFromParty(personID: String, code: String, credential: ServerCredential, authHeader: String) async throws -> WatchPartyState {
        try await http.send("DELETE", party(code, "/People/\(PickTogetherClient.component(personID))"), base: "",
                            credential: credential, authHeader: authHeader)
    }

    public func leaveParty(code: String, credential: ServerCredential, authHeader: String) async {
        let _: PickTogetherClient.Empty? = try? await http.send("DELETE", party(code, "/Me"), base: "", credential: credential, authHeader: authHeader)
    }

    /// What a party's QR code holds: just the code.
    public static func partyLink(code: String) -> URL {
        URL(string: "arcfin://party/\(PickTogetherClient.component(code))")!
    }

    /// The code in a scanned or typed party code.
    public static func partyCode(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.scheme == "arcfin", url.host == "party" {
            return url.pathComponents.dropFirst().first?.uppercased()
        }
        return PickTogetherClient.code(from: trimmed)
    }

    private func party(_ code: String, _ suffix: String = "") -> String {
        "ArcfinSync/WatchParty/Parties/\(PickTogetherClient.component(code))\(suffix)"
    }

    // MARK: Admin

    public func integrationsAdmin(credential: ServerCredential, authHeader: String) async throws -> IntegrationsAdmin {
        try await http.send("GET", "ArcfinSync/Admin/Integrations", base: "", credential: credential, authHeader: authHeader)
    }

    public func saveIntegrations(_ change: IntegrationsAdminChange, credential: ServerCredential, authHeader: String) async throws -> IntegrationsAdmin {
        try await http.send("PUT", "ArcfinSync/Admin/Integrations", base: "", body: change, credential: credential, authHeader: authHeader)
    }

    /// Checks Seerr with this address and key, or the saved ones where they're nil, without saving.
    public func testSeerr(url: String?, apiKey: String?, credential: ServerCredential, authHeader: String) async throws -> IntegrationsAdmin {
        struct Body: Encodable { let seerrUrl: String?; let seerrApiKey: String? }
        return try await http.send("POST", "ArcfinSync/Admin/Integrations/Test", base: "", body: Body(seerrUrl: url, seerrApiKey: apiKey),
                                   credential: credential, authHeader: authHeader)
    }

    public func sendQueued(credential: ServerCredential, authHeader: String) async throws -> IntegrationsAdmin {
        try await http.send("POST", "ArcfinSync/Admin/Integrations/Queue/Send", base: "", credential: credential, authHeader: authHeader)
    }

    public func dropQueued(_ id: String, credential: ServerCredential, authHeader: String) async throws -> IntegrationsAdmin {
        try await http.send("DELETE", "ArcfinSync/Admin/Integrations/Queue/\(PickTogetherClient.component(id))", base: "",
                            credential: credential, authHeader: authHeader)
    }

    public func securityAdmin(credential: ServerCredential, authHeader: String) async throws -> SecurityAdmin {
        try await http.send("GET", "ArcfinSync/Admin/Security", base: "", credential: credential, authHeader: authHeader)
    }

    /// Makes a new signing key, or adds the admin's own P-256 key in PEM.
    /// Replaces the key with one the old key doesn't vouch for: every device has to trust it again.
    public func resetSigningKey(credential: ServerCredential, authHeader: String) async throws -> SecurityAdmin {
        try await http.send("POST", "ArcfinSync/Admin/Security/Key/Reset", base: "", credential: credential, authHeader: authHeader)
    }

    public func makeSigningKey(pem: String? = nil, credential: ServerCredential, authHeader: String) async throws -> SecurityAdmin {
        struct Body: Encodable { let pem: String? }
        return try await http.send("POST", "ArcfinSync/Admin/Security/Key", base: "", body: Body(pem: pem), credential: credential, authHeader: authHeader)
    }

    /// `disableAccount` with a lock also disables the Jellyfin account and signs it out everywhere;
    /// the next unlock enables it again.
    public func sendCommand(_ kind: ServerCommandKind, userID: String, disableAccount: Bool = false,
                            credential: ServerCredential, authHeader: String) async throws -> SecurityAdmin {
        struct Body: Encodable { let userId: String; let kind: String; let disableAccount: Bool }
        return try await http.send("POST", "ArcfinSync/Admin/Security/Commands", base: "",
                                   body: Body(userId: userID, kind: kind.rawValue, disableAccount: disableAccount),
                                   credential: credential, authHeader: authHeader)
    }

    public func saveSecuritySettings(_ settings: SecuritySettings, credential: ServerCredential, authHeader: String) async throws -> SecurityAdmin {
        try await http.send("PUT", "ArcfinSync/Admin/Security/Settings", base: "", body: settings, credential: credential, authHeader: authHeader)
    }

    /// Signs out one Arcfin sign-in too old for the security features, or all of a user's when `deviceID` is nil.
    public func signOutOlder(userID: String, deviceID: String?, credential: ServerCredential, authHeader: String) async throws -> SecurityAdmin {
        struct Body: Encodable { let userId: String; let deviceId: String }
        return try await http.send("POST", "ArcfinSync/Admin/Security/Devices/SignOut", base: "", body: Body(userId: userID, deviceId: deviceID ?? ""),
                                   credential: credential, authHeader: authHeader)
    }

    /// Lets a device the rule for devices that fall behind signed out or locked use Arcfin again.
    public func unlockDevice(userID: String, deviceID: String, credential: ServerCredential, authHeader: String) async throws -> SecurityAdmin {
        struct Body: Encodable { let userId: String; let deviceId: String }
        return try await http.send("POST", "ArcfinSync/Admin/Security/Devices/Unlock", base: "", body: Body(userId: userID, deviceId: deviceID),
                                   credential: credential, authHeader: authHeader)
    }

    public func limitsAdmin(credential: ServerCredential, authHeader: String) async throws -> LimitsAdmin {
        try await http.send("GET", "ArcfinSync/Admin/Limits", base: "", credential: credential, authHeader: authHeader)
    }

    public func saveLimits(_ change: LimitsAdminChange, credential: ServerCredential, authHeader: String) async throws -> LimitsAdmin {
        try await http.send("PUT", "ArcfinSync/Admin/Limits", base: "", body: change, credential: credential, authHeader: authHeader)
    }

    public func watchPartyAdmin(credential: ServerCredential, authHeader: String) async throws -> PickTogetherAdminSettings {
        try await http.send("GET", "ArcfinSync/Admin/WatchParty", base: "", credential: credential, authHeader: authHeader)
    }

    public func saveWatchPartyAdmin(_ settings: PickTogetherAdminSettings, credential: ServerCredential, authHeader: String) async throws -> PickTogetherAdminSettings {
        try await http.send("PUT", "ArcfinSync/Admin/WatchParty", base: "", body: settings, credential: credential, authHeader: authHeader)
    }

    public func recommendationsEnabled(credential: ServerCredential, authHeader: String) async throws -> Bool {
        struct Toggle: Decodable { let enabled: Bool }
        let toggle: Toggle = try await http.send("GET", "ArcfinSync/Admin/Recommendations", base: "", credential: credential, authHeader: authHeader)
        return toggle.enabled
    }

    public func setRecommendationsEnabled(_ enabled: Bool, credential: ServerCredential, authHeader: String) async throws -> Bool {
        struct Toggle: Codable { let enabled: Bool }
        let toggle: Toggle = try await http.send("PUT", "ArcfinSync/Admin/Recommendations", base: "", body: Toggle(enabled: enabled),
                                                 credential: credential, authHeader: authHeader)
        return toggle.enabled
    }

    // MARK: Live sessions and history (admin)

    public func liveSessions(credential: ServerCredential, authHeader: String) async throws -> LiveSessions {
        try await http.send("GET", "ArcfinSync/Admin/Live", base: "", credential: credential, authHeader: authHeader)
    }

    /// Moves any party's start, or nil to make it one that's on now.
    public func adminScheduleParty(_ scheduledFor: Date?, code: String, credential: ServerCredential, authHeader: String) async throws -> LiveSessions {
        struct Body: Encodable { let scheduledFor: String? }
        return try await http.send("POST", "ArcfinSync/Admin/WatchParties/\(PickTogetherClient.component(code))/Schedule", base: "",
                                   body: Body(scheduledFor: scheduledFor.map(Self.iso)), credential: credential, authHeader: authHeader)
    }

    public func adminLockParty(_ locked: Bool, code: String, credential: ServerCredential, authHeader: String) async throws -> LiveSessions {
        struct Body: Encodable { let locked: Bool }
        return try await http.send("POST", "ArcfinSync/Admin/WatchParties/\(PickTogetherClient.component(code))/Lock", base: "",
                                   body: Body(locked: locked), credential: credential, authHeader: authHeader)
    }

    public func adminRemoveFromParty(personID: String, code: String, credential: ServerCredential, authHeader: String) async throws -> LiveSessions {
        try await http.send("DELETE", "ArcfinSync/Admin/WatchParties/\(PickTogetherClient.component(code))/People/\(PickTogetherClient.component(personID))",
                            base: "", credential: credential, authHeader: authHeader)
    }

    public func adminEndParty(code: String, credential: ServerCredential, authHeader: String) async throws -> LiveSessions {
        try await http.send("POST", "ArcfinSync/Admin/WatchParties/\(PickTogetherClient.component(code))/End", base: "",
                            credential: credential, authHeader: authHeader)
    }

    public func adminLockPick(_ locked: Bool, code: String, credential: ServerCredential, authHeader: String) async throws -> LiveSessions {
        struct Body: Encodable { let locked: Bool }
        return try await http.send("POST", "ArcfinSync/Admin/PickSessions/\(PickTogetherClient.component(code))/Lock", base: "",
                                   body: Body(locked: locked), credential: credential, authHeader: authHeader)
    }

    public func adminRemoveFromPick(personID: String, code: String, credential: ServerCredential, authHeader: String) async throws -> LiveSessions {
        try await http.send("DELETE", "ArcfinSync/Admin/PickSessions/\(PickTogetherClient.component(code))/People/\(PickTogetherClient.component(personID))",
                            base: "", credential: credential, authHeader: authHeader)
    }

    public func adminEndPick(code: String, credential: ServerCredential, authHeader: String) async throws -> LiveSessions {
        try await http.send("POST", "ArcfinSync/Admin/PickSessions/\(PickTogetherClient.component(code))/End", base: "",
                            credential: credential, authHeader: authHeader)
    }

    public func historySettings(credential: ServerCredential, authHeader: String) async throws -> HistorySettings {
        try await http.send("GET", "ArcfinSync/Admin/History/Settings", base: "", credential: credential, authHeader: authHeader)
    }

    public func saveHistorySettings(_ settings: HistorySettings, credential: ServerCredential, authHeader: String) async throws -> HistorySettings {
        try await http.send("PUT", "ArcfinSync/Admin/History/Settings", base: "", body: settings, credential: credential, authHeader: authHeader)
    }

    /// Newest first; `kind` is watchParty or pickTogether, or nil for both.
    public func history(kind: String? = nil, credential: ServerCredential, authHeader: String) async throws -> [HistoryEntry] {
        try await http.send("GET", "ArcfinSync/Admin/History" + (kind.map { "?kind=\($0)" } ?? ""), base: "", credential: credential, authHeader: authHeader)
    }

    public func clearHistory(credential: ServerCredential, authHeader: String) async throws {
        let _: PickTogetherClient.Empty = try await http.send("DELETE", "ArcfinSync/Admin/History", base: "", credential: credential, authHeader: authHeader)
    }

    // MARK: Household

    public func downloadAllowance(credential: ServerCredential, authHeader: String) async throws -> DownloadAllowance {
        try await http.send("GET", "ArcfinSync/Household/Downloads", base: "", credential: credential, authHeader: authHeader)
    }

    /// Every title (and, when given, every song) this device keeps downloaded, after each change:
    /// the server counts one on several devices once. Nil songs leaves the last list.
    public func reportDownloads(_ titles: [(itemID: String, bytes: Int64)], songs: [DownloadedSong]? = nil,
                                credential: ServerCredential, authHeader: String) async throws -> DownloadAllowance {
        struct Title: Encodable { let itemId: String; let bytes: Int64 }
        struct Body: Encodable { let titles: [Title]; let songs: [DownloadedSong]? }
        return try await http.send("PUT", "ArcfinSync/Household/Downloads", base: "",
                                   body: Body(titles: titles.map { Title(itemId: $0.itemID, bytes: $0.bytes) }, songs: songs),
                                   credential: credential, authHeader: authHeader)
    }

    /// Whether downloading this title of this size fits under the admin's caps; one already on
    /// another of the person's devices adds no title.
    public func checkDownload(itemID: String, bytes: Int64, credential: ServerCredential, authHeader: String) async throws -> DownloadCheck {
        struct Body: Encodable { let itemId: String; let bytes: Int64 }
        return try await http.send("POST", "ArcfinSync/Household/Downloads/Check", base: "", body: Body(itemId: itemID, bytes: bytes),
                                   credential: credential, authHeader: authHeader)
    }

    /// Whether these songs fit under the admin's music caps; ones already on another device don't count again.
    public func checkMusicDownload(_ songs: [DownloadedSong], credential: ServerCredential, authHeader: String) async throws -> DownloadCheck {
        struct Body: Encodable { let songs: [DownloadedSong] }
        return try await http.send("POST", "ArcfinSync/Household/Downloads/Check", base: "", body: Body(songs: songs),
                                   credential: credential, authHeader: authHeader)
    }

    public func sharedAccount(credential: ServerCredential, authHeader: String) async throws -> SharedAccountInfo {
        try await http.send("GET", "ArcfinSync/Household/Shared", base: "", credential: credential, authHeader: authHeader)
    }

    /// On a shared account's device: who's watching, so their own progress follows along.
    public func setWatching(_ memberIDs: [String], credential: ServerCredential, authHeader: String) async throws -> SharedAccountInfo {
        struct Body: Encodable { let members: [String] }
        return try await http.send("POST", "ArcfinSync/Household/Shared/Watching", base: "", body: Body(members: memberIDs),
                                   credential: credential, authHeader: authHeader)
    }

    public func notices(credential: ServerCredential, authHeader: String) async throws -> ServerNotices {
        try await http.send("GET", "ArcfinSync/Household/Notices", base: "", credential: credential, authHeader: authHeader)
    }

    // MARK: Household (admin)

    public func householdAdmin(credential: ServerCredential, authHeader: String) async throws -> HouseholdAdmin {
        try await http.send("GET", "ArcfinSync/Admin/Household", base: "", credential: credential, authHeader: authHeader)
    }

    public func saveDownloadLimits(_ settings: DownloadLimitSettings, credential: ServerCredential, authHeader: String) async throws -> HouseholdAdmin {
        try await http.send("PUT", "ArcfinSync/Admin/Household/Downloads", base: "", body: settings, credential: credential, authHeader: authHeader)
    }

    public func saveSharedAccounts(_ accounts: [SharedAccountSetting], credential: ServerCredential, authHeader: String) async throws -> HouseholdAdmin {
        try await http.send("PUT", "ArcfinSync/Admin/Household/SharedAccounts", base: "", body: accounts, credential: credential, authHeader: authHeader)
    }

    public func saveAnnouncements(_ announcements: [Announcement], credential: ServerCredential, authHeader: String) async throws -> HouseholdAdmin {
        try await http.send("PUT", "ArcfinSync/Admin/Household/Announcements", base: "", body: announcements, credential: credential, authHeader: authHeader)
    }

    public func saveMaintenance(_ windows: [MaintenanceWindow], credential: ServerCredential, authHeader: String) async throws -> HouseholdAdmin {
        try await http.send("PUT", "ArcfinSync/Admin/Household/Maintenance", base: "", body: windows, credential: credential, authHeader: authHeader)
    }

    public func hiddenEnabled(credential: ServerCredential, authHeader: String) async throws -> Bool {
        struct Toggle: Decodable { let enabled: Bool }
        let toggle: Toggle = try await http.send("GET", "ArcfinSync/Admin/Hidden", base: "", credential: credential, authHeader: authHeader)
        return toggle.enabled
    }

    public func setHiddenEnabled(_ enabled: Bool, credential: ServerCredential, authHeader: String) async throws -> Bool {
        struct Toggle: Codable { let enabled: Bool }
        let toggle: Toggle = try await http.send("PUT", "ArcfinSync/Admin/Hidden", base: "", body: Toggle(enabled: enabled), credential: credential, authHeader: authHeader)
        return toggle.enabled
    }

    /// The admin trusts a waiting device, or doesn't (which signs it out).
    public func adminAnswerTrust(_ trust: Bool, requestID: String, credential: ServerCredential, authHeader: String) async throws -> SecurityAdmin {
        struct Body: Encodable { let trust: Bool }
        return try await http.send("POST", "ArcfinSync/Admin/Security/TrustRequests/\(PickTogetherClient.component(requestID))", base: "",
                                   body: Body(trust: trust), credential: credential, authHeader: authHeader)
    }

    /// Wipes a lost device: downloads deleted, Arcfin locked, then signed out.
    public func wipeDevice(userID: String, deviceID: String, credential: ServerCredential, authHeader: String) async throws -> SecurityAdmin {
        struct Body: Encodable { let userId: String; let deviceId: String }
        return try await http.send("POST", "ArcfinSync/Admin/Security/Devices/Wipe", base: "", body: Body(userId: userID, deviceId: deviceID),
                                   credential: credential, authHeader: authHeader)
    }

    private static func directory(_ base: URL) -> URL {
        base.absoluteString.hasSuffix("/") ? base : URL(string: base.absoluteString + "/") ?? base
    }
}
