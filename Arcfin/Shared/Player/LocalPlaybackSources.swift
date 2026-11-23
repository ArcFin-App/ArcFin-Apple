// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import SwiftData
import AuthCore
import JellyfinAPI
import MediaEngine
import Persistence
import SyncEngine

// MARK: - Tracks from the engine

/// A file on this device carries its own tracks, and the engine is the one that knows which are
/// really there (a download converted to a smaller size keeps only some of the original's). The
/// player lists the engine's tracks, named from the server's saved details where they match.
enum LocalTracks {
    /// `saved` are the streams the server listed for the original file; `sidecars` the
    /// subtitles saved beside it. A saved stream describes an engine track when they share an
    /// index, which holds for Aether on the original file (both number by stream index).
    static func streams(saved: [JellyfinMediaStream], sidecars: [JellyfinMediaStream],
                        engineAudio: [AudioTrack], engineSubtitles: [SubtitleTrack])
        -> (audio: [JellyfinMediaStream], subtitles: [JellyfinMediaStream]) {
        let savedAudio = Dictionary(saved.filter { $0.type == "Audio" }.map { ($0.index, $0) }, uniquingKeysWith: { first, _ in first })
        let savedSubtitles = Dictionary(saved.filter { $0.type == "Subtitle" && !$0.isExternal }.map { ($0.index, $0) },
                                        uniquingKeysWith: { first, _ in first })
        let audio = engineAudio.map { track in
            savedAudio[track.id] ?? JellyfinMediaStream(
                index: track.id, type: "Audio", language: track.language, displayTitle: track.displayName)
        }
        let taken = Set(sidecars.map(\.index))
        let embedded = engineSubtitles.filter { !$0.isExternal && !taken.contains($0.id) }.map { track in
            savedSubtitles[track.id] ?? JellyfinMediaStream(
                index: track.id, type: "Subtitle", language: track.language, displayTitle: track.displayName)
        }
        return (audio, embedded + sidecars)
    }

    /// The index a subtitle was saved under, from its `sub-<index>.vtt` file name.
    static func sidecarIndex(fileName: String) -> Int? {
        guard fileName.hasPrefix("sub-"), fileName.hasSuffix(".vtt") else { return nil }
        return Int(fileName.dropFirst(4).dropLast(4))
    }
}

extension JellyfinPlaybackInfo {
    /// A file played as it is from this device.
    static func local(url: URL, container: String?, runTimeTicks: Int64?, audio: [JellyfinMediaStream],
                      subtitles: [JellyfinMediaStream], video: JellyfinMediaStream?, defaultAudio: Int? = nil) -> JellyfinPlaybackInfo {
        JellyfinPlaybackInfo(
            mediaSourceId: "local", playURL: url, playMethod: .directPlay, container: container, runTimeTicks: runTimeTicks,
            audioStreams: audio, subtitleStreams: subtitles,
            defaultAudioStreamIndex: defaultAudio ?? audio.first(where: \.isDefault)?.index ?? audio.first?.index,
            defaultSubtitleStreamIndex: subtitles.first(where: \.isDefault)?.index,
            trickplay: nil, videoStream: video ?? JellyfinMediaStream(index: -1, type: "Video"),
            bitrate: nil, versions: [])
    }
}

/// Engine tracks list a moment after the file opens.
@MainActor
private func waitForEngineTracks(_ player: any MediaPlayerProtocol) async {
    for _ in 0..<20 where player.availableAudioTracks.isEmpty {
        try? await Task.sleep(for: .milliseconds(100))
    }
}

// MARK: - A picked file

/// A video picked from Files: nothing about it is known beyond what the engine finds inside.
@MainActor
final class FilePlaybackSource: PlaybackSource {
    let url: URL
    let item: MediaItem
    private var isAccessing = false

    init(url: URL) {
        self.url = url
        item = MediaItem(id: "file:\(url.path)", name: url.deletingPathExtension().lastPathComponent, type: .unknown)
    }

    var capabilities: PlaybackCapabilities { .local }
    var isLocal: Bool { true }
    /// AVFoundation can't open most files' containers, so a file stays on Aether unless VLC is picked.
    func engine(for preference: PlaybackEngineKind) -> PlaybackEngineKind { preference == .vlc ? .vlc : .aether }
    var tracksComeFromEngine: Bool { true }
    var unavailableMessage: String? { nil }

    func playbackInfo(for item: MediaItem, _ request: PlaybackInfoRequest) async throws -> JellyfinPlaybackInfo {
        // Paired with the stop once the engine has let go of the file (playerClosed).
        if !isAccessing { isAccessing = url.startAccessingSecurityScopedResource() }
        return .local(url: url, container: url.pathExtension.lowercased(), runTimeTicks: nil, audio: [], subtitles: [], video: nil)
    }

    func tracksLoaded(on player: any MediaPlayerProtocol, info: JellyfinPlaybackInfo) async -> JellyfinPlaybackInfo? {
        await waitForEngineTracks(player)
        let tracks = LocalTracks.streams(saved: [], sidecars: [], engineAudio: player.availableAudioTracks,
                                         engineSubtitles: player.availableSubtitleTracks)
        return .local(url: url, container: info.container, runTimeTicks: nil, audio: tracks.audio, subtitles: tracks.subtitles,
                      video: nil, defaultAudio: tracks.audio.isEmpty ? nil : player.selectedAudioTrackIndex)
    }

    func details(for item: MediaItem, info: JellyfinPlaybackInfo, includesItemDetail: Bool) async -> PlaybackDetails { PlaybackDetails() }
    func subtitleLocation(for stream: JellyfinMediaStream, in info: JellyfinPlaybackInfo, item: MediaItem) -> String? { nil }
    func subtitleCues(at location: String) async -> [SubtitleCue] { [] }
    func drawsSubtitleInEngine(_ stream: JellyfinMediaStream) -> Bool { true }
    func skipSegments(for item: MediaItem) async -> SkipSegments { SkipSegments() }
    func neighbours(of item: MediaItem) async -> (next: MediaItem?, previous: MediaItem?) { (nil, nil) }
    func artwork(for item: MediaItem) async -> PlatformImage? { nil }
    func playbackStarted(item: MediaItem, info: JellyfinPlaybackInfo, positionTicks: Int64) async {}
    func reportProgress(_ progress: PlaybackProgressReport) async {}
    func playbackStopped(_ stop: PlaybackStopReport) async {}
    func playbackFinished(item: MediaItem, positionTicks: Int64, durationTicks: Int64) async {}
    func fallbackEngine(for info: JellyfinPlaybackInfo) -> any MediaPlayerProtocol { VLCEnginePlayer() }

    func playerClosed() {
        guard isAccessing else { return }
        isAccessing = false
        url.stopAccessingSecurityScopedResource()
    }
}

// MARK: - A download

/// The download's video file isn't where it was saved.
struct DownloadFileMissing: Error {}

/// A downloaded title: its file, the details saved with it, and its position kept here and
/// handed to its own profile's server once it can be reached.
@MainActor
final class DownloadPlaybackSource: PlaybackSource {
    let downloadedItem: DownloadedItem
    let item: MediaItem
    private let startPositionOverride: Int64?
    private var authManager: AuthManager?
    /// The page as the server sent it when this was downloaded; older downloads may have none.
    /// Read off the main thread when the player first asks for the stream, not when the view is made.
    private var savedDetailData: Data?
    private var savedStreams: (container: String?, streams: [JellyfinMediaStream])?
    private var savedDetailsLoad: Task<Void, Never>?
    /// The other downloaded episodes the player can move on to, by id.
    private var episodes: [String: DownloadedItem] = [:]
    /// Playing with a position: until then the player's position is 0, and saving it would
    /// send that to the server as a newer resume point.
    private(set) var hasStarted = false
    /// Reached Mark as Watched's point in this playback, for Delete After Watching.
    private var finishedHere = false

    init(downloadedItem: DownloadedItem, startPositionOverride: Int64? = nil) {
        self.downloadedItem = downloadedItem
        self.startPositionOverride = startPositionOverride
        item = Self.mediaItem(for: downloadedItem)
    }

    private func loadSavedDetails() async {
        if savedDetailsLoad == nil {
            let file = directory.appendingPathComponent("detail.json")
            savedDetailsLoad = Task {
                let saved = await Task.detached(priority: .userInitiated) {
                    let data = try? Data(contentsOf: file)
                    return (data: data, streams: data.flatMap(JellyfinMediaStream.savedStreams(fromItemDetail:)))
                }.value
                savedDetailData = saved.data
                savedStreams = saved.streams
            }
        }
        await savedDetailsLoad?.value
    }

    static func mediaItem(for download: DownloadedItem) -> MediaItem {
        MediaItem(id: download.itemId, name: download.name, overview: download.overview,
                  type: MediaType(rawValue: download.typeRaw) ?? .unknown,
                  productionYear: download.productionYear, communityRating: download.communityRating,
                  seriesName: download.seriesName, indexNumber: download.episodeNumber,
                  parentIndexNumber: download.seasonNumber, seriesId: download.seriesId,
                  runTimeTicks: download.runtimeTicks > 0 ? download.runtimeTicks : nil, genres: download.genres)
    }

    /// The download another title the player moves on to stands for.
    func download(for itemId: String) -> DownloadedItem? {
        itemId == downloadedItem.itemId ? downloadedItem : episodes[itemId]
    }

    var capabilities: PlaybackCapabilities { .local }
    var isLocal: Bool { true }
    /// AVFoundation can't open most files' containers, so a file stays on Aether unless VLC is picked.
    func engine(for preference: PlaybackEngineKind) -> PlaybackEngineKind { preference == .vlc ? .vlc : .aether }
    var tracksComeFromEngine: Bool { true }
    var unavailableMessage: String? { nil }

    func attach(authManager: AuthManager, mediaRepo: MediaRepository) {
        self.authManager = authManager
    }

    private var directory: URL { DownloadStore.directory(for: downloadedItem) }
    private var videoURL: URL { directory.appendingPathComponent(downloadedItem.videoFileName) }

    // MARK: Resume

    /// An explicit Start Over, else the local position, unless the server (asked briefly, so
    /// offline starts aren't held up) has a newer one from another device.
    func startPosition() async -> (ticks: Int64, decided: Bool)? {
        if let startPositionOverride { return (startPositionOverride, true) }
        let local = downloadedItem.playbackPositionTicks
        // Unsynced local progress is the newest there is.
        guard !downloadedItem.needsSync, let authManager,
              let credential = OfflineProgressSync.credential(for: downloadedItem.profile, in: authManager.profiles)
        else { return (local, false) }
        let header = authManager.authClient.authHeader(token: credential.accessToken)
        let itemId = downloadedItem.itemId
        // Whichever finishes first: the server's answer, or nil after 2.5 seconds.
        let server: UserData? = await withTaskGroup(of: UserData?.self) { group in
            group.addTask {
                let data = try? await JellyfinMediaClient().getUserData(credential: credential, authHeader: header, itemId: itemId)
                return data ?? nil
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(2.5))
                return nil
            }
            let first = await group.next()
            group.cancelAll()
            return first ?? nil
        }
        guard let server else { return (local, false) }
        if server.played && server.playbackPositionTicks == 0 { return (local, false) }
        return (server.playbackPositionTicks, false)
    }

    // MARK: Streams

    /// The subtitles saved beside the video, described by the saved details when there are any.
    private var sidecars: [JellyfinMediaStream] {
        let saved = Dictionary((savedStreams?.streams ?? []).filter { $0.type == "Subtitle" }.map { ($0.index, $0) },
                               uniquingKeysWith: { first, _ in first })
        return downloadedItem.subtitleFileNames.enumerated().compactMap { order, fileName in
            guard let index = LocalTracks.sidecarIndex(fileName: fileName) else { return nil }
            let language = downloadedItem.subtitleLanguages.indices.contains(order) ? downloadedItem.subtitleLanguages[order] : nil
            let stream = saved[index]
            return JellyfinMediaStream(
                index: index, type: "Subtitle", codec: "webvtt", language: stream?.language ?? language,
                displayTitle: stream?.displayTitle ?? language, isDefault: stream?.isDefault ?? false,
                isForced: stream?.isForced ?? false, isExternal: true)
        }
    }

    private var savedVideo: JellyfinMediaStream? { savedStreams?.streams.first { $0.type == "Video" } }

    func playbackInfo(for item: MediaItem, _ request: PlaybackInfoRequest) async throws -> JellyfinPlaybackInfo {
        guard FileManager.default.fileExists(atPath: videoURL.path) else { throw DownloadFileMissing() }
        await loadSavedDetails()
        let saved = savedStreams?.streams ?? []
        return .local(url: videoURL, container: videoURL.pathExtension.lowercased(), runTimeTicks: item.runTimeTicks,
                      audio: saved.filter { $0.type == "Audio" },
                      subtitles: saved.filter { $0.type == "Subtitle" && !$0.isExternal } + sidecars, video: savedVideo)
    }

    func tracksLoaded(on player: any MediaPlayerProtocol, info: JellyfinPlaybackInfo) async -> JellyfinPlaybackInfo? {
        await waitForEngineTracks(player)
        await loadSavedDetails()
        let tracks = LocalTracks.streams(saved: savedStreams?.streams ?? [], sidecars: sidecars,
                                         engineAudio: player.availableAudioTracks, engineSubtitles: player.availableSubtitleTracks)
        let defaultAudio = tracks.audio.first(where: \.isDefault)?.index ?? (tracks.audio.isEmpty ? nil : player.selectedAudioTrackIndex)
        return .local(url: videoURL, container: info.container, runTimeTicks: info.runTimeTicks, audio: tracks.audio,
                      subtitles: tracks.subtitles, video: savedVideo, defaultAudio: defaultAudio)
    }

    // MARK: Details

    func details(for item: MediaItem, info: JellyfinPlaybackInfo, includesItemDetail: Bool) async -> PlaybackDetails {
        var details = PlaybackDetails()
        await loadSavedDetails()
        let data = savedDetailData
        let detail = await Task.detached(priority: .userInitiated) {
            data.flatMap { try? JellyfinMediaClient.decodeItemDetail($0) }
        }.value
        if let trickplay = localTrickplay {
            details.trickplay = TrickplayLoader(directory: directory, fileNames: downloadedItem.trickplayFileNames, info: trickplay)
        }
        details.chapters = detail?.chapters ?? []
        details.castMembers = detail?.cast ?? zip(downloadedItem.castNames, downloadedItem.castRoles + Array(
            repeating: "", count: max(0, downloadedItem.castNames.count - downloadedItem.castRoles.count))).enumerated().map { index, person in
                MediaPerson(id: "local-cast-\(index)", name: person.0, role: person.1.isEmpty ? nil : person.1)
            }
        var genres = downloadedItem.genres.isEmpty ? (detail?.genres ?? []) : downloadedItem.genres
        // An episode rarely carries genres of its own, so its show's are read when it has none.
        if genres.isEmpty, let seriesId = downloadedItem.seriesId,
           let series = try? downloadedItem.modelContext?.fetch(FetchDescriptor<DownloadedSeries>(
            predicate: #Predicate { $0.seriesId == seriesId })).first {
            genres = series.genres
        }
        details.genres = genres
        return details
    }

    private var localTrickplay: JellyfinTrickplayInfo? {
        guard let intervalMs = downloadedItem.trickplayIntervalMs, intervalMs > 0,
              let thumbnailCount = downloadedItem.trickplayThumbnailCount, thumbnailCount > 0,
              let tileWidth = downloadedItem.trickplayTileWidth, tileWidth > 0,
              let tileHeight = downloadedItem.trickplayTileHeight, tileHeight > 0,
              let width = downloadedItem.trickplayWidth, let height = downloadedItem.trickplayHeight,
              !downloadedItem.trickplayFileNames.isEmpty
        else { return nil }
        return JellyfinTrickplayInfo(width: width, height: height, tileWidth: tileWidth, tileHeight: tileHeight,
                                     thumbnailCount: thumbnailCount, intervalMs: intervalMs)
    }

    /// A photo saved with the download for one of its cast, in billing order.
    func castPhotoURL(for person: MediaPerson, in cast: [MediaPerson]) -> URL? {
        guard let index = cast.firstIndex(of: person), downloadedItem.castPhotoFileNames.indices.contains(index),
              !downloadedItem.castPhotoFileNames[index].isEmpty
        else { return nil }
        return directory.appendingPathComponent(downloadedItem.castPhotoFileNames[index])
    }

    // MARK: Subtitles

    func subtitleLocation(for stream: JellyfinMediaStream, in info: JellyfinPlaybackInfo, item: MediaItem) -> String? {
        guard stream.isExternal else { return nil }
        let fileName = "sub-\(stream.index).vtt"
        guard downloadedItem.subtitleFileNames.contains(fileName) else { return nil }
        return directory.appendingPathComponent(fileName).path
    }

    func subtitleCues(at location: String) async -> [SubtitleCue] {
        await SubtitleLoader.loadCues(fileURL: URL(fileURLWithPath: location))
    }

    func drawsSubtitleInEngine(_ stream: JellyfinMediaStream) -> Bool { !stream.isExternal }

    func skipSegments(for item: MediaItem) async -> SkipSegments { downloadedItem.skipSegments }

    // MARK: Next and previous

    /// The show's other downloaded episodes, for this profile, in season and episode order.
    func neighbours(of item: MediaItem) async -> (next: MediaItem?, previous: MediaItem?) {
        guard let seriesId = downloadedItem.seriesId, let context = downloadedItem.modelContext,
              let rows = try? context.fetch(FetchDescriptor<DownloadedItem>(predicate: #Predicate { $0.seriesId == seriesId }))
        else { return (nil, nil) }
        let profile = downloadedItem.profile
        let mine = rows.filter { $0.profile == profile }
        let order = LocalEpisodeOrder.neighbours(
            of: LocalEpisodeOrder.Episode(downloadedItem),
            in: mine.map(LocalEpisodeOrder.Episode.init))
        for row in mine where row.itemId == order.next || row.itemId == order.previous { episodes[row.itemId] = row }
        return (order.next.flatMap { episodes[$0] }.map(Self.mediaItem(for:)),
                order.previous.flatMap { episodes[$0] }.map(Self.mediaItem(for:)))
    }

    // MARK: Artwork

    func artwork(for item: MediaItem) async -> PlatformImage? {
        guard let url = localImageURL(for: item.id) else { return nil }
        return PlatformImage.from(contentsOfFile: url.path)
    }

    func localImageURL(for itemId: String) -> URL? {
        guard let download = download(for: itemId), let poster = download.posterFileName else { return nil }
        return DownloadStore.directory(for: download).appendingPathComponent(poster)
    }

    // MARK: Progress

    /// Once it has played with a position, never before: a save at 0 would read as a newer
    /// resume point.
    nonisolated static func hasStarted(atTicks ticks: Int64, durationTicks: Int64, status: PlaybackStatus) -> Bool {
        ticks > 0 && durationTicks > 0 && (status == .playing || status == .paused)
    }

    func positionChanged(ticks: Int64, durationTicks: Int64, status: PlaybackStatus) {
        if !hasStarted, Self.hasStarted(atTicks: ticks, durationTicks: durationTicks, status: status) { hasStarted = true }
    }

    func playbackStarted(item: MediaItem, info: JellyfinPlaybackInfo, positionTicks: Int64) async {}

    func reportProgress(_ progress: PlaybackProgressReport) async {
        savePosition(ticks: progress.positionTicks, durationTicks: progress.durationTicks, final: false)
    }

    func playbackStopped(_ stop: PlaybackStopReport) async {
        savePosition(ticks: stop.positionTicks, durationTicks: stop.durationTicks, final: true)
        // Moving on to the next episode after watching this one counts as watching to the end.
        if stop.handedOver { deleteIfWatchedHere() }
    }

    func playbackFinished(item: MediaItem, positionTicks: Int64, durationTicks: Int64) async {
        savePosition(ticks: positionTicks, durationTicks: durationTicks, final: true)
        // The player's end can come early (a converted file cut short), so only a title
        // watched to the end in this playback goes: one watched before it was downloaded
        // is already marked watched.
        deleteIfWatchedHere()
    }

    private func deleteIfWatchedHere() {
        guard finishedHere, UserDefaults.standard.bool(forKey: "deleteDownloadsAfterWatching") else { return }
        AppServices.downloadManager.markForDeletionAfterWatching(downloadedItem)
    }

    private func savePosition(ticks: Int64, durationTicks: Int64, final: Bool) {
        guard hasStarted else { return }
        downloadedItem.playbackPositionTicks = ticks
        // Settings › Playback › Mark as Watched, with Jellyfin's own 90% for Server Default.
        // Only ever set here, never cleared: watching a finished title again doesn't make it
        // unwatched, on the server either.
        if durationTicks > 0 {
            let seconds = Double(ticks) / 10_000_000
            let duration = Double(durationTicks) / 10_000_000
            let threshold = WatchedThreshold.current
            let reached = threshold == .server
                ? seconds / duration >= 0.9
                : threshold.isReached(seconds: seconds, duration: duration, creditsStart: downloadedItem.creditsStartSeconds)
            if reached {
                downloadedItem.played = true
                finishedHere = true
            }
        }
        // Picked up by OfflineProgressSync once the app's back online — this is the only
        // record that playback happened at all while offline.
        downloadedItem.needsSync = true
        downloadedItem.progressChangedAt = Date()
        try? downloadedItem.modelContext?.save()
        if final { syncNow() }
    }

    /// Hands the position to the server right away when it's reachable; otherwise it waits
    /// for the next sync (coming back online, the app reopening).
    private func syncNow() {
        guard let authManager, let context = downloadedItem.modelContext else { return }
        let profiles = authManager.profiles
        let authClient = authManager.authClient
        Task {
            await OfflineProgressSync.syncPending(
                modelContext: context, profiles: profiles,
                authHeader: { authClient.authHeader(token: $0.accessToken) }
            )
        }
    }

    func fallbackEngine(for info: JellyfinPlaybackInfo) -> any MediaPlayerProtocol { VLCEnginePlayer() }
}

/// The order of a show's downloaded episodes, which may be only some of its run.
enum LocalEpisodeOrder {
    struct Episode: Equatable {
        let id: String
        let season: Int?
        let episode: Int?

        init(id: String, season: Int?, episode: Int?) {
            self.id = id; self.season = season; self.episode = episode
        }

        @MainActor init(_ download: DownloadedItem) {
            self.init(id: download.itemId, season: download.seasonNumber, episode: download.episodeNumber)
        }
    }

    /// Specials sit outside the run of the show unless one is what's playing, as when streaming.
    static func neighbours(of current: Episode, in episodes: [Episode]) -> (next: String?, previous: String?) {
        var seen = Set<String>()
        let run = episodes
            .filter { seen.insert($0.id).inserted }
            .filter { current.season == 0 || $0.season != 0 || $0.id == current.id }
            .sorted { ($0.season ?? .max, $0.episode ?? .max, $0.id) < ($1.season ?? .max, $1.episode ?? .max, $1.id) }
        guard let index = run.firstIndex(where: { $0.id == current.id }) else { return (nil, nil) }
        return (run.indices.contains(index + 1) ? run[index + 1].id : nil, index > 0 ? run[index - 1].id : nil)
    }
}
