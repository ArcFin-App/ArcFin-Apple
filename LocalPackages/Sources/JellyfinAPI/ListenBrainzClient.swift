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

    /// The song that just started, shown on the profile until the next one.
    public func playingNow(_ listen: ListenBrainzListen) async throws {
        try await submit(type: "playing_now", [listen])
    }

    /// Songs heard, at most `maxListensPerRequest`.
    public func submit(_ listens: [ListenBrainzListen]) async throws {
        try await submit(type: listens.count == 1 ? "single" : "import", listens)
    }

    private func submit(type: String, _ listens: [ListenBrainzListen]) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("1/submit-listens"))
        request.httpMethod = "POST"
        request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Self.body(type: type, listens: listens, clientVersion: clientVersion)
        _ = try await send(request)
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
