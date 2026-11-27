// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import AuthCore

// MARK: - Models

/// What this server's admin allows for Arcs, and whether it's on for this user.
public struct ArcsAvailability: Sendable, Decodable, Equatable {
    public enum Sharing: String, Sendable, Codable, CaseIterable { case allowed = "Allowed", off = "Off" }
    public enum Watermark: String, Sendable, Codable, CaseIterable { case optional = "Optional", forced = "Forced", off = "Off" }
    public enum Spoilers: String, Sendable, Codable, CaseIterable { case userChoice = "UserChoice", alwaysSafe = "AlwaysSafe" }

    public let enabled: Bool
    public let sharing: Sharing
    public let watermark: Watermark
    public let minSeconds: Int
    public let maxSeconds: Int
    public let defaultSeconds: Int
    public let spoilers: Spoilers
    public let clipOfTheDay: Bool
    /// Scenes can be sent to other people on the server.
    public let sending: Bool
    /// The server indexes what's said, so scenes can be searched by it.
    public let dialogueSearch: Bool
    /// Trailers of titles to request can be mixed in (Seerr is set up and the admin allows it).
    public let requests: Bool
    /// Request clips may play YouTube trailers: the admin's switch, over each person's own.
    public let youTubeTrailers: Bool
    /// Scenes friends sent that haven't been watched yet.
    public let unseen: Int

    enum CodingKeys: String, CodingKey {
        case enabled, sharing, watermark, minSeconds, maxSeconds, defaultSeconds, spoilers, clipOfTheDay, sending, dialogueSearch, requests, youTubeTrailers, unseen
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decode(Bool.self, forKey: .enabled)
        sharing = try c.decodeIfPresent(Sharing.self, forKey: .sharing) ?? .allowed
        watermark = try c.decodeIfPresent(Watermark.self, forKey: .watermark) ?? .optional
        minSeconds = try c.decodeIfPresent(Int.self, forKey: .minSeconds) ?? 15
        maxSeconds = try c.decodeIfPresent(Int.self, forKey: .maxSeconds) ?? 60
        defaultSeconds = try c.decodeIfPresent(Int.self, forKey: .defaultSeconds) ?? 30
        spoilers = try c.decodeIfPresent(Spoilers.self, forKey: .spoilers) ?? .userChoice
        clipOfTheDay = try c.decodeIfPresent(Bool.self, forKey: .clipOfTheDay) ?? true
        // "Everyone" / "Off" on the wire.
        sending = (try? c.decodeIfPresent(String.self, forKey: .sending)).flatMap { $0 }.map { $0 != "Off" }
            ?? (try? c.decodeIfPresent(Bool.self, forKey: .sending)).flatMap { $0 } ?? false
        dialogueSearch = try c.decodeIfPresent(Bool.self, forKey: .dialogueSearch) ?? false
        requests = try c.decodeIfPresent(Bool.self, forKey: .requests) ?? false
        youTubeTrailers = try c.decodeIfPresent(Bool.self, forKey: .youTubeTrailers) ?? true
        unseen = try c.decodeIfPresent(Int.self, forKey: .unseen) ?? 0
    }

    public init(enabled: Bool, sharing: Sharing = .allowed, watermark: Watermark = .optional, minSeconds: Int = 15,
                maxSeconds: Int = 60, defaultSeconds: Int = 30, spoilers: Spoilers = .userChoice, clipOfTheDay: Bool = true) {
        self.enabled = enabled
        self.sharing = sharing
        self.watermark = watermark
        self.minSeconds = minSeconds
        self.maxSeconds = maxSeconds
        self.defaultSeconds = defaultSeconds
        self.spoilers = spoilers
        self.clipOfTheDay = clipOfTheDay
        sending = false
        dialogueSearch = false
        requests = false
        youTubeTrailers = true
        unseen = 0
    }
}

public enum ArcsFeed: String, Sendable, Codable, CaseIterable, Identifiable {
    case forYou, `continue`, discover, series, liked
    public var id: String { rawValue }
}

public struct ArcSubtitle: Sendable, Codable, Equatable, Hashable {
    public let index: Int
    public let language: String?
    public let title: String?
    public let isDefault: Bool
}

/// Why a clip is in the feed, shown under its title.
public struct ArcReason: Sendable, Codable, Equatable, Hashable {
    public enum Kind: String, Sendable, Codable {
        case because, `continue`, discover, popular, new, explore, series, liked, top, request, sent
        case unknown
        public init(from decoder: Decoder) throws {
            self = Kind(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
        }
    }
    public let kind: Kind
    public let seedName: String?
}

/// One scene in the feed: a stretch of a film or an episode.
public struct ArcClip: Sendable, Codable, Equatable, Hashable, Identifiable {
    public let id: String
    public let itemId: String
    public let mediaSourceId: String?
    public let type: String
    public let name: String
    public let seriesId: String?
    public let seriesName: String?
    public let seasonNumber: Int?
    public let episodeNumber: Int?
    public let chapterName: String?
    public let overview: String?
    public let year: Int?
    public let officialRating: String?
    public let communityRating: Double?
    public let genres: [String]
    public let startTicks: Int64
    public let endTicks: Int64
    public let runtimeTicks: Int64?
    public let width: Int?
    public let height: Int?
    public let subtitles: [ArcSubtitle]
    public let reason: ArcReason?
    public var liked: Bool
    public var disliked: Bool
    public var isFavorite: Bool
    public var likeCount: Int
    /// "scene", or "request": a title not on the server, shown with its trailer to request.
    public let kind: String
    public let isColdOpen: Bool
    public var myReaction: ArcReaction?
    public var reactions: [String: Int]
    public let matchedLine: String?
    public let matchedTicks: Int64?
    public let sentBy: String?
    public let sentNote: String?
    public let tmdbId: Int?
    public let mediaType: String?
    public let trailerYouTubeKey: String?
    public let posterPath: String?
    public let backdropPath: String?

    public var isRequest: Bool { kind == "request" }

    public var isEpisode: Bool { type == "Episode" }
    public var seconds: Double { Double(endTicks - startTicks) / 10_000_000 }
    /// The series for an episode, otherwise the film: what "Hide" and "Fewer" act on.
    public var titleID: String { seriesId ?? itemId }
    /// Wider than tall, so a portrait screen has to crop or letterbox it.
    public var isLandscape: Bool {
        guard let width, let height, height > 0 else { return true }
        return width > height
    }

    enum CodingKeys: String, CodingKey {
        case id, itemId, mediaSourceId, type, name, seriesId, seriesName, seasonNumber, episodeNumber, chapterName,
             overview, year, officialRating, communityRating, genres, startTicks, endTicks, runtimeTicks, width,
             height, subtitles, reason, liked, disliked, isFavorite, likeCount, kind, isColdOpen, myReaction, reactions,
             matchedLine, matchedTicks, sentBy, sentNote, tmdbId, mediaType, trailerYouTubeKey, posterPath, backdropPath
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        itemId = try c.decode(String.self, forKey: .itemId)
        mediaSourceId = try c.decodeIfPresent(String.self, forKey: .mediaSourceId)
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? "Movie"
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        seriesId = try c.decodeIfPresent(String.self, forKey: .seriesId)
        seriesName = try c.decodeIfPresent(String.self, forKey: .seriesName)
        seasonNumber = try c.decodeIfPresent(Int.self, forKey: .seasonNumber)
        episodeNumber = try c.decodeIfPresent(Int.self, forKey: .episodeNumber)
        chapterName = try c.decodeIfPresent(String.self, forKey: .chapterName)
        overview = try c.decodeIfPresent(String.self, forKey: .overview)
        year = try c.decodeIfPresent(Int.self, forKey: .year)
        officialRating = try c.decodeIfPresent(String.self, forKey: .officialRating)
        communityRating = try c.decodeIfPresent(Double.self, forKey: .communityRating)
        genres = try c.decodeIfPresent([String].self, forKey: .genres) ?? []
        startTicks = try c.decode(Int64.self, forKey: .startTicks)
        endTicks = try c.decode(Int64.self, forKey: .endTicks)
        runtimeTicks = try c.decodeIfPresent(Int64.self, forKey: .runtimeTicks)
        width = try c.decodeIfPresent(Int.self, forKey: .width)
        height = try c.decodeIfPresent(Int.self, forKey: .height)
        subtitles = try c.decodeIfPresent([ArcSubtitle].self, forKey: .subtitles) ?? []
        reason = try c.decodeIfPresent(ArcReason.self, forKey: .reason)
        liked = try c.decodeIfPresent(Bool.self, forKey: .liked) ?? false
        disliked = try c.decodeIfPresent(Bool.self, forKey: .disliked) ?? false
        isFavorite = try c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        likeCount = try c.decodeIfPresent(Int.self, forKey: .likeCount) ?? 0
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "scene"
        isColdOpen = try c.decodeIfPresent(Bool.self, forKey: .isColdOpen) ?? false
        myReaction = try c.decodeIfPresent(String.self, forKey: .myReaction).flatMap(ArcReaction.init(rawValue:))
        reactions = try c.decodeIfPresent([String: Int].self, forKey: .reactions) ?? [:]
        matchedLine = try c.decodeIfPresent(String.self, forKey: .matchedLine)
        matchedTicks = try c.decodeIfPresent(Int64.self, forKey: .matchedTicks)
        sentBy = try c.decodeIfPresent(String.self, forKey: .sentBy)
        sentNote = try c.decodeIfPresent(String.self, forKey: .sentNote)
        tmdbId = try c.decodeIfPresent(Int.self, forKey: .tmdbId)
        mediaType = try c.decodeIfPresent(String.self, forKey: .mediaType)
        trailerYouTubeKey = try c.decodeIfPresent(String.self, forKey: .trailerYouTubeKey)
        posterPath = try c.decodeIfPresent(String.self, forKey: .posterPath)
        backdropPath = try c.decodeIfPresent(String.self, forKey: .backdropPath)
    }
}

/// A quick reaction to a scene, beside the like.
public enum ArcReaction: String, Sendable, Codable, CaseIterable {
    case funny, wow, sad
}

/// The moods the feed can be narrowed to.
public enum ArcsMood: String, Sendable, CaseIterable, Identifiable {
    case funny, action, feelgood, scary, drama, scifi
    public var id: String { rawValue }
}

/// Someone else on the server a scene can be sent to.
public struct ArcPerson: Sendable, Decodable, Equatable, Hashable, Identifiable {
    public let id: String
    public let name: String
}

public struct ArcFriends: Sendable, Decodable, Equatable {
    public let code: String
    public let friends: [ArcPerson]
}

/// This person's own Arcs, for Stats.
public struct ArcsMyStats: Sendable, Decodable, Equatable {
    public struct Title: Sendable, Decodable, Equatable, Hashable, Identifiable {
        public let id: String
        public let name: String
        public let scenes: Int
    }
    public let scenes: Int
    public let minutes: Int
    public let likes: Int
    public let shares: Int
    public let watchFromHere: Int
    public let topTitles: [Title]
    public let mostRewatched: ArcClip?
    public let topReaction: ArcReaction?
    public let since: Date?

    enum CodingKeys: String, CodingKey {
        case scenes, minutes, likes, shares, watchFromHere, topTitles, mostRewatched, topReaction, since
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        scenes = try c.decodeIfPresent(Int.self, forKey: .scenes) ?? 0
        minutes = try c.decodeIfPresent(Int.self, forKey: .minutes) ?? 0
        likes = try c.decodeIfPresent(Int.self, forKey: .likes) ?? 0
        shares = try c.decodeIfPresent(Int.self, forKey: .shares) ?? 0
        watchFromHere = try c.decodeIfPresent(Int.self, forKey: .watchFromHere) ?? 0
        topTitles = try c.decodeIfPresent([Title].self, forKey: .topTitles) ?? []
        mostRewatched = try c.decodeIfPresent(ArcClip.self, forKey: .mostRewatched)
        topReaction = try c.decodeIfPresent(String.self, forKey: .topReaction).flatMap(ArcReaction.init(rawValue:))
        since = try c.decodeIfPresent(Date.self, forKey: .since)
    }
}

public struct ArcsPage: Sendable, Decodable, Equatable {
    public let clips: [ArcClip]
    public let cursor: String?
}

public enum ArcEventKind: String, Sendable, Encodable {
    case view, like, unlike, dislike, undislike, share, watchFromHere, openTitle, rewatch,
         fewerFromSeries, hide, unhide, report, notNow, react, request, startEpisode
}

public struct ArcEvent: Sendable, Encodable {
    public let clipId: String
    public let itemId: String
    public let seriesId: String?
    public let kind: ArcEventKind
    public let watchedSeconds: Double?
    public let clipSeconds: Double?
    public let feed: String?
    public let at: Date
    /// For `react`: the reaction, or "none" to clear it.
    public let reaction: String?

    public init(clip: ArcClip, kind: ArcEventKind, watchedSeconds: Double? = nil, feed: ArcsFeed? = nil,
                reaction: String? = nil, at: Date = .now) {
        clipId = clip.id
        itemId = clip.itemId
        seriesId = clip.seriesId
        self.kind = kind
        self.watchedSeconds = watchedSeconds
        clipSeconds = clip.seconds
        self.feed = feed?.rawValue
        self.at = at
        self.reaction = reaction
    }
}

/// A title kept out of the feed: hidden for good, shown less, or skipped for a while.
public struct ArcHiddenTitle: Sendable, Decodable, Equatable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let kind: String
    public let until: Date?
}

public struct ArcsAdminSettings: Sendable, Codable, Equatable {
    public struct Weights: Sendable, Codable, Equatable {
        public var history = 1.0, likes = 1.0, watchTime = 1.0, watchFromHere = 1.0, shares = 1.0,
                   favorites = 1.0, similar = 1.0, popular = 1.0, exploration = 0.15, fresh = 1.0
        public init() {}
    }

    public var enabled = true
    public var disabledUsers: [String] = []
    public var libraries: [String] = []
    public var minSeconds = 15
    public var maxSeconds = 60
    public var defaultSeconds = 30
    public var spoilers: ArcsAvailability.Spoilers = .userChoice
    public var sharing: ArcsAvailability.Sharing = .allowed
    public var watermark: ArcsAvailability.Watermark = .optional
    public var clipOfTheDay = true
    public var bannedItems: [String] = []
    public var cacheMb = 2048
    public var prewarm = 3
    public var useSceneDetection = true
    /// Titles the scene index scans side by side, 1 to 8.
    public var sceneScans = 1
    public var weights = Weights()
    public var requestsInFeed = true
    public var youTubeTrailers = true
    /// "Everyone" or "Off".
    public var sending = "Everyone"
    public var dialogueSearch = true

    public init() {}
}

public struct ArcsAdminStats: Sendable, Decodable, Equatable {
    public let clips: Int
    public let indexedTitles: Int
    public let cacheMb: Double
    public let likes: Int
    public let shares: Int
    public let watchFromHere: Int
    public let topLiked: [ArcClip]
    public let topWatchFromHere: [ArcClip]
}

// MARK: - Client

/// Arcs, served by the Arcfin Sync plugin under ArcfinSync/Arcs: the feed, its signals and the
/// clips' video, which the plugin cuts from the library with the server's own ffmpeg.
public struct ArcsClient: Sendable {
    public init() {}

    private static let base = "ArcfinSync/Arcs"
    private let plumbing = PickTogetherClient()

    /// `spoilerSafe` as the feed uses it, so the count of unwatched sent scenes matches what it shows.
    public func availability(spoilerSafe: Bool = true, credential: ServerCredential, authHeader: String) async throws -> ArcsAvailability {
        try await plumbing.send("GET", "?spoilerSafe=\(spoilerSafe)", base: Self.base, credential: credential, authHeader: authHeader)
    }

    public func feed(_ feed: ArcsFeed, count: Int = 10, cursor: String? = nil, spoilerSafe: Bool, seconds: Int,
                     seriesID: String? = nil, exclude: [String] = [], quality: Quality = .high,
                     mood: ArcsMood? = nil, requests: Bool = false,
                     credential: ServerCredential, authHeader: String) async throws -> ArcsPage {
        var query = [URLQueryItem(name: "feed", value: feed.rawValue), URLQueryItem(name: "count", value: String(count)),
                     URLQueryItem(name: "spoilerSafe", value: spoilerSafe ? "true" : "false"),
                     URLQueryItem(name: "seconds", value: String(seconds)),
                     // The scenes the server makes ahead are made at this quality, to match what's asked for next.
                     URLQueryItem(name: "quality", value: quality.rawValue)]
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        if let seriesID { query.append(URLQueryItem(name: "seriesId", value: seriesID)) }
        if let mood { query.append(URLQueryItem(name: "mood", value: mood.rawValue)) }
        if requests { query.append(URLQueryItem(name: "requests", value: "true")) }
        // The newest ones: a long session's list would make the address too long.
        if !exclude.isEmpty { query.append(URLQueryItem(name: "exclude", value: exclude.suffix(60).joined(separator: ","))) }
        return try await plumbing.send("GET", "/Feed?" + Self.encode(query), base: Self.base, credential: credential, authHeader: authHeader)
    }

    /// Scenes whose dialogue matches `text`, from the server's index of subtitle lines.
    public func search(_ text: String, seconds: Int, count: Int = 20, credential: ServerCredential, authHeader: String) async throws -> [ArcClip] {
        let query = [URLQueryItem(name: "q", value: text), URLQueryItem(name: "count", value: String(count)),
                     URLQueryItem(name: "seconds", value: String(seconds))]
        let page: ArcsPage = try await plumbing.send("GET", "/Search?" + Self.encode(query), base: Self.base, credential: credential, authHeader: authHeader)
        return page.clips
    }

    /// A film's or show's best scenes, for its page.
    public func top(itemID: String, spoilerSafe: Bool, count: Int = 10, credential: ServerCredential, authHeader: String) async throws -> [ArcClip] {
        let query = [URLQueryItem(name: "itemId", value: itemID), URLQueryItem(name: "count", value: String(count)),
                     URLQueryItem(name: "spoilerSafe", value: spoilerSafe ? "true" : "false")]
        let page: ArcsPage = try await plumbing.send("GET", "/Top?" + Self.encode(query), base: Self.base, credential: credential, authHeader: authHeader)
        return page.clips
    }

    /// This person's friend code and friends: the only people they can send scenes to.
    public func friends(credential: ServerCredential, authHeader: String) async throws -> ArcFriends {
        try await plumbing.send("GET", "/Friends", base: Self.base, credential: credential, authHeader: authHeader)
    }

    /// Adds whoever has this code; it works both ways.
    public func addFriend(code: String, credential: ServerCredential, authHeader: String) async throws -> ArcPerson {
        struct Body: Encodable { let code: String }
        return try await plumbing.send("POST", "/Friends", base: Self.base, body: Body(code: code), credential: credential, authHeader: authHeader)
    }

    public func removeFriend(_ id: String, credential: ServerCredential, authHeader: String) async throws {
        let _: PickTogetherClient.Empty = try await plumbing.send("DELETE", "/Friends/\(PickTogetherClient.component(id))", base: Self.base,
                                                                   credential: credential, authHeader: authHeader)
    }

    /// A new code; the old one stops working, friends stay.
    public func newFriendCode(credential: ServerCredential, authHeader: String) async throws -> String {
        struct Result: Decodable { let code: String }
        let result: Result = try await plumbing.send("POST", "/Friends/Code", base: Self.base, credential: credential, authHeader: authHeader)
        return result.code
    }

    /// What a friend QR code holds: just the code, nothing about the server.
    public static func friendLink(code: String) -> URL {
        URL(string: "arcfin://arcs-friend/\(PickTogetherClient.component(code))")!
    }

    /// The code in a scanned or typed friend code: an arcfin://arcs-friend/<code> link, or the code itself.
    public static func friendCode(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.scheme == "arcfin", url.host == "arcs-friend" {
            return url.pathComponents.dropFirst().first?.uppercased()
        }
        let code = trimmed.uppercased().filter { $0.isLetter || $0.isNumber }
        return (6...12).contains(code.count) ? code : nil
    }

    public func people(credential: ServerCredential, authHeader: String) async throws -> [ArcPerson] {
        struct Result: Decodable { let people: [ArcPerson] }
        let result: Result = try await plumbing.send("GET", "/People", base: Self.base, credential: credential, authHeader: authHeader)
        return result.people
    }

    public func send(clipID: String, to personID: String, note: String?, credential: ServerCredential, authHeader: String) async throws {
        struct Body: Encodable { let clipId: String; let toUserId: String; let note: String? }
        let _: PickTogetherClient.Empty = try await plumbing.send("POST", "/Send", base: Self.base,
                                                                   body: Body(clipId: clipID, toUserId: personID, note: note),
                                                                   credential: credential, authHeader: authHeader)
    }

    public func myStats(credential: ServerCredential, authHeader: String) async throws -> ArcsMyStats {
        try await plumbing.send("GET", "/Me/Stats", base: Self.base, credential: credential, authHeader: authHeader)
    }

    /// A TMDB image for a request clip.
    public static func tmdbImageURL(_ path: String?, width: Int = 780) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w\(width)\(path)")
    }

    /// One scene picked for this person for today, or nil when there's none (or the admin turned it off).
    public func clipOfTheDay(credential: ServerCredential, authHeader: String) async throws -> ArcClip? {
        let result: Optional204<ArcClip> = try await plumbing.send("GET", "/ClipOfTheDay", base: Self.base,
                                                                    credential: credential, authHeader: authHeader)
        return result.value
    }

    public func send(_ events: [ArcEvent], credential: ServerCredential, authHeader: String) async throws {
        struct Body: Encodable { let events: [ArcEvent] }
        let _: PickTogetherClient.Empty = try await plumbing.send("POST", "/Events", base: Self.base, body: Body(events: events),
                                                                   credential: credential, authHeader: authHeader)
    }

    public func hidden(credential: ServerCredential, authHeader: String) async throws -> [ArcHiddenTitle] {
        struct Result: Decodable { let items: [ArcHiddenTitle] }
        let result: Result = try await plumbing.send("GET", "/Hidden", base: Self.base, credential: credential, authHeader: authHeader)
        return result.items
    }

    public func unhide(_ id: String, credential: ServerCredential, authHeader: String) async throws {
        let _: PickTogetherClient.Empty = try await plumbing.send("DELETE", "/Hidden/\(PickTogetherClient.component(id))", base: Self.base,
                                                                   credential: credential, authHeader: authHeader)
    }

    /// Forgets this person's Arcs history: likes, what they skipped and hid.
    public func reset(credential: ServerCredential, authHeader: String) async throws {
        let _: PickTogetherClient.Empty = try await plumbing.send("DELETE", "/Me", base: Self.base, credential: credential, authHeader: authHeader)
    }

    public enum Quality: String, Sendable { case high, low }
    public enum Purpose: String, Sendable { case feed, share }

    /// The clip's video, an MP4 the plugin renders and keeps; ask for it with `authHeader` as the
    /// Authorization header.
    public static func videoURL(for clip: ArcClip, seconds: Int, quality: Quality, purpose: Purpose = .feed,
                                subtitle: Int? = nil, baseURL: URL) -> URL? {
        var query = [URLQueryItem(name: "seconds", value: String(seconds)), URLQueryItem(name: "quality", value: quality.rawValue),
                     URLQueryItem(name: "purpose", value: purpose.rawValue)]
        if let subtitle { query.append(URLQueryItem(name: "subtitle", value: String(subtitle))) }
        return URL(string: "\(base)/Clips/\(PickTogetherClient.component(clip.id))/Video?\(encode(query))", relativeTo: directory(baseURL))?.absoluteURL
    }

    /// The clip as HLS for the feed: the server makes it as it plays, so it starts within a moment.
    public static func streamURL(for clip: ArcClip, seconds: Int, quality: Quality, baseURL: URL) -> URL? {
        let query = [URLQueryItem(name: "seconds", value: String(seconds)), URLQueryItem(name: "quality", value: quality.rawValue)]
        return URL(string: "\(base)/Clips/\(PickTogetherClient.component(clip.id))/Stream.m3u8?\(encode(query))", relativeTo: directory(baseURL))?.absoluteURL
    }

    /// A text subtitle for the clip's stretch, timed from the clip's start, from Jellyfin itself.
    public static func subtitleURL(for clip: ArcClip, index: Int, baseURL: URL) -> URL? {
        URL(string: "Videos/\(clip.itemId)/\(clip.mediaSourceId ?? clip.itemId)/Subtitles/\(index)/\(clip.startTicks)/Stream.vtt",
            relativeTo: directory(baseURL))?.absoluteURL
    }

    // MARK: Admin

    public func adminSettings(credential: ServerCredential, authHeader: String) async throws -> ArcsAdminSettings {
        try await plumbing.send("GET", "", base: "ArcfinSync/Admin/Arcs", credential: credential, authHeader: authHeader)
    }

    public func saveAdminSettings(_ settings: ArcsAdminSettings, credential: ServerCredential, authHeader: String) async throws -> ArcsAdminSettings {
        try await plumbing.send("PUT", "", base: "ArcfinSync/Admin/Arcs", body: settings, credential: credential, authHeader: authHeader)
    }

    public func adminStats(credential: ServerCredential, authHeader: String) async throws -> ArcsAdminStats {
        try await plumbing.send("GET", "/Stats", base: "ArcfinSync/Admin/Arcs", credential: credential, authHeader: authHeader)
    }

    public func rebuildIndex(credential: ServerCredential, authHeader: String) async throws {
        let _: PickTogetherClient.Empty = try await plumbing.send("POST", "/Index", base: "ArcfinSync/Admin/Arcs",
                                                                   credential: credential, authHeader: authHeader)
    }

    public func rebuildDialogueIndex(credential: ServerCredential, authHeader: String) async throws {
        let _: PickTogetherClient.Empty = try await plumbing.send("POST", "/DialogueIndex", base: "ArcfinSync/Admin/Arcs",
                                                                   credential: credential, authHeader: authHeader)
    }

    public func clearCache(credential: ServerCredential, authHeader: String) async throws {
        let _: PickTogetherClient.Empty = try await plumbing.send("DELETE", "/Cache", base: "ArcfinSync/Admin/Arcs",
                                                                   credential: credential, authHeader: authHeader)
    }

    // MARK: Saved clips

    /// A clip as JSON in the server's own form, so `decodeClip` reads it back the same way.
    public static func encodeClip(_ clip: ArcClip) throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .custom { keys in Key(keys.last!.stringValue.prefix(1).uppercased() + keys.last!.stringValue.dropFirst()) }
        return try encoder.encode(clip)
    }

    public static func decodeClip(_ data: Data) throws -> ArcClip {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .custom { keys in Key(keys.last!.stringValue.prefix(1).lowercased() + keys.last!.stringValue.dropFirst()) }
        return try decoder.decode(ArcClip.self, from: data)
    }

    private struct Key: CodingKey {
        let stringValue: String
        let intValue: Int? = nil
        init(_ value: String) { stringValue = value }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    // MARK: Plumbing

    private static func encode(_ items: [URLQueryItem]) -> String {
        var comps = URLComponents()
        comps.queryItems = items
        return comps.percentEncodedQuery ?? ""
    }

    private static func directory(_ base: URL) -> URL {
        base.absoluteString.hasSuffix("/") ? base : URL(string: base.absoluteString + "/") ?? base
    }
}

/// A response that can come back with no body (204), for `send` to hand back without decoding.
protocol EmptyBodyDecodable { static var emptyBody: Self { get } }

/// A body that may be missing: 204 No Content decodes as nil.
struct Optional204<T: Decodable & Sendable>: Decodable, Sendable, EmptyBodyDecodable {
    let value: T?
    static var emptyBody: Self { Self(value: nil) }
    init(value: T?) { self.value = value }
    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}
