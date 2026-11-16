// SPDX-License-Identifier: AGPL-3.0-or-later

import AuthCore
import Foundation
import JellyfinAPI
import Observation
import os
import Telemetry

/// Songs saved for listening offline: each one's file (as it is where this device plays it,
/// MP3 otherwise), its details and its album's cover, kept in Application Support per
/// profile. One downloads at a time while the app is open.
@MainActor @Observable
final class MusicDownloads {
    static let shared = MusicDownloads()

    struct Saved: Codable {
        var song: MusicSong
        var file: String
        var userID: String
        var bytes: Int64
        var savedAt: Date
    }

    private struct Index: Codable {
        var songs: [String: Saved] = [:]
        var albums: [String: MusicAlbum] = [:]
    }

    private var index = Index()
    /// Waiting or downloading, in order.
    private(set) var queue: [MusicSong] = []
    private(set) var current: String?
    /// How far the current song is, 0 to 1.
    private(set) var progress: Double = 0
    /// Settings › Music › Download on Mobile Data is off and this is on mobile data.
    private(set) var isWaitingForWiFi = false
    @ObservationIgnored private var worker: Task<Void, Never>?
    /// The current song's transfer, so cancelling it stops the download.
    @ObservationIgnored private var transfer: Task<Void, Never>?
    @ObservationIgnored private let log = Telemetry.logger(category: "MusicDownloads")

    private static let folder: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("MusicDownloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var excluded = url
        try? excluded.setResourceValues(values)
        return url
    }()
    private static var indexURL: URL { folder.appendingPathComponent("index.json") }

    private init() {
        if let data = try? Data(contentsOf: Self.indexURL), let saved = try? JSONDecoder().decode(Index.self, from: data) {
            index = saved
        }
    }

    private var userID: String? { AppServices.authManager.state.credential?.userID }

    private var mine: [Saved] { index.songs.values.filter { $0.userID == userID } }

    var isEmpty: Bool { mine.isEmpty }
    var songCount: Int { mine.count }
    var totalBytes: Int64 { mine.reduce(0) { $0 + $1.bytes } }

    func bytes(of songs: [MusicSong]) -> Int64 {
        songs.reduce(0) { $0 + (index.songs[$1.id]?.bytes ?? 0) }
    }

    func isDownloaded(_ songID: String) -> Bool { index.songs[songID]?.userID == userID && index.songs[songID] != nil }
    func isQueued(_ songID: String) -> Bool { queue.contains { $0.id == songID } }

    /// The saved file, to play instead of streaming.
    func localURL(for songID: String) -> URL? {
        guard let saved = index.songs[songID], saved.userID == userID else { return nil }
        let url = Self.folder.appendingPathComponent(saved.file)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// An album's cover, saved with its songs.
    func coverURL(albumID: String) -> URL? {
        let url = Self.folder.appendingPathComponent("\(albumID).jpg")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Saved albums, newest first, each with its songs in disc and track order.
    var albums: [(album: MusicAlbum?, songs: [MusicSong])] {
        let groups = Dictionary(grouping: mine) { $0.song.albumId ?? "" }
        let newestFirst = groups.sorted { lhs, rhs in
            (lhs.value.map(\.savedAt).max() ?? .distantPast) > (rhs.value.map(\.savedAt).max() ?? .distantPast)
        }
        return newestFirst.map { key, saved in
            (album: index.albums[key], songs: saved.map(\.song).sorted(by: Self.trackOrder))
        }
    }

    private static func trackOrder(_ lhs: MusicSong, _ rhs: MusicSong) -> Bool {
        let left = (lhs.discNumber ?? 1, lhs.trackNumber ?? 0), right = (rhs.discNumber ?? 1, rhs.trackNumber ?? 0)
        return left < right
    }

    /// How much of an album is saved or on its way, for its button.
    func state(of songs: [MusicSong]) -> (saved: Int, queued: Int) {
        (songs.filter { isDownloaded($0.id) }.count, songs.filter { isQueued($0.id) }.count)
    }

    // MARK: Changing what's saved

    func download(_ songs: [MusicSong], album: MusicAlbum? = nil) {
        if let album { index.albums[album.id] = album }
        for song in songs where !isDownloaded(song.id) && !isQueued(song.id) {
            queue.append(song)
        }
        saveIndex()
        startIfNeeded()
    }

    /// A song, or an album's songs, just made a favourite (Keep Favorites Downloaded).
    func downloadFavorite(_ id: String) async {
        if let songs = try? await MusicAPI.call({ try await $0.getSongs(credential: $1, authHeader: $2, ids: [id]) }) ?? nil,
           !songs.isEmpty {
            return download(songs)
        }
        let tracks = (try? await MusicAPI.call { try await $0.getAlbumTracks(credential: $1, authHeader: $2, albumId: id) }) ?? []
        download(tracks)
    }

    /// Every favourite song and album, for turning Keep Favorites Downloaded on.
    func downloadAllFavorites() async {
        if let albums = try? await MusicAPI.call({
            try await $0.getMusicAlbums(credential: $1, authHeader: $2, libraryId: nil,
                                        filter: .init(favoritesOnly: true), limit: 500)
        }).albums {
            for album in albums { download(await MusicActions.albumSongs(album), album: album) }
        }
        var start = 0
        while true {
            guard let page = try? await MusicAPI.call({
                try await $0.getMusicTracks(credential: $1, authHeader: $2, libraryId: nil,
                                            filter: .init(favoritesOnly: true), startIndex: start, limit: 200)
            }) else { return }
            download(page.tracks)
            start += page.tracks.count
            if page.tracks.isEmpty || start >= page.total { return }
        }
    }

    func download(album: MusicAlbum) {
        Task { download(await MusicActions.albumSongs(album), album: album) }
    }

    func remove(_ songs: [MusicSong]) {
        let ids = Set(songs.map(\.id))
        queue.removeAll { ids.contains($0.id) }
        if let current, ids.contains(current) { transfer?.cancel() }
        for id in ids {
            guard let saved = index.songs.removeValue(forKey: id) else { continue }
            try? FileManager.default.removeItem(at: Self.folder.appendingPathComponent(saved.file))
        }
        dropUnusedAlbums()
        saveIndex()
    }

    /// Stops songs that haven't finished; one halfway through is thrown away.
    func cancel(_ songs: [MusicSong]) {
        let ids = Set(songs.map(\.id))
        queue.removeAll { ids.contains($0.id) }
        if let current, ids.contains(current) { transfer?.cancel() }
    }

    func cancelAll() {
        queue.removeAll()
        transfer?.cancel()
    }

    func removeAll() {
        queue.removeAll()
        remove(mine.map(\.song))
    }

    private func dropUnusedAlbums() {
        let used = Set(index.songs.values.compactMap(\.song.albumId))
        for id in index.albums.keys where !used.contains(id) {
            index.albums[id] = nil
            try? FileManager.default.removeItem(at: Self.folder.appendingPathComponent("\(id).jpg"))
        }
    }

    // MARK: Downloading

    private func startIfNeeded() {
        guard worker == nil, !queue.isEmpty else { return }
        worker = Task { [weak self] in
            var saved = 0
            while let self, let song = queue.first {
                while MusicSettings.downloadsWaitForWiFi, !queue.isEmpty {
                    isWaitingForWiFi = true
                    try? await Task.sleep(for: .seconds(5))
                }
                isWaitingForWiFi = false
                guard queue.first?.id == song.id else { continue }
                current = song.id
                progress = 0
                let transfer = Task { await fetch(song) }
                self.transfer = transfer
                await transfer.value
                self.transfer = nil
                if isDownloaded(song.id) { saved += 1 }
                queue.removeAll { $0.id == song.id }
                current = nil
            }
            self?.worker = nil
            if saved > 0, MusicSettings.notifiesDownloads {
                await NotificationManager.notifyMusicDownloaded(songs: saved)
            }
        }
    }

    private func fetch(_ song: MusicSong) async {
        guard let credential = AppServices.authManager.state.credential,
              let url = MusicAPI.client.audioStreamURL(credential: credential, deviceId: Self.deviceID, trackId: song.id,
                                                       container: song.container,
                                                       bitrateCap: MusicSettings.downloadBitrate) else { return }
        do {
            let (temp, response) = try await URLSession.arcfin.download(from: url, delegate: ProgressReporter { fraction in
                Task { @MainActor in MusicDownloads.shared.reportProgress(fraction, for: song.id) }
            })
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            // Cancelled while it downloaded.
            guard isQueued(song.id) else {
                try? FileManager.default.removeItem(at: temp)
                return
            }
            let file = "\(song.id).\(url.pathExtension)"
            let destination = Self.folder.appendingPathComponent(file)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: temp, to: destination)
            let bytes = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            index.songs[song.id] = Saved(song: song, file: file, userID: credential.userID, bytes: bytes, savedAt: .now)
            saveIndex()
            await saveCover(for: song)
        } catch {
            log.error("Couldn't save \(song.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func reportProgress(_ fraction: Double, for songID: String) {
        guard current == songID else { return }
        progress = fraction
    }

    private func saveCover(for song: MusicSong) async {
        guard let albumID = song.albumId, coverURL(albumID: albumID) == nil,
              let url = MusicAPI.artworkURL(song, width: 600),
              let data = await URLSession.arcfin.imageData(from: url) else { return }
        try? data.write(to: Self.folder.appendingPathComponent("\(albumID).jpg"))
    }

    private func saveIndex() {
        guard let data = try? JSONEncoder().encode(index) else { return }
        try? data.write(to: Self.indexURL, options: .atomic)
    }

    private static let deviceID = UserDefaults.standard.string(forKey: "arcfin.deviceId") ?? UUID().uuidString
}

/// Passes on a download's progress, a percent at a time.
private final class ProgressReporter: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let report: @Sendable (Double) -> Void
    private var observation: NSKeyValueObservation?
    private var last = -1

    init(_ report: @escaping @Sendable (Double) -> Void) {
        self.report = report
    }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        observation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            guard let self else { return }
            let percent = Int(progress.fractionCompleted * 100)
            guard percent != last else { return }
            last = percent
            report(progress.fractionCompleted)
        }
    }
}
