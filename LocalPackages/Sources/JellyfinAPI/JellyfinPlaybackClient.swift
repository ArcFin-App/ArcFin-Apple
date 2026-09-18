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
}

/// Caps applied when the user overrides automatic quality — nil means uncapped/Auto.
public struct StreamQualityCap: Sendable, Equatable {
    public let maxBitrate: Int?      // bits per second
    public let maxWidth: Int?

    public init(maxBitrate: Int?, maxWidth: Int?) {
        self.maxBitrate = maxBitrate
        self.maxWidth = maxWidth
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
            var directComps = URLComponents(
                url: credential.baseURL.appendingPathComponent("Videos/\(itemId)/stream"),
                resolvingAgainstBaseURL: false)!
            directComps.queryItems = [
                .init(name: "static", value: "true"),
                .init(name: "mediaSourceId", value: source.id),
                .init(name: "api_key", value: credential.accessToken),
                .init(name: "Container", value: source.container ?? "mp4"),
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
            defaultSubtitleStreamIndex: subtitleStreams.first(where: \.isDefault)?.index
        )
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
        "DirectPlayProfiles": [
            ["Container": "mp4,m4v", "Type": "Video", "VideoCodec": "h264,hevc", "AudioCodec": "aac,mp3,alac,flac"],
            ["Container": "mkv", "Type": "Video", "VideoCodec": "h264,hevc", "AudioCodec": "aac,mp3,alac,flac"],
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
        "SubtitleProfiles": [
            ["Format": "srt", "Method": "External"],
            ["Format": "vtt", "Method": "External"],
            ["Format": "ass", "Method": "External"],
            ["Format": "subrip", "Method": "External"],
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

    enum CodingKeys: String, CodingKey {
        case id = "Id", container = "Container", runTimeTicks = "RunTimeTicks"
        case transcodingUrl = "TranscodingUrl", mediaStreams = "MediaStreams"
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

    enum CodingKeys: String, CodingKey {
        case index = "Index", type = "Type", codec = "Codec", language = "Language"
        case displayTitle = "DisplayTitle", isDefault = "IsDefault"
        case isForced = "IsForced", isExternal = "IsExternal"
    }

    func toStream() -> JellyfinMediaStream {
        JellyfinMediaStream(
            index: index, type: type, codec: codec, language: language,
            displayTitle: displayTitle, isDefault: isDefault ?? false,
            isForced: isForced ?? false, isExternal: isExternal ?? false
        )
    }
}
