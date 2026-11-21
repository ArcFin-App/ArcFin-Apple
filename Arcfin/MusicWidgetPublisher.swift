// SPDX-License-Identifier: AGPL-3.0-or-later

#if !os(tvOS)
import AuthCore
import Foundation
import JellyfinAPI
import LiveActivityKit
import MediaEngine
import WidgetKit

/// Keeps the music widgets (Home Screen, Lock Screen, StandBy, CarPlay, the Mac, and Control
/// Center's toggle) showing what's playing, and performs their buttons. Started once at launch.
@MainActor
enum MusicWidgetPublisher {
    private static var isStarted = false
    private static var writeTask: Task<Void, Never>?
    private static var recentTask: Task<Void, Never>?
    private static var recentlyPlayed: [MusicSong] = []
    private static var recentProfile: UUID?
    private static let maxUpNext = 4
    private static let maxRecent = 8

    static func start() {
        guard !isStarted else { return }
        isStarted = true
        MusicIntentPerformer.handle = { await perform($0) }
        follow()
        refreshRecentlyPlayed()
    }

    // MARK: Buttons

    private static func perform(_ command: MusicIntentCommand) async {
        // Started by the widget, the app hasn't signed in or brought the queue back yet.
        await AppServices.authManager.checkStoredAuthOnce()
        let music = AppServices.music
        music.restoreQueue()
        switch command {
        case .togglePlayPause:
            music.isActive ? music.togglePlayPause() : await playRecent(from: nil)
        case .setPlaying(let playing):
            if !playing { music.pause() } else if music.isActive { music.resume() } else { await playRecent(from: nil) }
        case .next: music.next()
        case .previous: music.previous()
        case .play(let songID): await playRecent(from: songID)
        }
    }

    /// The widget's Recently Played list, from this song (or the top).
    private static func playRecent(from songID: String?) async {
        let ids = MusicWidgetStore.load()?.recentlyPlayed.map(\.id) ?? []
        guard !ids.isEmpty, let songs = try? await MusicAPI.call({
            try await $0.getSongs(credential: $1, authHeader: $2, ids: ids)
        }), !songs.isEmpty else { return }
        let index = songID.flatMap { id in songs.firstIndex { $0.id == id } } ?? 0
        MusicActions.play(songs, from: index)
    }

    // MARK: Snapshot

    private static func follow() {
        withObservationTracking {
            let music = AppServices.music
            _ = music.player.current?.id
            _ = music.isPlaying
            _ = music.player.queue.upNext.prefix(maxUpNext).map(\.id)
            _ = music.player.seekCount
            _ = AppServices.authManager.state.credential?.id
        } onChange: {
            Task { @MainActor in
                scheduleWrite()
                follow()
            }
        }
    }

    /// A moment after things settle, so a skip through several songs writes once.
    private static func scheduleWrite() {
        writeTask?.cancel()
        writeTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await write()
        }
    }

    private static func write() async {
        let music = AppServices.music
        // Like Siri and Spotlight, nothing from a profile with an app-lock PIN.
        guard let profile = AppServices.authManager.state.credential?.id, IntentSession.credential() != nil else {
            MusicWidgetStore.clear()
            reload()
            return
        }
        if profile != recentProfile {
            recentProfile = profile
            recentlyPlayed = []
            refreshRecentlyPlayed()
        }
        let current = music.player.current
        var keep = Set<String>()
        func entry(_ song: MusicSong) async -> MusicWidgetSnapshot.Song {
            let cover = await storeCover(song)
            if let cover { keep.insert(cover) }
            return .init(id: song.id, title: song.name, artist: song.artistLine, album: song.albumName, coverFileName: cover)
        }
        var playing: MusicWidgetSnapshot.Song?
        if let current { playing = await entry(current) }
        var next: [MusicWidgetSnapshot.Song] = []
        for item in music.player.queue.upNext.prefix(maxUpNext) { next.append(await entry(item.track)) }
        var recent: [MusicWidgetSnapshot.Song] = []
        for song in recentlyPlayed.prefix(maxRecent) { recent.append(await entry(song)) }
        guard AppServices.authManager.state.credential?.id == profile else { return }
        let snapshot = MusicWidgetSnapshot(nowPlaying: playing, isPlaying: music.isPlaying, position: music.position,
                                           duration: music.player.duration, upNext: next, recentlyPlayed: recent)
        MusicWidgetStore.save(snapshot)
        MusicWidgetStore.pruneCovers(keeping: keep)
        reload()
        // What was played changes as songs start; asked again a little after.
        if current != nil { refreshRecentlyPlayed(after: .seconds(5)) }
    }

    private static func refreshRecentlyPlayed(after delay: Duration = .zero) {
        recentTask?.cancel()
        recentTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await AppServices.authManager.checkStoredAuthOnce()
            let profile = AppServices.authManager.state.credential?.id
            let songs = (try? await MusicAPI.call {
                try await $0.getMusicTracks(credential: $1, authHeader: $2, libraryId: nil, sort: .datePlayed,
                                            ascending: false, filter: .init(playedOnly: true), limit: maxRecent)
            })?.tracks ?? []
            guard !Task.isCancelled, AppServices.authManager.state.credential?.id == profile,
                  songs.map(\.id) != recentlyPlayed.map(\.id) else { return }
            recentlyPlayed = songs
            scheduleWrite()
        }
    }

    /// Covers are kept by album (or song), so an unchanged widget downloads nothing.
    private static func storeCover(_ song: MusicSong) async -> String? {
        let name = "cover-\(song.albumId ?? song.id).jpg"
        if MusicWidgetStore.hasCover(fileName: name) { return name }
        guard let url = MusicAPI.artworkURL(song, width: 300), let data = await URLSession.arcfin.imageData(from: url)
        else { return nil }
        MusicWidgetStore.writeCover(data, fileName: name)
        return name
    }

    private static func reload() {
        WidgetCenter.shared.reloadTimelines(ofKind: MusicWidgetStore.nowPlayingKind)
        WidgetCenter.shared.reloadTimelines(ofKind: MusicWidgetStore.recentlyPlayedKind)
        ControlCenter.shared.reloadControls(ofKind: MusicWidgetStore.controlKind)
    }
}
#endif
