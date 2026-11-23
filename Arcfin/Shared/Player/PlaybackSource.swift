// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import JellyfinAPI
import MediaEngine

/// What the player can offer beyond the picture and sound. The server has it all; a download
/// or a picked file plays on this device alone, so none of it applies there.
struct PlaybackCapabilities: Equatable {
    var quality: Bool
    var versions: Bool
    var syncPlay: Bool
    var sharePlay: Bool
    var casting: Bool
    var subtitleSearch: Bool
    var moreLikeThis: Bool
    var rating: Bool
    var personPages: Bool
    /// The web app's and the dashboard's view of this session follows what's played.
    var serverRemoteControl: Bool
    var newWindow: Bool
    var externalPlayer: Bool

    static let server = PlaybackCapabilities(
        quality: true, versions: true, syncPlay: true, sharePlay: true, casting: true, subtitleSearch: true,
        moreLikeThis: true, rating: true, personPages: true, serverRemoteControl: true, newWindow: true, externalPlayer: true)
    static let local = PlaybackCapabilities(
        quality: false, versions: false, syncPlay: false, sharePlay: false, casting: false, subtitleSearch: false,
        moreLikeThis: false, rating: false, personPages: false, serverRemoteControl: false, newWindow: false, externalPlayer: false)
}

/// The tracks and quality a stream is asked for with.
struct PlaybackInfoRequest {
    var mediaSourceId: String?
    var quality: StreamQualityCap
    var audioStreamIndex: Int?
    var subtitleStreamIndex: Int?
    var forCast = false
    var nativeDecoder = false
}

/// The title's page details the player uses: previews, chapters, cast, rating and genres.
struct PlaybackDetails {
    var trickplay: TrickplayLoader?
    var chapters: [MediaChapter] = []
    var castMembers: [MediaPerson] = []
    var likes: Bool?
    /// The title's own, or its show's when an episode has none.
    var genres: [String] = []
}

/// Where the player's video, tracks and details come from, and where what's watched goes.
@MainActor
protocol PlaybackSource: AnyObject {
    var capabilities: PlaybackCapabilities { get }
    /// Plays from this device, with nothing asked of a server.
    var isLocal: Bool { get }
    /// The engine to open the stream with, for Settings › Playback › Playback Engine.
    func engine(for preference: PlaybackEngineKind) -> PlaybackEngineKind
    /// The list of tracks is the engine's own, read once the file is open, so a track's index is
    /// the engine's id for it.
    var tracksComeFromEngine: Bool { get }
    func attach(authManager: AuthManager, mediaRepo: MediaRepository)
    /// Why nothing can play, checked before anything loads.
    var unavailableMessage: String? { get }
    /// The resume point when it has to be looked up first; nil keeps the one the player opened with.
    /// `decided` is an explicit start position that When Resuming doesn't ask about again.
    func startPosition() async -> (ticks: Int64, decided: Bool)?
    func playbackInfo(for item: MediaItem, _ request: PlaybackInfoRequest) async throws -> JellyfinPlaybackInfo
    /// The engine's tracks once a load has opened the file, for a source that lists those.
    func tracksLoaded(on player: any MediaPlayerProtocol, info: JellyfinPlaybackInfo) async -> JellyfinPlaybackInfo?
    func details(for item: MediaItem, info: JellyfinPlaybackInfo, includesItemDetail: Bool) async -> PlaybackDetails
    /// Where a subtitle drawn over the video is read from; nil when it isn't drawn here.
    func subtitleLocation(for stream: JellyfinMediaStream, in info: JellyfinPlaybackInfo, item: MediaItem) -> String?
    func subtitleCues(at location: String) async -> [SubtitleCue]
    /// The engine draws this track itself, from inside the file.
    func drawsSubtitleInEngine(_ stream: JellyfinMediaStream) -> Bool
    func skipSegments(for item: MediaItem) async -> SkipSegments
    func neighbours(of item: MediaItem) async -> (next: MediaItem?, previous: MediaItem?)
    func similarItems(to item: MediaItem) async -> [MediaItem]
    func artwork(for item: MediaItem) async -> PlatformImage?
    /// A poster on this device for a title the player shows, such as the one up next.
    func localImageURL(for itemId: String) -> URL?
    func playbackStarted(item: MediaItem, info: JellyfinPlaybackInfo, positionTicks: Int64) async
    func positionChanged(ticks: Int64, durationTicks: Int64, status: PlaybackStatus)
    func reportProgress(_ progress: PlaybackProgressReport) async
    func playbackStopped(_ stop: PlaybackStopReport) async
    func playbackFinished(item: MediaItem, positionTicks: Int64, durationTicks: Int64) async
    /// The engine to try when Aether can't open the stream.
    func fallbackEngine(for info: JellyfinPlaybackInfo) -> any MediaPlayerProtocol
    /// The player has closed and its engine has stopped.
    func playerClosed()
}

extension PlaybackSource {
    var isLocal: Bool { false }
    func engine(for preference: PlaybackEngineKind) -> PlaybackEngineKind {
        PlaybackEngineSelector.choose(preference: preference, container: nil, videoStream: nil)
    }
    var tracksComeFromEngine: Bool { false }
    func attach(authManager: AuthManager, mediaRepo: MediaRepository) {}
    func startPosition() async -> (ticks: Int64, decided: Bool)? { nil }
    func tracksLoaded(on player: any MediaPlayerProtocol, info: JellyfinPlaybackInfo) async -> JellyfinPlaybackInfo? { nil }
    func drawsSubtitleInEngine(_ stream: JellyfinMediaStream) -> Bool { false }
    func similarItems(to item: MediaItem) async -> [MediaItem] { [] }
    func localImageURL(for itemId: String) -> URL? { nil }
    func positionChanged(ticks: Int64, durationTicks: Int64, status: PlaybackStatus) {}
    func playerClosed() {}
}

struct PlaybackProgressReport {
    let item: MediaItem
    let mediaSourceId: String
    let positionTicks: Int64
    let durationTicks: Int64
    let isPaused: Bool
    let liveStreamId: String?
    let volumeLevel: Int
    let isMuted: Bool
    let playSessionId: String?
    let playMethod: JellyfinPlayMethod
}

struct PlaybackStopReport {
    let item: MediaItem
    let info: JellyfinPlaybackInfo
    let positionTicks: Int64
    let durationTicks: Int64
    let creditsStart: Double?
    let isLive: Bool
    /// Another title took over the player, such as the next episode.
    let handedOver: Bool
}

// MARK: - The server

/// Streams from the signed-in profile's server, and reports to it.
@MainActor
final class ServerPlaybackSource: PlaybackSource {
    private let client = JellyfinMediaClient()
    private var authManager: AuthManager?
    private var mediaRepo: MediaRepository?

    var capabilities: PlaybackCapabilities { .server }

    func attach(authManager: AuthManager, mediaRepo: MediaRepository) {
        self.authManager = authManager
        self.mediaRepo = mediaRepo
    }

    private var credential: ServerCredential? { authManager?.state.credential }
    private var authHeader: String? {
        guard let authManager, let credential else { return nil }
        return authManager.authClient.authHeader(token: credential.accessToken)
    }

    var unavailableMessage: String? {
        credential != nil && authHeader != nil ? nil : String(localized: "Not signed in.")
    }

    func playbackInfo(for item: MediaItem, _ request: PlaybackInfoRequest) async throws -> JellyfinPlaybackInfo {
        guard let credential, let authHeader else { throw URLError(.userAuthenticationRequired) }
        return try await client.getPlaybackInfo(
            credential: credential, authHeader: authHeader, itemId: item.id, mediaSourceId: request.mediaSourceId,
            quality: request.quality, audioStreamIndex: request.audioStreamIndex,
            subtitleStreamIndex: request.subtitleStreamIndex, forCast: request.forCast, nativeDecoder: request.nativeDecoder
        )
    }

    func details(for item: MediaItem, info: JellyfinPlaybackInfo, includesItemDetail: Bool) async -> PlaybackDetails {
        guard let credential, let authHeader else { return PlaybackDetails(genres: item.genres) }
        // PlaybackInfo's own TrickplayInfo field isn't reliably populated by Jellyfin —
        // the general item-detail endpoint's Trickplay field (keyed by MediaSourceId) is
        // what the official apps actually read it from.
        let detail = includesItemDetail ? try? await client.getItemDetail(credential: credential, authHeader: authHeader, itemId: item.id) : nil
        var details = PlaybackDetails()
        if let trickplay = detail?.trickplay[info.mediaSourceId] ?? info.trickplay {
            details.trickplay = TrickplayLoader(credential: credential, authHeader: authHeader, client: client, itemId: item.id, info: trickplay)
        }
        details.chapters = detail?.chapters ?? []
        details.castMembers = detail?.cast ?? []
        details.likes = detail?.item.userData?.likes
        // An episode rarely carries genres of its own, so its show's are read when it has none.
        var genres = detail?.genres ?? item.genres
        if genres.isEmpty, let seriesId = item.seriesId,
           let series = try? await client.getItemDetail(credential: credential, authHeader: authHeader, itemId: seriesId) {
            genres = series.genres
        }
        details.genres = genres
        return details
    }

    /// Where to fetch a text subtitle as WebVTT. The server's own link when it gives one; a
    /// text track inside a file played as is can come without one, and the server converts
    /// it from the same address all the same. Never for a conversion, which may burn it in.
    func subtitleLocation(for stream: JellyfinMediaStream, in info: JellyfinPlaybackInfo, item: MediaItem) -> String? {
        if let deliveryUrl = stream.deliveryUrl { return deliveryUrl }
        let textCodecs: Set<String> = ["subrip", "srt", "ass", "ssa", "webvtt", "vtt", "mov_text", "text", "ttml"]
        guard info.playMethod != .transcode, textCodecs.contains(stream.codec?.lowercased() ?? "") else { return nil }
        return "/Videos/\(item.id)/\(info.mediaSourceId)/Subtitles/\(stream.index)/0/Stream.vtt"
    }

    func subtitleCues(at location: String) async -> [SubtitleCue] {
        guard let credential else { return [] }
        return await SubtitleLoader.loadCues(deliveryUrl: location, credential: credential)
    }

    func skipSegments(for item: MediaItem) async -> SkipSegments {
        guard let credential, let authHeader else { return SkipSegments() }
        return await client.getSkipSegments(credential: credential, authHeader: authHeader, itemId: item.id)
    }

    /// A playlist or collection playing through goes by its own order; an episode by the
    /// series' order. Next Up wasn't usable here: part-way through an episode it answers
    /// with that same episode.
    func neighbours(of item: MediaItem) async -> (next: MediaItem?, previous: MediaItem?) {
        if PlayQueue.contains(item.id) {
            return (PlayQueue.item(after: item.id), PlayQueue.item(before: item.id))
        }
        guard let credential, let authHeader, item.type == .episode, let seriesId = item.seriesId,
              let episodes = try? await client.getEpisodes(
                credential: credential, authHeader: authHeader, seriesId: seriesId, seasonId: nil)
        else { return (nil, nil) }
        // Specials sit outside the run of the show unless one is what's playing.
        let run = item.parentIndexNumber == 0 ? episodes : episodes.filter { $0.parentIndexNumber != 0 }
        guard let index = run.firstIndex(where: { $0.id == item.id }) else { return (nil, nil) }
        return (run.indices.contains(index + 1) ? run[index + 1] : nil, index > 0 ? run[index - 1] : nil)
    }

    func similarItems(to item: MediaItem) async -> [MediaItem] {
        guard let credential, let authHeader else { return [] }
        return ((try? await client.getSimilarItems(credential: credential, authHeader: authHeader, itemId: item.id, limit: 12)) ?? [])
            .filter { $0.id != item.id }
    }

    func artwork(for item: MediaItem) async -> PlatformImage? {
        guard let url = mediaRepo?.imageURL(for: item, type: .primary, fillWidth: 600),
              let data = await URLSession.arcfin.imageData(from: url)
        else { return nil }
        return PlatformImage(data: data)
    }

    func playbackStarted(item: MediaItem, info: JellyfinPlaybackInfo, positionTicks: Int64) async {
        guard let credential, let authHeader else { return }
        await client.reportPlaybackStart(credential: credential, authHeader: authHeader,
                                         itemId: item.id, mediaSourceId: info.mediaSourceId,
                                         positionTicks: positionTicks, liveStreamId: info.liveStreamId,
                                         playSessionId: info.playSessionId, playMethod: info.playMethod)
    }

    func reportProgress(_ progress: PlaybackProgressReport) async {
        guard let credential, let authHeader else { return }
        await client.reportPlaybackProgress(
            credential: credential, authHeader: authHeader, itemId: progress.item.id,
            mediaSourceId: progress.mediaSourceId, positionTicks: progress.positionTicks,
            isPaused: progress.isPaused, liveStreamId: progress.liveStreamId,
            volumeLevel: progress.volumeLevel, isMuted: progress.isMuted,
            playSessionId: progress.playSessionId, playMethod: progress.playMethod
        )
    }

    func playbackStopped(_ stop: PlaybackStopReport) async {
        guard let credential, let authHeader else { return }
        let info = stop.info
        await client.reportPlaybackStopped(credential: credential, authHeader: authHeader,
                                           itemId: stop.item.id, mediaSourceId: info.mediaSourceId,
                                           positionTicks: stop.positionTicks, liveStreamId: info.liveStreamId,
                                           playSessionId: info.playSessionId, playMethod: info.playMethod)
        if let liveStreamId = info.liveStreamId {
            await client.closeLiveStream(credential: credential, authHeader: authHeader, liveStreamId: liveStreamId)
        }
        if !stop.isLive, WatchedThreshold.current.isReached(seconds: Double(stop.positionTicks) / 10_000_000,
                                                           duration: Double(stop.durationTicks) / 10_000_000,
                                                           creditsStart: stop.creditsStart) {
            _ = try? await client.markWatched(credential: credential, authHeader: authHeader, itemId: stop.item.id, watched: true)
        }
        NotificationCenter.default.post(name: .arcfinPlaybackReported, object: nil)
    }

    func playbackFinished(item: MediaItem, positionTicks: Int64, durationTicks: Int64) async {
        guard let credential, let authHeader else { return }
        _ = try? await client.markWatched(credential: credential, authHeader: authHeader, itemId: item.id, watched: true)
    }

    /// The AVFoundation/VLC split Auto used before Aether existed — now only reached when
    /// Aether itself fails to construct or load a source (see setup()'s runtime fallback).
    func fallbackEngine(for info: JellyfinPlaybackInfo) -> any MediaPlayerProtocol {
        switch PlaybackEngineSelector.legacyFallback(container: info.container, videoStream: info.videoStream) {
        case .vlc: return VLCEnginePlayer()
        default: return AVFoundationPlayer()
        }
    }
}
