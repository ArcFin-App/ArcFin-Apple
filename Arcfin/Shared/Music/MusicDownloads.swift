// SPDX-License-Identifier: AGPL-3.0-or-later

import AuthCore
import Foundation
import JellyfinAPI
import Network
import Observation
import os
import Telemetry

/// Songs saved for listening offline: each one's file (as it is where this device plays it,
/// MP3 otherwise), its details and its album's cover, kept in Application Support per
/// profile. Two download at a time while the app is open; the queue is kept across launches,
/// waits out a lost connection, and a song that keeps failing waits for Retry.
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

    /// What's still to download, kept apart from the index so an older index still reads.
    private struct Pending: Codable {
        var queue: [MusicSong] = []
        var failed: [MusicSong] = []
    }

    private enum Outcome { case saved, cancelled, retry, failed }

    private var index = Index()
    /// Waiting or downloading, in order.
    private(set) var queue: [MusicSong] = []
    /// Songs that failed every try, until Retry puts them back in the queue.
    private(set) var failed: [MusicSong] = []
    /// The songs downloading now and how far each is, 0 to 1.
    private(set) var progress: [String: Double] = [:]
    /// Settings › Music › Download on Mobile Data is off and this is on mobile data.
    private(set) var isWaitingForWiFi = false
    /// No connection (or not signed in yet): the queue carries on once there is.
    private(set) var isWaitingForNetwork = false
    private var isOnline = true
    @ObservationIgnored private var worker: Task<Void, Never>?
    /// Each song's transfer, so cancelling it stops the download.
    @ObservationIgnored private var transfers: [String: Task<Bool, Never>] = [:]
    /// Where a dropped download got to, so the next try picks up from there.
    @ObservationIgnored private var resumeData: [String: Data] = [:]
    @ObservationIgnored private let pathMonitor = NWPathMonitor()
    @ObservationIgnored private var session: (headers: [String: String], session: URLSession)?
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
    private static var pendingURL: URL { folder.appendingPathComponent("queue.json") }
    private static let parallel = 2
    private static let attempts = 4
    /// Seconds before each try after the first.
    private static let backoff: [Double] = [2, 10, 30]
    private static let retryable: Set<URLError.Code> = [
        .timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost, .cannotFindHost,
        .dnsLookupFailed, .cannotLoadFromNetwork, .dataNotAllowed, .internationalRoamingOff, .callIsActive,
        .backgroundSessionWasDisconnected,
    ]

    private init() {
        if let data = try? Data(contentsOf: Self.indexURL), let saved = try? JSONDecoder().decode(Index.self, from: data) {
            index = saved
        }
        if let data = try? Data(contentsOf: Self.pendingURL), let pending = try? JSONDecoder().decode(Pending.self, from: data) {
            queue = pending.queue
            failed = pending.failed
        }
        pathMonitor.pathUpdateHandler = { path in
            let online = path.status == .satisfied
            Task { @MainActor in MusicDownloads.shared.isOnline = online }
        }
        pathMonitor.start(queue: DispatchQueue(label: "arcfin.musicDownloads.path"))
        // Left from last time: it carries on once the app is up.
        if !queue.isEmpty { Task { @MainActor in MusicDownloads.shared.startIfNeeded() } }
    }

    /// Offline, before the sign-in is confirmed, the last profile's songs are still the ones
    /// to show.
    private var userID: String? {
        let auth = AppServices.authManager
        if let credential = auth.state.credential { return credential.userID }
        let active = UserDefaults.standard.string(forKey: "arcfin.activeProfileID")
        return auth.profiles.first { $0.id.uuidString == active }?.userID
    }

    private var mine: [Saved] { index.songs.values.filter { $0.userID == userID } }

    var isEmpty: Bool { mine.isEmpty }
    var songCount: Int { mine.count }
    var totalBytes: Int64 { mine.reduce(0) { $0 + $1.bytes } }

    func bytes(of songs: [MusicSong]) -> Int64 {
        songs.reduce(0) { $0 + (index.songs[$1.id]?.bytes ?? 0) }
    }

    func isDownloaded(_ songID: String) -> Bool { index.songs[songID]?.userID == userID && index.songs[songID] != nil }
    func isQueued(_ songID: String) -> Bool { queue.contains { $0.id == songID } }
    func hasFailed(_ songID: String) -> Bool { failed.contains { $0.id == songID } }

    /// The saved file, to play instead of streaming.
    func localURL(for songID: String) -> URL? {
        guard let saved = index.songs[songID], saved.userID == userID else { return nil }
        let url = Self.folder.appendingPathComponent(saved.file)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private static func lyricsURL(_ songID: String) -> URL { folder.appendingPathComponent("\(songID).lyrics.json") }

    func hasLyrics(_ songID: String) -> Bool {
        localURL(for: songID) != nil && FileManager.default.fileExists(atPath: Self.lyricsURL(songID).path)
    }

    /// A downloaded song's lyrics, saved with it.
    func lyrics(for songID: String) -> Lyrics? {
        guard localURL(for: songID) != nil, let data = try? Data(contentsOf: Self.lyricsURL(songID)) else { return nil }
        return try? JSONDecoder().decode(Lyrics.self, from: data)
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
        let ids = Set(songs.map(\.id))
        failed.removeAll { ids.contains($0.id) }
        for song in songs where !isDownloaded(song.id) && !isQueued(song.id) {
            queue.append(song)
        }
        saveIndex()
        saveQueue()
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

    func retryFailed() { download(failed) }

    func download(album: MusicAlbum) {
        Task { download(await MusicActions.albumSongs(album), album: album) }
    }

    func remove(_ songs: [MusicSong]) {
        let ids = Set(songs.map(\.id))
        stop(ids)
        for id in ids {
            guard let saved = index.songs.removeValue(forKey: id) else { continue }
            try? FileManager.default.removeItem(at: Self.folder.appendingPathComponent(saved.file))
            try? FileManager.default.removeItem(at: Self.lyricsURL(id))
        }
        dropUnusedAlbums()
        saveIndex()
    }

    /// Stops songs that haven't finished; one halfway through is thrown away.
    func cancel(_ songs: [MusicSong]) {
        stop(Set(songs.map(\.id)))
    }

    func cancelAll() {
        stop(Set(queue.map(\.id) + failed.map(\.id)))
    }

    func removeAll() {
        cancelAll()
        remove(mine.map(\.song))
    }

    private func stop(_ ids: Set<String>) {
        queue.removeAll { ids.contains($0.id) }
        failed.removeAll { ids.contains($0.id) }
        for id in ids {
            transfers[id]?.cancel()
            resumeData[id] = nil
        }
        saveQueue()
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
            while let self, !queue.isEmpty {
                await waitUntilAllowed()
                let batch = Array(queue.prefix(Self.parallel))
                guard !batch.isEmpty else { break }
                let started = batch.map { song in
                    let transfer = Task { await self.download(song) }
                    self.transfers[song.id] = transfer
                    return transfer
                }
                for transfer in started where await transfer.value { saved += 1 }
            }
            self?.worker = nil
            if saved > 0, MusicSettings.notifiesDownloads {
                await NotificationManager.notifyMusicDownloaded(songs: saved)
            }
        }
    }

    /// Holds the queue while it's on mobile data that isn't allowed, there's no connection,
    /// or nobody's signed in yet.
    private func waitUntilAllowed() async {
        while !queue.isEmpty, !Task.isCancelled {
            let offline = !isOnline || AppServices.authManager.state.credential == nil
            let wifi = !offline && MusicSettings.downloadsWaitForWiFi
            isWaitingForNetwork = offline
            isWaitingForWiFi = wifi
            guard offline || wifi else { return }
            try? await Task.sleep(for: .seconds(3))
        }
        isWaitingForNetwork = false
        isWaitingForWiFi = false
    }

    /// A song, tried again after a dropped connection or a busy server until it's saved,
    /// cancelled or out of tries.
    private func download(_ song: MusicSong) async -> Bool {
        progress[song.id] = 0
        var outcome = Outcome.retry
        for attempt in 0..<Self.attempts {
            if attempt > 0 {
                try? await Task.sleep(for: .seconds(Self.backoff[attempt - 1]))
                await waitUntilAllowed()
                log.notice("Trying \(song.id, privacy: .public) again (\(attempt + 1, privacy: .public) of \(Self.attempts, privacy: .public))")
            }
            guard !Task.isCancelled, isQueued(song.id) else {
                outcome = .cancelled
                break
            }
            outcome = await fetch(song)
            if outcome != .retry { break }
        }
        progress[song.id] = nil
        transfers[song.id] = nil
        let wasQueued = isQueued(song.id)
        queue.removeAll { $0.id == song.id }
        if outcome != .saved { resumeData[song.id] = nil }
        if wasQueued, outcome == .retry || outcome == .failed, !hasFailed(song.id) { failed.append(song) }
        saveQueue()
        return outcome == .saved
    }

    private func fetch(_ song: MusicSong) async -> Outcome {
        guard let credential = AppServices.authManager.state.credential,
              let url = MusicAPI.client.audioStreamURL(credential: credential, deviceId: Self.deviceID, trackId: song.id,
                                                       container: song.container,
                                                       bitrateCap: MusicSettings.downloadBitrate) else { return .retry }
        let reporter = ProgressReporter { fraction in
            Task { @MainActor in MusicDownloads.shared.reportProgress(fraction, for: song.id) }
        }
        do {
            let (temp, response) = if let resume = resumeData.removeValue(forKey: song.id) {
                try await downloadSession.download(resumeFrom: resume, delegate: reporter)
            } else {
                try await downloadSession.download(from: url, delegate: reporter)
            }
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                try? FileManager.default.removeItem(at: temp)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                log.error("Couldn't save \(song.id, privacy: .public): the server answered \(status, privacy: .public)")
                return status >= 500 || status == 429 ? .retry : .failed
            }
            // Cancelled while it downloaded.
            guard isQueued(song.id) else {
                try? FileManager.default.removeItem(at: temp)
                return .cancelled
            }
            let file = "\(song.id).\(url.pathExtension)"
            let destination = Self.folder.appendingPathComponent(file)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: temp, to: destination)
            let bytes = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            index.songs[song.id] = Saved(song: song, file: file, userID: credential.userID, bytes: bytes, savedAt: .now)
            saveIndex()
            await saveCover(for: song)
            if let lyrics = await MusicLyricsSource.shared.lyricsToSave(for: song),
               let data = try? JSONEncoder().encode(lyrics) {
                try? data.write(to: Self.lyricsURL(song.id))
            }
            return .saved
        } catch let error as URLError {
            if error.code == .cancelled { return .cancelled }
            if let resume = error.downloadTaskResumeData { resumeData[song.id] = resume }
            log.error("Couldn't save \(song.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return Self.retryable.contains(error.code) ? .retry : .failed
        } catch {
            if error is CancellationError { return .cancelled }
            log.error("Couldn't save \(song.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return .failed
        }
    }

    /// Its own session: the shared one gives a whole request 30 seconds, which a long song on
    /// a slow connection doesn't fit in.
    private var downloadSession: URLSession {
        let headers = CustomHTTPHeaders.current
        if let session, session.headers == headers { return session.session }
        session?.session.finishTasksAndInvalidate()
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 60 * 60
        config.httpAdditionalHeaders = headers.isEmpty ? nil : headers
        let made = URLSession(configuration: config)
        session = (headers, made)
        return made
    }

    private func reportProgress(_ fraction: Double, for songID: String) {
        guard progress[songID] != nil else { return }
        progress[songID] = fraction
    }

    private func saveCover(for song: MusicSong) async {
        guard let albumID = song.albumId, coverURL(albumID: albumID) == nil,
              let url = MusicAPI.artworkURL(song, width: 600),
              let data = await URLSession.arcfin.imageData(from: url) else { return }
        try? data.write(to: Self.folder.appendingPathComponent("\(albumID).jpg"))
    }

    private func saveQueue() {
        guard let data = try? JSONEncoder().encode(Pending(queue: queue, failed: failed)) else { return }
        try? data.write(to: Self.pendingURL, options: .atomic)
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
