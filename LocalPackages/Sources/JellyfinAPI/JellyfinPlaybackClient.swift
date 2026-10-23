// SPDX-License-Identifier: AGPL-3.0-or-later

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
    /// Video-only — source pixel dimensions, used to cap the quality picker at what the
    /// source actually offers (no point advertising 4K for a 1080p source).
    public let width: Int?
    public let height: Int?
    /// Video-only — "SDR" | "HDR10" | "HDR10+" | "DolbyVision" | "HLG", nil if unknown.
    public let videoRange: String?
    /// Video-only, bits/sec — fallback for JellyfinPlaybackInfo.bitrate, since Jellyfin
    /// often leaves the MediaSource-level aggregate Bitrate null while still reporting
    /// this per-stream one.
    public let bitRate: Int?
    /// Video-only — e.g. "Main", "High", "Main 10". Diagnostic only for now (see
    /// PlaybackEngineSelector.choose's log line) — not yet used to pick an engine, since
    /// which specific profile/bitDepth combination actually breaks AVPlayerLayer rendering
    /// isn't confirmed yet.
    public let profile: String?
    /// Video-only — 8, 10, or 12.
    public let bitDepth: Int?
    /// Video-only — e.g. 150 means Level 15.0.
    public let level: Double?
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

/// Mirrors Jellyfin's own three PlayMethod states — the server's dashboard distinguishes
/// these, so a client badge collapsing DirectStream and Transcode into one "Transcoding"
/// bucket disagrees with what the dashboard shows for the same session.
public enum JellyfinPlayMethod: String, Sendable {
    case directPlay = "Direct Play"
    case directStream = "Direct Stream"
    case transcode = "Transcoding"
}

public struct MediaVersion: Sendable, Identifiable, Equatable, Hashable {
    public let id: String
    public let name: String
}

public struct JellyfinPlaybackInfo: Sendable {
    public let mediaSourceId: String
    public let playURL: URL
    public let playMethod: JellyfinPlayMethod
    public let container: String?
    public let runTimeTicks: Int64?
    public let audioStreams: [JellyfinMediaStream]
    public let subtitleStreams: [JellyfinMediaStream]
    public let defaultAudioStreamIndex: Int?
    public let defaultSubtitleStreamIndex: Int?
    public let trickplay: JellyfinTrickplayInfo?
    public let videoStream: JellyfinMediaStream?
    /// Source's total bitrate (bits/sec), when the server reports it — used to keep a
    /// forced remux download close to source quality instead of Jellyfin's low default
    /// transcode bitrate when none is specified.
    public let bitrate: Int?
    /// Every version of the item (e.g. 4K and 1080p files merged into one title), in the
    /// server's order; one entry when there's only one.
    public let versions: [MediaVersion]

    public var isTranscoding: Bool { playMethod == .transcode }
    public var isDolbyVision: Bool { (videoStream?.videoRange ?? "").localizedCaseInsensitiveContains("dolby") }
    public var isHDR: Bool {
        isDolbyVision || (videoStream?.videoRange ?? "").localizedCaseInsensitiveContains("hdr")
    }
}

/// One row of GET /Sessions — a currently-connected client, playing or idle.
public struct JellyfinSession: Sendable, Identifiable, Equatable {
    public let id: String
    public let userName: String?
    public let deviceName: String
    public let clientName: String
    public let nowPlayingItemName: String?
    public let isPaused: Bool
    public let positionTicks: Int64?
    public let runTimeTicks: Int64?
    public let lastActivityDate: Date?
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
        mediaSourceId: String? = nil,
        quality: StreamQualityCap = .auto,
        audioStreamIndex: Int? = nil,
        subtitleStreamIndex: Int? = nil,
        forCast: Bool = false,
        nativeDecoder: Bool = false
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
            "DeviceProfile": forCast || !nativeDecoder
                ? Self.deviceProfile(forCast: forCast) : Self.nativeDecoderProfile,
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
        if let mediaSourceId { body["MediaSourceId"] = mediaSourceId }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.arcfin.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(PlaybackInfoResponse.self, from: data)
        guard let source = decoded.mediaSources.first(where: { $0.id == mediaSourceId }) ?? decoded.mediaSources.first
        else { throw URLError(.cannotParseResponse) }

        let playURL: URL
        let playMethod: JellyfinPlayMethod
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
            // "ContainerNotSupported" alone means every stream is already compatible and
            // only the container is being repackaged (a cheap remux, codecs untouched) —
            // that's Jellyfin's "Direct Stream", genuinely distinct from a real re-encode,
            // and its own dashboard doesn't label it "Transcoding" either.
            let reasons = Set(source.transcodeReasons ?? [])
            playMethod = (reasons.isEmpty || reasons == ["ContainerNotSupported"]) ? .directStream : .transcode
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
            playMethod = .directPlay
        }

        let streams = source.mediaStreams ?? []
        let audioStreams = streams.filter { $0.type == "Audio" }.map { $0.toStream() }
        let subtitleStreams = streams.filter { $0.type == "Subtitle" }.map { $0.toStream() }
        let videoStream = streams.first(where: { $0.type == "Video" })?.toStream()

        return JellyfinPlaybackInfo(
            mediaSourceId: source.id,
            playURL: playURL,
            playMethod: playMethod,
            container: source.container,
            runTimeTicks: source.runTimeTicks,
            audioStreams: audioStreams,
            subtitleStreams: subtitleStreams,
            defaultAudioStreamIndex: audioStreams.first(where: \.isDefault)?.index ?? audioStreams.first?.index,
            defaultSubtitleStreamIndex: subtitleStreams.first(where: \.isDefault)?.index,
            trickplay: source.trickplayInfo?.preferred(),
            videoStream: videoStream,
            bitrate: source.bitrate ?? videoStream?.bitRate,
            versions: decoded.mediaSources.map { MediaVersion(id: $0.id, name: $0.name ?? "Version") }
        )
    }

    // MARK: - Network bandwidth probe

    /// Streams up to `sizeBytes` from Jellyfin's bandwidth-test endpoint for at most
    /// `duration` and returns the throughput in bits per second, or nil if the probe failed.
    /// A 1 MB sample finished before the connection got up to speed and under-read fast
    /// links, so this reads a bigger sample but stops on time on a slow one. The first
    /// chunk is left out so the server's response latency doesn't count as slowness.
    public func testBitrate(
        credential: ServerCredential,
        authHeader: String,
        sizeBytes: Int = 10_000_000,
        duration: Duration = .seconds(4)
    ) async -> Int? {
        var comps = URLComponents(
            url: credential.baseURL.appendingPathComponent("Playback/BitrateTest"),
            resolvingAgainstBaseURL: false)!
        comps.queryItems = [.init(name: "size", value: "\(sizeBytes)")]
        var req = URLRequest(url: comps.url!)
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 8

        let probe = ThroughputProbe()
        let session = URLSession(configuration: URLSession.arcfin.configuration, delegate: probe, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        session.dataTask(with: req).resume()
        let deadline = ContinuousClock.now + duration
        while !probe.isFinished, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        return probe.bitsPerSecond
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
        _ = try? await URLSession.arcfin.data(for: req)
    }

    // MARK: - Intro/credits skip markers (community "Intro Skipper" plugin — optional)

    /// Intro, recap, credits and preview spans for an item, in seconds. Read from Jellyfin's
    /// Media Segments API (10.10+), which the Intro Skipper, Chapter Segments Provider and
    /// SkipMe.db plugins all publish to; servers with only an older Intro Skipper fall back to
    /// its own IntroTimestamps endpoint.
    public func getSkipSegments(credential: ServerCredential, authHeader: String, itemId: String) async -> SkipSegments {
        if let segments = await fetchMediaSegments(credential: credential, authHeader: authHeader, itemId: itemId),
           !segments.isEmpty {
            return segments
        }
        async let intro = fetchLegacySegment(credential: credential, authHeader: authHeader, itemId: itemId, kind: "Introduction")
        async let credits = fetchLegacySegment(credential: credential, authHeader: authHeader, itemId: itemId, kind: "Credits")
        return SkipSegments(intro: await intro, credits: await credits)
    }

    private func fetchMediaSegments(credential: ServerCredential, authHeader: String, itemId: String) async -> SkipSegments? {
        var comps = URLComponents(
            url: credential.baseURL.appendingPathComponent("MediaSegments/\(itemId)"),
            resolvingAgainstBaseURL: false)!
        comps.queryItems = [.init(name: "includeSegmentTypes", value: "Intro,Outro,Recap,Preview")]
        var req = URLRequest(url: comps.url!)
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 6
        guard let (data, resp) = try? await URLSession.arcfin.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let page = try? JSONDecoder().decode(MediaSegmentsPage.self, from: data)
        else { return nil }
        var result = SkipSegments()
        for segment in page.items {
            let span = Double(segment.startTicks) / 10_000_000 ... Double(max(segment.endTicks, segment.startTicks)) / 10_000_000
            // A provider can report more than one of a kind; the first one is the one to skip.
            switch segment.type {
            case "Intro": result.intro = result.intro ?? span
            case "Recap": result.recap = result.recap ?? span
            case "Outro": result.credits = result.credits ?? span
            case "Preview": result.preview = result.preview ?? span
            default: break
            }
        }
        return result
    }

    private func fetchLegacySegment(credential: ServerCredential, authHeader: String, itemId: String, kind: String) async -> ClosedRange<Double>? {
        var req = URLRequest(url: credential.baseURL.appendingPathComponent("Episode/\(itemId)/IntroTimestamps/\(kind)"))
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 6
        guard let (data, resp) = try? await URLSession.arcfin.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let segment = try? JSONDecoder().decode(LegacySegment.self, from: data),
              segment.valid != false, let end = segment.end, end > 0
        else { return nil }
        return min(segment.start ?? 0, end)...end
    }

    // MARK: - Active sessions (admin)

    /// GET /Sessions — every active session server-wide, not just this user's. Jellyfin
    /// itself returns 403 for a non-admin caller, which callers should treat the same as
    /// an empty result (the Admin Sessions screen is only reachable for admins anyway,
    /// but a token that stops being admin mid-session shouldn't crash, just show nothing).
    public func getActiveSessions(credential: ServerCredential, authHeader: String) async throws -> [JellyfinSession] {
        var req = URLRequest(url: credential.baseURL.appendingPathComponent("Sessions"))
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 10
        let (data, resp) = try await URLSession.arcfin.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode([SessionResponse].self, from: data).map { $0.toSession() }
    }

    // MARK: - Device profile

    /// For engines that demux and decode on the device (Aether's FFmpeg + VideoToolbox, VLC):
    /// any container and codec plays as is, so the server only steps in when the bitrate
    /// cap forces a transcode, and image subtitles stay in the file for the engine to draw.
    private static var nativeDecoderProfile: [String: Any] { [
        "MaxStreamingBitrate": 120_000_000,
        "DirectPlayProfiles": [
            ["Container": "mkv,webm,mp4,m4v,mov,avi,ts,m2ts,mpegts,mts,wmv,asf,flv,ogg,ogv,3gp,mpg,mpeg,vob",
             "Type": "Video"],
        ],
        "TranscodingProfiles": [
            [
                "Container": "mp4", "Type": "Video", "AudioCodec": "aac,ac3,eac3",
                "VideoCodec": "hevc,h264", "Context": "Streaming", "Protocol": "hls",
                "MaxAudioChannels": "8", "MinSegments": "2", "BreakOnNonKeyFrames": true,
            ],
        ],
        "SubtitleProfiles": [
            ["Format": "vtt", "Method": "External"],
            ["Format": "pgssub", "Method": "Embed"],
            ["Format": "dvdsub", "Method": "Embed"],
            ["Format": "dvbsub", "Method": "Embed"],
        ],
    ] }

    /// Two escape hatches for device-specific codec issues, surfaced as user-facing toggles
    /// in CodecProfileSettingsView (Settings > Playback > Codec Compatibility) rather than
    /// hardcoded — a struct, not a View, so read straight from UserDefaults like the rest
    /// of the playback code's own settings reads (skipIntro/autoPlayNext etc.) already do.
    private static func deviceProfile(forCast: Bool) -> [String: Any] {
        let allowHEVC = (UserDefaults.standard.object(forKey: "codecAllowHEVCDirectPlay") as? Bool) ?? true
        let allowSurroundAudio = UserDefaults.standard.bool(forKey: "codecAllowSurroundAudioDirectPlay")
        let videoCodecs = allowHEVC ? "h264,hevc" : "h264"
        // AudioCodec lists are deliberately narrow by default: AVFoundation can't reliably
        // decode ac3/eac3/dts to the built-in speaker/headphones on-device (only passthrough
        // to a compatible receiver, which isn't guaranteed) — claiming them as direct-play
        // compatible produced video with silent audio. Anything else gets remuxed with
        // audio transcoded to AAC while video stays copied, via the profiles below.
        var mp4AudioCodecs = "aac,mp3,alac,flac" + (allowSurroundAudio ? ",ac3,eac3,dts" : "")
        var movAudioCodecs = "aac,mp3,alac" + (allowSurroundAudio ? ",ac3,eac3,dts" : "")
        if forCast {
            // The Default Media Receiver decodes on the Chromecast itself, not through
            // AVFoundation: it handles ac3/eac3 but not alac/flac-in-mp4 or dts, so those get
            // transcoded to AAC regardless of the on-device surround toggle.
            mp4AudioCodecs = "aac,mp3,ac3,eac3"
            movAudioCodecs = mp4AudioCodecs
        }
        return [
        "MaxStreamingBitrate": 120_000_000,
        // mkv is deliberately absent — AVFoundation's native Matroska support is
        // unreliable even for codec-compatible files (routinely "Cannot Open" on
        // real-world encodes), so mkv sources always remux into HLS below instead.
        "DirectPlayProfiles": [
            ["Container": "mp4,m4v", "Type": "Video", "VideoCodec": videoCodecs, "AudioCodec": mp4AudioCodecs],
            ["Container": "mov", "Type": "Video", "VideoCodec": videoCodecs, "AudioCodec": movAudioCodecs],
        ],
        // HLS can only carry HEVC in fMP4 segments, and with h264 as the only output an HEVC
        // source in mkv was re-encoded in full instead of just repackaged. The Chromecast
        // receiver keeps the h264-in-ts output it's known to play.
        "TranscodingProfiles": [
            forCast ? [
                "Container": "ts", "Type": "Video", "AudioCodec": "aac",
                "VideoCodec": "h264", "Context": "Streaming", "Protocol": "hls",
                "MaxAudioChannels": "6", "MinSegments": "2", "BreakOnNonKeyFrames": true,
            ] : [
                "Container": "mp4", "Type": "Video", "AudioCodec": "aac",
                "VideoCodec": videoCodecs, "Context": "Streaming", "Protocol": "hls",
                "MaxAudioChannels": "6", "MinSegments": "2", "BreakOnNonKeyFrames": true,
            ],
        ],
        "CodecProfiles": [
            ["Type": "Video", "Codec": "h264",
             "Conditions": [["Condition": "LessThanEqual", "Property": "VideoBitDepth", "Value": "8"]]],
            // AVFoundation requires the HEVC FourCC tag to be hvc1, not hev1 (Apple's own
            // documented requirement) — a source tagged hev1 plays audio with a black video
            // screen, which is exactly the failure mode chased through most of this session.
            // IsRequired: false so a correctly-tagged hevc source isn't forced through an
            // unnecessary transcode; it still guides the tag Jellyfin writes when transcoding.
            ["Type": "Video", "Codec": "hevc",
             "Conditions": [["Condition": "EqualsAny", "Property": "VideoCodecTag", "Value": "hvc1", "IsRequired": false]]],
        ],
        // vtt only — the client parses/renders subtitles itself (see SubtitleLoader), so a
        // single consistent, easily-parsed format is preferable to juggling srt/ass too.
        // Jellyfin converts any source subtitle format to vtt on request.
        //
        // Image-based subtitle formats (Blu-ray/DVD/DVB) have no text to extract, so they
        // can never be satisfied by an External vtt profile — without a matching profile,
        // Jellyfin just can't deliver them and SubtitleLoader gets no deliveryUrl at all,
        // silently showing nothing. Encode tells Jellyfin to burn these into the transcoded
        // video instead; SubtitleLoader's existing "no deliveryUrl -> no overlay cues" path
        // already does the right thing here, since the text is now in the video itself.
        "SubtitleProfiles": [
            ["Format": "vtt", "Method": "External"],
            ["Format": "pgssub", "Method": "Encode"],
            ["Format": "dvdsub", "Method": "Encode"],
            ["Format": "dvbsub", "Method": "Encode"],
        ],
    ] }
}

// MARK: - Private response decoders

private struct SessionResponse: Decodable {
    struct NowPlayingItem: Decodable {
        let name: String?
        let runTimeTicks: Int64?
        enum CodingKeys: String, CodingKey {
            case name = "Name"
            case runTimeTicks = "RunTimeTicks"
        }
    }
    struct PlayState: Decodable {
        let isPaused: Bool?
        let positionTicks: Int64?
        enum CodingKeys: String, CodingKey {
            case isPaused = "IsPaused"
            case positionTicks = "PositionTicks"
        }
    }
    let id: String
    let userName: String?
    let deviceName: String?
    let client: String?
    let nowPlayingItem: NowPlayingItem?
    let playState: PlayState?
    // Decoded as a raw string, not Date — Jellyfin's timestamp format (fractional-second
    // ISO 8601) doesn't match JSONDecoder's default .deferredToDate strategy, and a single
    // unparseable field on one session shouldn't fail decoding the whole session list.
    let lastActivityDate: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case userName = "UserName"
        case deviceName = "DeviceName"
        case client = "Client"
        case nowPlayingItem = "NowPlayingItem"
        case playState = "PlayState"
        case lastActivityDate = "LastActivityDate"
    }

    func toSession() -> JellyfinSession {
        // Created fresh per call rather than cached statically — this only ever runs over
        // a short Sessions list (not a hot path), and ISO8601DateFormatter isn't Sendable,
        // so a shared static instance would need extra ceremony for no real benefit here.
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plainFormatter = ISO8601DateFormatter()
        let parsedDate = lastActivityDate.flatMap {
            fractionalFormatter.date(from: $0) ?? plainFormatter.date(from: $0)
        }
        return JellyfinSession(
            id: id, userName: userName, deviceName: deviceName ?? "Unknown Device",
            clientName: client ?? "Unknown Client",
            nowPlayingItemName: nowPlayingItem?.name,
            isPaused: playState?.isPaused ?? false,
            positionTicks: playState?.positionTicks,
            runTimeTicks: nowPlayingItem?.runTimeTicks,
            lastActivityDate: parsedDate
        )
    }
}

private struct PlaybackInfoResponse: Decodable {
    let mediaSources: [MediaSourceResponse]
    enum CodingKeys: String, CodingKey { case mediaSources = "MediaSources" }
}

private struct MediaSourceResponse: Decodable {
    let id: String
    let container: String?
    let runTimeTicks: Int64?
    let transcodingUrl: String?
    let transcodeReasons: [String]?
    let mediaStreams: [MediaStreamStreamResponse]?
    let trickplayInfo: [String: TrickplayResponse]?
    let bitrate: Int?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case id = "Id", name = "Name", container = "Container", runTimeTicks = "RunTimeTicks"
        case transcodingUrl = "TranscodingUrl", transcodeReasons = "TranscodeReasons"
        case mediaStreams = "MediaStreams"
        case trickplayInfo = "TrickplayInfo"
        case bitrate = "Bitrate"
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
    let width: Int?
    let height: Int?
    let videoRange: String?
    let bitRate: Int?
    let profile: String?
    let bitDepth: Int?
    let level: Double?

    enum CodingKeys: String, CodingKey {
        case index = "Index", type = "Type", codec = "Codec", language = "Language"
        case displayTitle = "DisplayTitle", isDefault = "IsDefault"
        case isForced = "IsForced", isExternal = "IsExternal"
        case deliveryUrl = "DeliveryUrl"
        case width = "Width", height = "Height", videoRange = "VideoRange"
        case bitRate = "BitRate"
        case profile = "Profile", bitDepth = "BitDepth", level = "Level"
    }

    func toStream() -> JellyfinMediaStream {
        JellyfinMediaStream(
            index: index, type: type, codec: codec, language: language,
            displayTitle: displayTitle, isDefault: isDefault ?? false,
            isForced: isForced ?? false, isExternal: isExternal ?? false,
            deliveryUrl: deliveryUrl, width: width, height: height, videoRange: videoRange,
            bitRate: bitRate, profile: profile, bitDepth: bitDepth, level: level
        )
    }
}

public struct SkipSegments: Sendable, Equatable {
    public var intro: ClosedRange<Double>?
    public var recap: ClosedRange<Double>?
    public var credits: ClosedRange<Double>?
    /// A "next time on" preview, usually after the credits.
    public var preview: ClosedRange<Double>?

    public init(intro: ClosedRange<Double>? = nil, recap: ClosedRange<Double>? = nil,
                credits: ClosedRange<Double>? = nil, preview: ClosedRange<Double>? = nil) {
        self.intro = intro; self.recap = recap; self.credits = credits; self.preview = preview
    }

    public var isEmpty: Bool { intro == nil && recap == nil && credits == nil && preview == nil }
}

private struct MediaSegmentsPage: Decodable {
    struct Segment: Decodable {
        let type: String
        let startTicks: Int64
        let endTicks: Int64
        enum CodingKeys: String, CodingKey { case type = "Type", startTicks = "StartTicks", endTicks = "EndTicks" }
    }
    let items: [Segment]
    enum CodingKeys: String, CodingKey { case items = "Items" }
}

/// The older Intro Skipper response: `IntroStart`/`IntroEnd` (seconds) for whichever kind
/// was asked for, with `Valid` false when nothing was detected.
private struct LegacySegment: Decodable {
    let start: Double?
    let end: Double?
    let valid: Bool?
    enum CodingKeys: String, CodingKey { case start = "IntroStart", end = "IntroEnd", valid = "Valid" }
}

private final class ThroughputProbe: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var failed = false
    private var finished = false
    private var firstChunkAt: Date?
    private var lastChunkAt: Date?
    private var bytesAfterFirstChunk = 0

    var isFinished: Bool { lock.withLock { finished } }

    var bitsPerSecond: Int? {
        lock.withLock {
            guard !failed, let firstChunkAt, let lastChunkAt, bytesAfterFirstChunk > 0 else { return nil }
            let elapsed = lastChunkAt.timeIntervalSince(firstChunkAt)
            guard elapsed > 0.05 else { return nil }
            return Int(Double(bytesAfterFirstChunk) * 8 / elapsed)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse) async -> URLSession.ResponseDisposition {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            lock.withLock { failed = true; finished = true }
            return .cancel
        }
        return .allow
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let now = Date()
        lock.withLock {
            if firstChunkAt == nil {
                firstChunkAt = now
            } else {
                bytesAfterFirstChunk += data.count
            }
            lastChunkAt = now
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.withLock { finished = true }
    }
}
