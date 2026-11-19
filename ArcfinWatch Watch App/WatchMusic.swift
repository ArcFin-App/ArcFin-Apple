// SPDX-License-Identifier: AGPL-3.0-or-later

import AVFoundation
import Foundation
import MediaPlayer

/// Music played on the watch itself, to AirPods or other Bluetooth headphones: a playlist's
/// songs, from the watch when they're kept on it, streamed otherwise.
@MainActor @Observable
final class WatchMusicPlayer {
    private(set) var queue: [WatchSong] = []
    private(set) var index = 0
    private(set) var isPlaying = false
    private(set) var problem: String?
    @ObservationIgnored private let player = AVQueuePlayer()
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var items: [ObjectIdentifier: Int] = [:]

    var current: WatchSong? { queue.indices.contains(index) ? queue[index] : nil }

    init() {
        statusObservation = player.observe(\.timeControlStatus) { [weak self] player, _ in
            let playing = player.timeControlStatus != .paused
            Task { @MainActor [weak self] in self?.isPlaying = playing }
        }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification,
                                                             object: nil, queue: .main) { [weak self] note in
            let ended = (note.object as? AVPlayerItem).map(ObjectIdentifier.init)
            MainActor.assumeIsolated { self?.itemEnded(ended) }
        }
        setUpRemoteCommands()
    }

    /// The watch only plays to headphones: activating asks to pick them when none is on.
    func play(_ songs: [WatchSong], from start: Int = 0, shuffled: Bool = false, using client: WatchJellyfin?) async {
        guard !songs.isEmpty else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, policy: .longFormAudio)
            guard try await session.activate() else { return }
        } catch {
            problem = String(localized: "Connect AirPods or other Bluetooth headphones to play music on your watch.")
            return
        }
        problem = nil
        queue = shuffled ? songs.shuffled() : songs
        index = shuffled ? 0 : min(start, songs.count - 1)
        player.removeAllItems()
        items = [:]
        for (offset, song) in queue.enumerated().dropFirst(index) {
            guard let url = WatchMusicDownloads.shared.file(for: song.id) ?? client?.streamURL(songID: song.id) else { continue }
            let item = AVPlayerItem(url: url)
            items[ObjectIdentifier(item)] = offset
            player.insert(item, after: nil)
        }
        player.play()
        updateNowPlaying()
    }

    func togglePlayPause() {
        if isPlaying { player.pause() } else { player.play() }
        updateNowPlaying()
    }

    func next() {
        guard index + 1 < queue.count else { return }
        player.advanceToNextItem()
        index += 1
        updateNowPlaying()
    }

    private func itemEnded(_ item: ObjectIdentifier?) {
        guard let item, let ended = items[item] else { return }
        index = ended + 1
        if index >= queue.count { isPlaying = false }
        updateNowPlaying()
    }

    private func updateNowPlaying() {
        guard let song = current else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [MPMediaItemPropertyTitle: song.name,
                                   MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0]
        if let artist = song.artist { info[MPMediaItemPropertyArtist] = artist }
        if let seconds = song.seconds { info[MPMediaItemPropertyPlaybackDuration] = seconds }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func setUpRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.togglePlayPause() }
            return .success
        }
        center.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.player.play() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.player.pause() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.next() }
            return .success
        }
    }
}

/// Playlists kept on the watch to play without the iPhone or a connection.
@MainActor @Observable
final class WatchMusicDownloads {
    static let shared = WatchMusicDownloads()

    private struct Index: Codable {
        var playlists: [WatchPlaylist] = []
        var songs: [String: [WatchSong]] = [:]
        var files: [String: String] = [:]
    }

    private var index = Index()
    /// The playlist downloading now and how far, 0 to 1.
    private(set) var downloading: (id: String, progress: Double)?

    private static let folder: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("Music", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()
    private static var indexURL: URL { folder.appendingPathComponent("index.json") }

    private init() {
        if let data = try? Data(contentsOf: Self.indexURL), let saved = try? JSONDecoder().decode(Index.self, from: data) {
            index = saved
        }
    }

    var playlists: [WatchPlaylist] { index.playlists }
    func songs(in playlist: WatchPlaylist) -> [WatchSong] { index.songs[playlist.id] ?? [] }
    func isKept(_ playlist: WatchPlaylist) -> Bool { index.playlists.contains { $0.id == playlist.id } }

    func file(for songID: String) -> URL? {
        guard let name = index.files[songID] else { return nil }
        let url = Self.folder.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Keeps every song of the playlist; ones already here aren't fetched again.
    func keep(_ playlist: WatchPlaylist, songs: [WatchSong], using client: WatchJellyfin) async {
        guard downloading == nil else { return }
        downloading = (playlist.id, 0)
        defer { downloading = nil }
        for (offset, song) in songs.enumerated() {
            downloading = (playlist.id, Double(offset) / Double(max(songs.count, 1)))
            guard file(for: song.id) == nil, let url = client.streamURL(songID: song.id),
                  let (temp, response) = try? await URLSession.shared.download(from: url),
                  (response as? HTTPURLResponse).map({ (200...299).contains($0.statusCode) }) == true else { continue }
            let name = "\(song.id).mp3"
            let destination = Self.folder.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: destination)
            guard (try? FileManager.default.moveItem(at: temp, to: destination)) != nil else { continue }
            index.files[song.id] = name
        }
        index.songs[playlist.id] = songs
        if !isKept(playlist) { index.playlists.append(playlist) }
        save()
    }

    /// Removes the playlist and any of its songs no other kept playlist has.
    func remove(_ playlist: WatchPlaylist) {
        let songs = index.songs.removeValue(forKey: playlist.id) ?? []
        index.playlists.removeAll { $0.id == playlist.id }
        let stillKept = Set(index.songs.values.flatMap { $0.map(\.id) })
        for song in songs where !stillKept.contains(song.id) {
            if let name = index.files.removeValue(forKey: song.id) {
                try? FileManager.default.removeItem(at: Self.folder.appendingPathComponent(name))
            }
        }
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(index) else { return }
        try? data.write(to: Self.indexURL, options: .atomic)
    }
}
