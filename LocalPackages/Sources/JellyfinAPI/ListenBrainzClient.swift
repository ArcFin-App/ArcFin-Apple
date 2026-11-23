// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// One song heard, for ListenBrainz. `listenedAt` is when it started (Unix seconds); a song
/// only just started has none.
public struct ListenBrainzListen: Codable, Sendable, Equatable {
    public var listenedAt: Int?
    public var artist: String
    public var track: String
    public var release: String?
    public var durationMS: Int?

    public init(listenedAt: Int?, artist: String, track: String, release: String? = nil, durationMS: Int? = nil) {
        self.listenedAt = listenedAt; self.artist = artist; self.track = track
        self.release = release; self.durationMS = durationMS
    }
}

public enum ListenBrainzError: Error, Equatable {
    /// ListenBrainz doesn't know the token.
    case invalidToken
    case rejected(status: Int)
}

/// Sends a profile's listens to ListenBrainz with its user token.
public struct ListenBrainzClient: Sendable {
    public static let baseURL = URL(string: "https://api.listenbrainz.org")!
    /// ListenBrainz takes up to 1000 listens in one request.
    public static let maxListensPerRequest = 1000

    private let token: String
    private let baseURL: URL
    private let clientVersion: String

    public init(token: String, clientVersion: String, baseURL: URL = Self.baseURL) {
        self.token = token
        self.clientVersion = clientVersion
        self.baseURL = baseURL
    }

    /// Its own session, without the custom headers meant for the Jellyfin server.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    /// The account's name, or nil when ListenBrainz doesn't know the token.
    public func validate() async throws -> String? {
        struct Validation: Decodable {
            let valid: Bool
            let userName: String?
            enum CodingKeys: String, CodingKey { case valid, userName = "user_name" }
        }
        var request = URLRequest(url: baseURL.appendingPathComponent("1/validate-token"))
        request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
        let data = try await send(request)
        let validation = try JSONDecoder().decode(Validation.self, from: data)
        return validation.valid ? validation.userName : nil
    }

    /// The song that just started, shown on the profile until the next one. Returns the id
    /// ListenBrainz gave the recording, which loving or hating it needs.
    @discardableResult
    public func playingNow(_ listen: ListenBrainzListen) async throws -> String? {
        let data = try await submit(type: "playing_now", [listen], returnsMSID: true)
        return Self.recordingMSID(in: data)
    }

    /// The docs name the field but not where it sits in the reply, so it's looked for anywhere.
    static func recordingMSID(in data: Data) -> String? {
        func find(_ value: Any) -> String? {
            if let object = value as? [String: Any] {
                if let id = object["recording_msid"] as? String { return id }
                return object.values.lazy.compactMap(find).first
            }
            if let array = value as? [Any] { return array.lazy.compactMap(find).first }
            return nil
        }
        return (try? JSONSerialization.jsonObject(with: data)).flatMap(find)
    }

    /// Loves (1), hates (-1) or clears (0) a recording on the profile.
    public func feedback(recordingMSID: String, score: Int) async throws {
        struct Body: Encodable {
            let recordingMSID: String
            let score: Int
            enum CodingKeys: String, CodingKey { case recordingMSID = "recording_msid", score }
        }
        var request = URLRequest(url: baseURL.appendingPathComponent("1/feedback/recording-feedback"))
        request.httpMethod = "POST"
        request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Body(recordingMSID: recordingMSID, score: score))
        _ = try await send(request)
    }

    /// The profile's love (1), hate (-1) or neither (0) for a recording.
    public func feedbackScore(userName: String, recordingMSID: String) async throws -> Int {
        struct Reply: Decodable {
            struct Item: Decodable { let score: Int }
            let feedback: [Item]
        }
        var comps = URLComponents(url: baseURL.appendingPathComponent("1/feedback/user/\(userName)/get-feedback-for-recordings"),
                                  resolvingAgainstBaseURL: false)
        comps?.queryItems = [.init(name: "recording_msids", value: recordingMSID)]
        guard let url = comps?.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
        let reply = try JSONDecoder().decode(Reply.self, from: try await send(request))
        return reply.feedback.first?.score ?? 0
    }

    /// Songs heard, at most `maxListensPerRequest`.
    public func submit(_ listens: [ListenBrainzListen]) async throws {
        try await submit(type: listens.count == 1 ? "single" : "import", listens)
    }

    @discardableResult
    private func submit(type: String, _ listens: [ListenBrainzListen], returnsMSID: Bool = false) async throws -> Data {
        var comps = URLComponents(url: baseURL.appendingPathComponent("1/submit-listens"), resolvingAgainstBaseURL: false)
        if returnsMSID { comps?.queryItems = [.init(name: "return_msid", value: "true")] }
        guard let url = comps?.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Self.body(type: type, listens: listens, clientVersion: clientVersion)
        return try await send(request)
    }

    private func send(_ request: URLRequest) async throws -> Data {
        await withCheckedContinuation { PathWait(continuation: $0).start(timeoutSeconds: 6) }
        var request = request
        request.timeoutInterval = 20
        let (data, response) = try await Self.session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw ListenBrainzError.invalidToken }
        guard (200...299).contains(status) else { throw ListenBrainzError.rejected(status: status) }
        return data
    }

    static func body(type: String, listens: [ListenBrainzListen], clientVersion: String) throws -> Data {
        struct Body: Encodable {
            let listenType: String
            let payload: [Payload]
            enum CodingKeys: String, CodingKey { case listenType = "listen_type", payload }
        }
        struct Payload: Encodable {
            let listenedAt: Int?
            let trackMetadata: Metadata
            enum CodingKeys: String, CodingKey { case listenedAt = "listened_at", trackMetadata = "track_metadata" }
        }
        struct Metadata: Encodable {
            let artistName: String
            let trackName: String
            let releaseName: String?
            let additionalInfo: Info
            enum CodingKeys: String, CodingKey {
                case artistName = "artist_name", trackName = "track_name", releaseName = "release_name"
                case additionalInfo = "additional_info"
            }
        }
        struct Info: Encodable {
            let mediaPlayer = "Arcfin"
            let submissionClient = "Arcfin"
            let submissionClientVersion: String
            let durationMS: Int?
            enum CodingKeys: String, CodingKey {
                case mediaPlayer = "media_player", submissionClient = "submission_client"
                case submissionClientVersion = "submission_client_version", durationMS = "duration_ms"
            }
        }
        // A playing-now listen must not carry a time.
        let payload = listens.map { listen in
            Payload(listenedAt: type == "playing_now" ? nil : listen.listenedAt,
                    trackMetadata: Metadata(artistName: listen.artist, trackName: listen.track,
                                            releaseName: listen.release,
                                            additionalInfo: Info(submissionClientVersion: clientVersion,
                                                                 durationMS: listen.durationMS)))
        }
        return try JSONEncoder().encode(Body(listenType: type, payload: payload))
    }
}

/// How much of one play of a song has been heard, and whether it counts as a listen yet:
/// half the song or four minutes, whichever is less, as ListenBrainz asks. Only steady
/// progress counts, so a seek to the end doesn't make a listen.
public struct ListenBrainzPlay: Sendable, Equatable {
    public let songID: String
    public let startedAt: Date
    public private(set) var heard: TimeInterval = 0
    public private(set) var isCounted = false
    private var last: Double
    private let needed: TimeInterval

    public init(songID: String, duration: TimeInterval?, at seconds: Double, now: Date = .now) {
        self.songID = songID
        startedAt = now.addingTimeInterval(-seconds)
        last = seconds
        needed = min(240, (duration ?? 480) / 2)
    }

    /// A start part-way into the same song (a resume, or a hand-off to a Chromecast) carries
    /// on this play rather than beginning another.
    public func continues(songID: String, at seconds: Double) -> Bool {
        songID == self.songID && seconds > 5
    }

    public mutating func moved(to seconds: Double) { last = seconds }

    /// True the first time the play counts as a listen.
    public mutating func reached(_ seconds: Double) -> Bool {
        let step = seconds - last
        last = seconds
        // Reports come every ten seconds while playing; a bigger step is a seek.
        if step > 0, step <= 15 { heard += step }
        guard !isCounted, heard >= needed else { return false }
        isCounted = true
        return true
    }
}

/// A year of listening as ListenBrainz counts it.
public struct ListenBrainzYear: Sendable, Equatable {
    public struct Entry: Sendable, Equatable, Hashable {
        public var name: String
        public var artist: String?
        public var listens: Int
    }
    public struct Month: Sendable, Equatable {
        public var start: Date
        public var listens: Int
    }
    public var songs: [Entry] = []
    public var artists: [Entry] = []
    public var albums: [Entry] = []
    public var months: [Month] = []

    public var totalListens: Int { months.reduce(0) { $0 + $1.listens } }
    public var busiestMonth: Month? { months.max { $0.listens < $1.listens } }
}

extension ListenBrainzClient {
    /// The ranges ListenBrainz works stats out for: the current week, month and year, the
    /// previous ones, and all time.
    public enum StatsRange: String, Sendable {
        case thisWeek = "this_week", thisMonth = "this_month", thisYear = "this_year"
        case lastWeek = "week", lastMonth = "month", lastYear = "year"
        case allTime = "all_time"
    }

    /// This year's top songs, artists and albums and listens per month. ListenBrainz works
    /// stats out once a day; a part it hasn't worked out yet comes back empty.
    public func thisYear(userName: String) async throws -> ListenBrainzYear {
        let startOfYear = Calendar.current.date(from: Calendar.current.dateComponents([.year], from: .now)) ?? .distantPast
        return try await stats(userName: userName, range: .thisYear, since: startOfYear)
    }

    /// One range's top songs, artists and albums, and its listens over time (by day for a week
    /// or month, by month for a year, by year for all time) from `since` up to `until`.
    public func stats(userName: String, range: StatsRange, since: Date = .distantPast,
                      until: Date = .distantFuture) async throws -> ListenBrainzYear {
        func stats(_ kind: String, count: Int = 25) async throws -> Data? {
            var comps = URLComponents(url: baseURL.appendingPathComponent("1/stats/user/\(userName)/\(kind)"),
                                      resolvingAgainstBaseURL: false)
            comps?.queryItems = [.init(name: "range", value: range.rawValue), .init(name: "count", value: String(count))]
            guard let url = comps?.url else { throw URLError(.badURL) }
            let data = try await send(URLRequest(url: url))
            return data.isEmpty ? nil : data
        }
        async let songs = stats("recordings")
        async let artists = stats("artists")
        async let albums = stats("releases")
        async let activity = stats("listening-activity")
        return try Self.year(songs: await songs, artists: await artists, albums: await albums, activity: await activity,
                             since: since, until: until)
    }

    /// `since` leaves out earlier months: ListenBrainz works out the previous period too, and
    /// its docs don't say whether this year's activity comes with last year's.
    static func year(songs: Data?, artists: Data?, albums: Data?, activity: Data?,
                     since: Date = .distantPast, until: Date = .distantFuture) throws -> ListenBrainzYear {
        func entries(_ data: Data?, list: String, name: String) throws -> [ListenBrainzYear.Entry] {
            guard let data, let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let payload = object["payload"] as? [String: Any], let items = payload[list] as? [[String: Any]]
            else { return [] }
            return items.compactMap { item in
                guard let title = item[name] as? String else { return nil }
                return .init(name: title, artist: list == "artists" ? nil : item["artist_name"] as? String,
                             listens: item["listen_count"] as? Int ?? 0)
            }
        }
        var year = ListenBrainzYear()
        year.songs = try entries(songs, list: "recordings", name: "track_name")
        year.artists = try entries(artists, list: "artists", name: "artist_name")
        year.albums = try entries(albums, list: "releases", name: "release_name")
        if let activity, let object = try JSONSerialization.jsonObject(with: activity) as? [String: Any],
           let payload = object["payload"] as? [String: Any],
           let items = payload["listening_activity"] as? [[String: Any]] {
            year.months = items.compactMap { item in
                guard let from = item["from_ts"] as? Int else { return nil }
                let start = Date(timeIntervalSince1970: TimeInterval(from))
                guard start >= since, start < until else { return nil }
                return .init(start: start, listens: item["listen_count"] as? Int ?? 0)
            }
        }
        return year
    }
}
