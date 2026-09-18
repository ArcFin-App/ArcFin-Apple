import Foundation
import AuthCore

// MARK: - Playback models

public struct JellyfinMediaStream: Sendable, Equatable {
    public let index: Int
    public let type: String          // "Audio" | "Subtitle" | "Video"
    public let codec: String?
    public let language: String?
    public let displayTitle: String?
    public let isDefault: Bool
    public let isForced: Bool
    public let isExternal: Bool
    /// Server-provided path to fetch this subtitle track's content (relative to base URL) —
    /// nil for embedded/non-subtitle streams.
    public let deliveryUrl: String?
}

/// Trickplay scrub-thumbnail sprite sheet info (Jellyfin 10.9+ "Trickplay" plugin/core
/// feature — absent entirely if the server hasn't generated it for this item).
public struct JellyfinTrickplayInfo: Sendable {
    public let width: Int
    public let height: Int
    public let tileWidth: Int
    public let tileHeight: Int
    public let thumbnailCount: Int
    public let intervalMs: Int
}

public struct JellyfinPlaybackInfo: Sendable {
    public let mediaSourceId: String
    public let playURL: URL
    public let isTranscoding: Bool
    public let container: String?
    public let runTimeTicks: Int64?
    public let audioStreams: [JellyfinMediaStream]
    public let subtitleStreams: [JellyfinMediaStream]
    public let defaultAudioStreamIndex: Int?
    public let defaultSubtitleStreamIndex: Int?
    public let trickplay: JellyfinTrickplayInfo?
}

/// Caps applied when the user overrides automatic quality — nil means uncapped/Auto.
public struct StreamQualityCap: Sendable, Equatable {
    public let maxBitrate: Int?      // bits per second
    public let maxWidth: Int?
    /// When true, forces a transcode even if the source would already qualify for direct
    /// play under these caps (e.g. a 720p source with a 1080p cap) — a manual quality
    /// override should always visibly re-encode, not silently no-op.
    public let forceTranscode: Bool

    public init(maxBitrate: Int?, maxWidth: Int?, forceTranscode: Bool = false) {
        self.maxBitrate = maxBitrate
        self.maxWidth = maxWidth
        self.forceTranscode = forceTranscode
    }

    public static let auto = StreamQualityCap(maxBitrate: nil, maxWidth: nil)
}

extension JellyfinMediaClient {

    // MARK: - Playback info (direct play / transcode decision)

    public func getPlaybackInfo(
        credential: ServerCredential,
        authHeader: String,
        itemId: String,
        quality: StreamQualityCap = .auto,
        audioStreamIndex: Int? = nil,
        subtitleStreamIndex: Int? = nil
    ) async throws -> JellyfinPlaybackInfo {
        var comps = URLComponents(
            url: credential.baseURL.appendingPathComponent("Items/\(itemId)/PlaybackInfo"),
            resolvingAgainstBaseURL: false)!
        comps.queryItems = [.init(name: "UserId", value: credential.userID)]

        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 20

        var body: [String: Any] = [
            "UserId": credential.userID,
            "AutoOpenLiveStream": true,
            "DeviceProfile": Self.deviceProfile,
        ]
        if let maxBitrate = quality.maxBitrate { body["MaxStreamingBitrate"] = maxBitrate }
        // MaxWidth forces a resolution-based transcode even when the source's bitrate
        // metadata is missing or under the cap — MaxStreamingBitrate alone only forces a
        // transcode when the server actually has bitrate metadata to compare against.
        if let maxWidth = quality.maxWidth { body["MaxWidth"] = maxWidth }
        if quality.forceTranscode {
            body["EnableDirectPlay"] = false
            body["EnableDirectStream"] = false
        }
        if let audioStreamIndex { body["AudioStreamIndex"] = audioStreamIndex }
        if let subtitleStreamIndex { body["SubtitleStreamIndex"] = subtitleStreamIndex }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(PlaybackInfoResponse.self, from: data)
        guard let source = decoded.mediaSources.first else { throw URLError(.cannotParseResponse) }

        let playURL: URL
        let isTranscoding: Bool
        if let transcodingUrl = source.transcodingUrl {
            // TranscodingUrl is a relative path+query (e.g. "/videos/x/master.m3u8?...") —
            // appendingPathComponent would percent-encode the "?" into the path itself and
            // silently break the URL, so parse and recombine with the base host instead.
            guard let relative = URLComponents(string: transcodingUrl),
                  var combined = URLComponents(url: credential.baseURL, resolvingAgainstBaseURL: false)
            else { throw URLError(.badURL) }
            let basePath = combined.path.hasSuffix("/") ? String(combined.path.dropLast()) : combined.path
            let relativePath = relative.path.hasPrefix("/") ? relative.path : "/" + relative.path
            combined.path = basePath + relativePath
            combined.query = relative.query
            guard let url = combined.url else { throw URLError(.badURL) }
            playURL = url
            isTranscoding = true
        } else {
            // The extension must be in the path, not just a query param — AVFoundation
            // demuxes a static stream by sniffing the URL's file extension, and without
            // one it falls back to the server's Content-Type, which is unreliable for
            // correctly picking up every track (this is what produced video-with-no-audio).
            let container = source.container ?? "mp4"
            var directComps = URLComponents(
                url: credential.baseURL.appendingPathComponent("Videos/\(itemId)/stream.\(container)"),
                resolvingAgainstBaseURL: false)!
            directComps.queryItems = [
                .init(name: "static", value: "true"),
                .init(name: "mediaSourceId", value: source.id),
                .init(name: "api_key", value: credential.accessToken),
            ]
            playURL = directComps.url!
            isTranscoding = false
        }

        let streams = source.mediaStreams ?? []
        let audioStreams = streams.filter { $0.type == "Audio" }.map { $0.toStream() }
        let subtitleStreams = streams.filter { $0.type == "Subtitle" }.map { $0.toStream() }

        return JellyfinPlaybackInfo(
            mediaSourceId: source.id,
            playURL: playURL,
            isTranscoding: isTranscoding,
            container: source.container,
            runTimeTicks: source.runTimeTicks,
            audioStreams: audioStreams,
            subtitleStreams: subtitleStreams,
            defaultAudioStreamIndex: audioStreams.first(where: \.isDefault)?.index ?? audioStreams.first?.index,
            defaultSubtitleStreamIndex: subtitleStreams.first(where: \.isDefault)?.index,
            trickplay: source.trickplayInfo?.preferred()
        )
    }

    /// The tile-sheet URL for one trickplay tile — cache these client-side, each holds
    /// tileWidth × tileHeight individual thumbnail frames.
    public func trickplayTileURL(credential: ServerCredential, itemId: String, width: Int, tileIndex: Int) -> URL {
        var comps = URLComponents(
            url: credential.baseURL.appendingPathComponent("Videos/\(itemId)/Trickplay/\(width)/\(tileIndex).jpg"),
            resolvingAgainstBaseURL: false)!
        comps.queryItems = [.init(name: "api_key", value: credential.accessToken)]
        return comps.url!
    }

    // MARK: - Playback progress reporting

    public func reportPlaybackStart(credential: ServerCredential, authHeader: String, itemId: String, mediaSourceId: String, positionTicks: Int64) async {
        await postPlaybackEvent(credential: credential, authHeader: authHeader, path: "Sessions/Playing",
                                itemId: itemId, mediaSourceId: mediaSourceId, positionTicks: positionTicks, isPaused: false)
    }

    public func reportPlaybackProgress(credential: ServerCredential, authHeader: String, itemId: String, mediaSourceId: String, positionTicks: Int64, isPaused: Bool) async {
        await postPlaybackEvent(credential: credential, authHeader: authHeader, path: "Sessions/Playing/Progress",
                                itemId: itemId, mediaSourceId: mediaSourceId, positionTicks: positionTicks, isPaused: isPaused)
    }

    public func reportPlaybackStopped(credential: ServerCredential, authHeader: String, itemId: String, mediaSourceId: String, positionTicks: Int64) async {
        await postPlaybackEvent(credential: credential, authHeader: authHeader, path: "Sessions/Playing/Stopped",
                                itemId: itemId, mediaSourceId: mediaSourceId, positionTicks: positionTicks, isPaused: false)
    }

    private func postPlaybackEvent(credential: ServerCredential, authHeader: String, path: String, itemId: String, mediaSourceId: String, positionTicks: Int64, isPaused: Bool) async {
        var req = URLRequest(url: credential.baseURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 8
        let body: [String: Any] = [
            "ItemId": itemId,
            "MediaSourceId": mediaSourceId,
            "PositionTicks": positionTicks,
            "IsPaused": isPaused,
            "PlayMethod": "DirectPlay",
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: req)
    }

    // MARK: - Intro/credits skip markers (community "Intro Skipper" plugin — optional)

    public func getSkipSegments(credential: ServerCredential, authHeader: String, itemId: String) async -> (introEnd: Double?, creditsStart: Double?) {
        async let intro = fetchSegment(credential: credential, authHeader: authHeader, itemId: itemId, kind: "Introduction")
        async let credits = fetchSegment(credential: credential, authHeader: authHeader, itemId: itemId, kind: "Credits")
        return (await intro, await credits)
    }

    private func fetchSegment(credential: ServerCredential, authHeader: String, itemId: String, kind: String) async -> Double? {
        var req = URLRequest(url: credential.baseURL.appendingPathComponent("Episode/\(itemId)/IntroTimestamps/\(kind)"))
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 6
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        struct Segment: Decodable { let end: Double? }
        return (try? JSONDecoder().decode(Segment.self, from: data))?.end
    }

    // MARK: - Device profile

    private static var deviceProfile: [String: Any] { [
        "MaxStreamingBitrate": 120_000_000,
        // AudioCodec lists are deliberately narrow: AVFoundation can't reliably decode
        // ac3/eac3/dts to the built-in speaker/headphones on-device (only passthrough to
        // a compatible receiver, which isn't guaranteed) — claiming them as direct-play
        // compatible produced video with silent audio. Anything else gets remuxed with
        // audio transcoded to AAC while video stays copied, via the profiles below.
        // mkv is deliberately absent — AVFoundation's native Matroska support is
        // unreliable even for codec-compatible files (routinely "Cannot Open" on
        // real-world encodes), so mkv sources always remux into HLS below instead.
        "DirectPlayProfiles": [
            ["Container": "mp4,m4v", "Type": "Video", "VideoCodec": "h264,hevc", "AudioCodec": "aac,mp3,alac,flac"],
            ["Container": "mov", "Type": "Video", "VideoCodec": "h264,hevc", "AudioCodec": "aac,mp3,alac"],
        ],
        "TranscodingProfiles": [
            [
                "Container": "ts", "Type": "Video", "AudioCodec": "aac",
                "VideoCodec": "h264,hevc", "Context": "Streaming", "Protocol": "hls",
                "MaxAudioChannels": "6", "MinSegments": "2", "BreakOnNonKeyFrames": true,
            ],
        ],
        "CodecProfiles": [
            ["Type": "Video", "Codec": "h264",
             "Conditions": [["Condition": "LessThanEqual", "Property": "VideoBitDepth", "Value": "8"]]],
        ],
        // vtt only — the client parses/renders subtitles itself (see SubtitleLoader), so a
        // single consistent, easily-parsed format is preferable to juggling srt/ass too.
        // Jellyfin converts any source subtitle format to vtt on request.
        "SubtitleProfiles": [
            ["Format": "vtt", "Method": "External"],
        ],
    ] }
}

// MARK: - Private response decoders

private struct PlaybackInfoResponse: Decodable {
    let mediaSources: [MediaSourceResponse]
    enum CodingKeys: String, CodingKey { case mediaSources = "MediaSources" }
}

private struct MediaSourceResponse: Decodable {
    let id: String
    let container: String?
    let runTimeTicks: Int64?
    let transcodingUrl: String?
    let mediaStreams: [MediaStreamStreamResponse]?
    let trickplayInfo: [String: TrickplayResponse]?

    enum CodingKeys: String, CodingKey {
        case id = "Id", container = "Container", runTimeTicks = "RunTimeTicks"
        case transcodingUrl = "TranscodingUrl", mediaStreams = "MediaStreams"
        case trickplayInfo = "TrickplayInfo"
    }
}

private struct TrickplayResponse: Decodable {
    let width: Int
    let height: Int
    let tileWidth: Int
    let tileHeight: Int
    let thumbnailCount: Int
    let interval: Int

    enum CodingKeys: String, CodingKey {
        case width = "Width", height = "Height"
        case tileWidth = "TileWidth", tileHeight = "TileHeight"
        case thumbnailCount = "ThumbnailCount", interval = "Interval"
    }
}

private extension [String: TrickplayResponse] {
    /// Smallest available resolution — a fast-loading, small scrub-preview image is
    /// preferable here since it's only ever shown at thumbnail size.
    func preferred() -> JellyfinTrickplayInfo? {
        guard let smallest = values.min(by: { $0.width < $1.width }) else { return nil }
        return JellyfinTrickplayInfo(
            width: smallest.width, height: smallest.height,
            tileWidth: smallest.tileWidth, tileHeight: smallest.tileHeight,
            thumbnailCount: smallest.thumbnailCount, intervalMs: smallest.interval
        )
    }
}

private struct MediaStreamStreamResponse: Decodable {
    let index: Int
    let type: String
    let codec: String?
    let language: String?
    let displayTitle: String?
    let isDefault: Bool?
    let isForced: Bool?
    let isExternal: Bool?
    let deliveryUrl: String?

    enum CodingKeys: String, CodingKey {
        case index = "Index", type = "Type", codec = "Codec", language = "Language"
        case displayTitle = "DisplayTitle", isDefault = "IsDefault"
        case isForced = "IsForced", isExternal = "IsExternal"
        case deliveryUrl = "DeliveryUrl"
    }

    func toStream() -> JellyfinMediaStream {
        JellyfinMediaStream(
            index: index, type: type, codec: codec, language: language,
            displayTitle: displayTitle, isDefault: isDefault ?? false,
            isForced: isForced ?? false, isExternal: isExternal ?? false,
            deliveryUrl: deliveryUrl
        )
    }
}
