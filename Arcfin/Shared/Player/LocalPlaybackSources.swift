// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import JellyfinAPI
import MediaEngine

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
