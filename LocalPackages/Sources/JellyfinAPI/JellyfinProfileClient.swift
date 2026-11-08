// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import AuthCore

/// One rating the server knows, e.g. "PG-13". `score` is what a user's maximum is compared
/// against (Jellyfin 10.10+); older servers only send `value`.
public struct ParentalRating: Sendable, Equatable {
    public let name: String
    public let score: Int?
    public let subScore: Int?

    public init(name: String, score: Int?, subScore: Int? = nil) {
        self.name = name
        self.score = score
        self.subScore = subScore
    }
}

/// A window of time the profile may use the server in, as set in its parental controls.
public struct AccessSchedule: Sendable, Equatable {
    /// "Sunday"…"Saturday", or "Everyday", "Weekday", "Weekend".
    public let dayOfWeek: String
    /// Hours from midnight, e.g. 7.5 is 7:30.
    public let startHour: Double
    public let endHour: Double

    public init(dayOfWeek: String, startHour: Double, endHour: Double) {
        self.dayOfWeek = dayOfWeek
        self.startHour = startHour
        self.endHour = endHour
    }
}

/// What the server lets this profile do and see. The server already applies the content
/// rules to everything it returns; the app reads them to apply the same rules to what comes
/// from elsewhere (Seerr) and to hide features the profile can't use.
public struct UserPolicy: Sendable, Equatable {
    public var isAdministrator = false
    public var maxParentalRating: Int?
    public var maxParentalSubRating: Int?
    /// Item kinds hidden when they have no rating: "Movie", "Series", "Trailer", "Book",
    /// "ChannelContent", "LiveTvChannel", "LiveTvProgram", "Music", "Other".
    public var blockUnratedItems: [String] = []
    public var blockedTags: [String] = []
    public var allowedTags: [String] = []
    public var accessSchedules: [AccessSchedule] = []
    public var enableMediaPlayback = true
    public var enableContentDownloading = true
    public var enableSubtitleManagement = false
    public var enableCollectionManagement = false
    public var enableContentDeletion = false
    public var enableLiveTvAccess = true
    public var enableRemoteAccess = true
    public var enableVideoPlaybackTranscoding = true
    public var enableAudioPlaybackTranscoding = true
    public var enablePlaybackRemuxing = true
    public var forceRemoteSourceTranscoding = false
    public var enablePublicSharing = true
    /// Bits per second; nil or 0 for no limit.
    public var remoteClientBitrateLimit: Int?
    /// 0 for no limit.
    public var maxActiveSessions = 0
    /// "CreateAndJoinGroups", "JoinGroups" or "None".
    public var syncPlayAccess = "CreateAndJoinGroups"
    /// When false, only the libraries in `enabledFolders` are visible.
    public var enableAllFolders = true
    public var enabledFolders: [String] = []

    public init() {}

    /// Anything limiting what content this profile may see.
    public var restrictsContent: Bool {
        maxParentalRating != nil || !blockUnratedItems.isEmpty || !blockedTags.isEmpty || !allowedTags.isEmpty
    }
}

/// The profile as the server describes it: account details, its playback preferences and
/// its policy.
public struct UserProfileDetails: Sendable, Equatable {
    public var name: String
    public var serverName: String?
    public var hasPassword: Bool
    public var lastLoginDate: Date?
    public var lastActivityDate: Date?
    public var audioLanguagePreference: String?
    public var subtitleLanguagePreference: String?
    /// "Default", "Always", "OnlyForced", "None", "Smart".
    public var subtitleMode: String?
    public var playDefaultAudioTrack: Bool
    public var enableNextEpisodeAutoPlay: Bool
    public var rememberAudioSelections: Bool
    public var rememberSubtitleSelections: Bool
    public var hidePlayedInLatest: Bool
    public var policy: UserPolicy
}

extension JellyfinMediaClient {

    public func getUserProfile(credential: ServerCredential, authHeader: String) async throws -> UserProfileDetails {
        var req = URLRequest(url: credential.baseURL.appendingPathComponent("Users/\(credential.userID)"))
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        let (data, response) = try await URLSession.arcfin.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw JellyfinRequestError.status(http.statusCode)
        }
        return try JSONDecoder().decode(UserResponse.self, from: data).model
    }

    /// Libraries the account leaves out of its latest titles (Jellyfin's own Home setting).
    public func getLatestExcludedLibraries(credential: ServerCredential, authHeader: String) async throws -> [String] {
        let configuration = try await userConfiguration(credential: credential, authHeader: authHeader)
        return configuration["LatestItemsExcludes"] as? [String] ?? []
    }

    /// Writes the account's whole configuration back with only this list changed, so the
    /// rest of its settings stay as they were.
    public func setLatestExcludedLibraries(_ ids: [String], credential: ServerCredential, authHeader: String) async throws {
        var configuration = try await userConfiguration(credential: credential, authHeader: authHeader)
        configuration["LatestItemsExcludes"] = ids
        var req = URLRequest(url: credential.baseURL.appendingPathComponent("Users/\(credential.userID)/Configuration"))
        req.httpMethod = "POST"
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: configuration)
        req.timeoutInterval = 15
        let (_, response) = try await URLSession.arcfin.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw JellyfinRequestError.status(http.statusCode)
        }
    }

    private func userConfiguration(credential: ServerCredential, authHeader: String) async throws -> [String: Any] {
        var req = URLRequest(url: credential.baseURL.appendingPathComponent("Users/\(credential.userID)"))
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        let (data, response) = try await URLSession.arcfin.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw JellyfinRequestError.status(http.statusCode)
        }
        guard let user = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let configuration = user["Configuration"] as? [String: Any]
        else { throw JellyfinRequestError.status(-1) }
        return configuration
    }

    /// The server's own clock, from the Date header of an unauthenticated ping.
    public func getServerDate(baseURL: URL) async -> Date? {
        var req = URLRequest(url: baseURL.appendingPathComponent("System/Ping"))
        req.timeoutInterval = 8
        guard let (_, response) = try? await URLSession.arcfin.data(for: req),
              let header = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Date")
        else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: header)
    }

    public func getParentalRatings(credential: ServerCredential, authHeader: String) async throws -> [ParentalRating] {
        var req = URLRequest(url: credential.baseURL.appendingPathComponent("Localization/ParentalRatings"))
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15
        let (data, _) = try await URLSession.arcfin.data(for: req)
        return try JSONDecoder().decode([RatingResponse].self, from: data).map(\.model)
    }
}

// MARK: - Response types

private struct RatingResponse: Decodable {
    struct Score: Decodable {
        let score: Int?
        let subScore: Int?
    }
    let name: String
    let value: Int?
    let ratingScore: Score?

    enum CodingKeys: String, CodingKey { case name = "Name", value = "Value", ratingScore = "RatingScore" }

    var model: ParentalRating {
        ParentalRating(name: name, score: ratingScore?.score ?? value, subScore: ratingScore?.subScore)
    }
}

private struct UserResponse: Decodable {
    struct Configuration: Decodable {
        let audioLanguagePreference: String?
        let subtitleLanguagePreference: String?
        let subtitleMode: String?
        let playDefaultAudioTrack: Bool?
        let enableNextEpisodeAutoPlay: Bool?
        let rememberAudioSelections: Bool?
        let rememberSubtitleSelections: Bool?
        let hidePlayedInLatest: Bool?

        enum CodingKeys: String, CodingKey {
            case audioLanguagePreference = "AudioLanguagePreference"
            case subtitleLanguagePreference = "SubtitleLanguagePreference"
            case subtitleMode = "SubtitleMode"
            case playDefaultAudioTrack = "PlayDefaultAudioTrack"
            case enableNextEpisodeAutoPlay = "EnableNextEpisodeAutoPlay"
            case rememberAudioSelections = "RememberAudioSelections"
            case rememberSubtitleSelections = "RememberSubtitleSelections"
            case hidePlayedInLatest = "HidePlayedInLatest"
        }
    }

    struct Schedule: Decodable {
        let dayOfWeek: String
        let startHour: Double
        let endHour: Double
        enum CodingKeys: String, CodingKey { case dayOfWeek = "DayOfWeek", startHour = "StartHour", endHour = "EndHour" }
    }

    struct Policy: Decodable {
        let isAdministrator: Bool?
        let maxParentalRating: Int?
        let maxParentalSubRating: Int?
        let blockUnratedItems: [String]?
        let blockedTags: [String]?
        let allowedTags: [String]?
        let accessSchedules: [Schedule]?
        let enableMediaPlayback: Bool?
        let enableContentDownloading: Bool?
        let enableSubtitleManagement: Bool?
        let enableCollectionManagement: Bool?
        let enableContentDeletion: Bool?
        let enableLiveTvAccess: Bool?
        let enableRemoteAccess: Bool?
        let enableVideoPlaybackTranscoding: Bool?
        let enableAudioPlaybackTranscoding: Bool?
        let enablePlaybackRemuxing: Bool?
        let forceRemoteSourceTranscoding: Bool?
        let enablePublicSharing: Bool?
        let remoteClientBitrateLimit: Int?
        let maxActiveSessions: Int?
        let syncPlayAccess: String?
        let enableAllFolders: Bool?
        let enabledFolders: [String]?

        enum CodingKeys: String, CodingKey {
            case isAdministrator = "IsAdministrator", maxParentalRating = "MaxParentalRating"
            case maxParentalSubRating = "MaxParentalSubRating", blockUnratedItems = "BlockUnratedItems"
            case blockedTags = "BlockedTags", allowedTags = "AllowedTags", accessSchedules = "AccessSchedules"
            case enableMediaPlayback = "EnableMediaPlayback", enableContentDownloading = "EnableContentDownloading"
            case enableSubtitleManagement = "EnableSubtitleManagement"
            case enableCollectionManagement = "EnableCollectionManagement"
            case enableContentDeletion = "EnableContentDeletion", enableLiveTvAccess = "EnableLiveTvAccess"
            case enableRemoteAccess = "EnableRemoteAccess"
            case enableVideoPlaybackTranscoding = "EnableVideoPlaybackTranscoding"
            case enableAudioPlaybackTranscoding = "EnableAudioPlaybackTranscoding"
            case enablePlaybackRemuxing = "EnablePlaybackRemuxing"
            case forceRemoteSourceTranscoding = "ForceRemoteSourceTranscoding"
            case enablePublicSharing = "EnablePublicSharing"
            case remoteClientBitrateLimit = "RemoteClientBitrateLimit", maxActiveSessions = "MaxActiveSessions"
            case syncPlayAccess = "SyncPlayAccess"
            case enableAllFolders = "EnableAllFolders", enabledFolders = "EnabledFolders"
        }
    }

    let name: String
    let serverName: String?
    let hasPassword: Bool?
    let lastLoginDate: String?
    let lastActivityDate: String?
    let configuration: Configuration?
    let policy: Policy?

    enum CodingKeys: String, CodingKey {
        case name = "Name", serverName = "ServerName", hasPassword = "HasPassword"
        case lastLoginDate = "LastLoginDate", lastActivityDate = "LastActivityDate"
        case configuration = "Configuration", policy = "Policy"
    }

    var model: UserProfileDetails {
        var p = UserPolicy()
        if let policy {
            p.isAdministrator = policy.isAdministrator ?? false
            p.maxParentalRating = policy.maxParentalRating
            p.maxParentalSubRating = policy.maxParentalSubRating
            p.blockUnratedItems = policy.blockUnratedItems ?? []
            p.blockedTags = policy.blockedTags ?? []
            p.allowedTags = policy.allowedTags ?? []
            p.accessSchedules = (policy.accessSchedules ?? []).map {
                AccessSchedule(dayOfWeek: $0.dayOfWeek, startHour: $0.startHour, endHour: $0.endHour)
            }
            p.enableMediaPlayback = policy.enableMediaPlayback ?? true
            p.enableContentDownloading = policy.enableContentDownloading ?? true
            p.enableSubtitleManagement = policy.enableSubtitleManagement ?? false
            p.enableCollectionManagement = policy.enableCollectionManagement ?? false
            p.enableContentDeletion = policy.enableContentDeletion ?? false
            p.enableLiveTvAccess = policy.enableLiveTvAccess ?? true
            p.enableRemoteAccess = policy.enableRemoteAccess ?? true
            p.enableVideoPlaybackTranscoding = policy.enableVideoPlaybackTranscoding ?? true
            p.enableAudioPlaybackTranscoding = policy.enableAudioPlaybackTranscoding ?? true
            p.enablePlaybackRemuxing = policy.enablePlaybackRemuxing ?? true
            p.forceRemoteSourceTranscoding = policy.forceRemoteSourceTranscoding ?? false
            p.enablePublicSharing = policy.enablePublicSharing ?? true
            p.remoteClientBitrateLimit = policy.remoteClientBitrateLimit
            p.maxActiveSessions = policy.maxActiveSessions ?? 0
            p.syncPlayAccess = policy.syncPlayAccess ?? "CreateAndJoinGroups"
            p.enableAllFolders = policy.enableAllFolders ?? true
            p.enabledFolders = policy.enabledFolders ?? []
        }
        return UserProfileDetails(
            name: name, serverName: serverName, hasPassword: hasPassword ?? true,
            lastLoginDate: lastLoginDate.flatMap(Self.parseDate),
            lastActivityDate: lastActivityDate.flatMap(Self.parseDate),
            audioLanguagePreference: configuration?.audioLanguagePreference,
            subtitleLanguagePreference: configuration?.subtitleLanguagePreference,
            subtitleMode: configuration?.subtitleMode,
            playDefaultAudioTrack: configuration?.playDefaultAudioTrack ?? true,
            enableNextEpisodeAutoPlay: configuration?.enableNextEpisodeAutoPlay ?? true,
            rememberAudioSelections: configuration?.rememberAudioSelections ?? true,
            rememberSubtitleSelections: configuration?.rememberSubtitleSelections ?? true,
            hidePlayedInLatest: configuration?.hidePlayedInLatest ?? true,
            policy: p)
    }

    /// Jellyfin sends 7-digit fractional seconds, which ISO8601DateFormatter rejects with
    /// fractional seconds enabled; trimming to whole seconds is plenty for "last seen".
    private static func parseDate(_ raw: String) -> Date? {
        let trimmed = raw.split(separator: ".").first.map(String.init) ?? raw
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: trimmed.hasSuffix("Z") ? trimmed : trimmed + "Z")
    }
}
