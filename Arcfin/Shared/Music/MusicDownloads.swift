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
/// profile. Two download at a time while the app is open, and the rest go to the system as it
/// leaves the foreground, so they carry on in the background. The queue is kept across
/// launches, waits out a lost connection, and a song that keeps failing waits for Retry.
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
    /// Bytes so far and in all for each song downloading now, for the Live Activity.
    @ObservationIgnored private var bytes: [String: (written: Int64, total: Int64, since: Date)] = [:]
    /// This run of the queue: how many are done, for "2 of 6".
    @ObservationIgnored private var runSaved = 0
    /// Saved in this run of the queue: the storage limit leaves them alone until it's done.
    @ObservationIgnored private var savedThisRun: Set<String> = []
    @ObservationIgnored private var lastActivityUpdate = Date.distantPast
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
        MusicTransfers.shared.connect { finished in
            Task { @MainActor in await MusicDownloads.shared.claim(finished) }
        }
        if queue.isEmpty { MusicDownloadActivity.endStale() }
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

    /// Every album the artist made, each kept with its name and cover as an album's own
    /// Download does.
    func download(artist: MusicArtist) async {
        var start = 0
        while true {
            guard let page = try? await MusicAPI.call({
                try await $0.getMusicAlbums(credential: $1, authHeader: $2, libraryId: nil, sort: .year,
                                            ascending: false, filter: MusicFilter(artistId: artist.id), startIndex: start)
            }) else { return }
            for album in page.albums { download(await MusicActions.albumSongs(album), album: album) }
            start += page.albums.count
            if page.albums.isEmpty || start >= page.total { return }
        }
    }

    /// The saved songs from these albums.
    func savedSongs(inAlbums ids: Set<String>) -> [MusicSong] {
        mine.map(\.song).filter { $0.albumId.map(ids.contains) ?? false }
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
        runSaved = 0
        savedThisRun = []
        worker = Task { [weak self] in
            var saved = 0
            while let self, !queue.isEmpty {
                await waitUntilAllowed()
                refreshActivity(force: true)
                let batch = Array(queue.prefix(Self.parallel))
                guard !batch.isEmpty else { break }
                let started = batch.map { song in
                    let transfer = Task { await self.download(song) }
                    self.transfers[song.id] = transfer
                    return transfer
                }
                for transfer in started where await transfer.value { saved += 1 }
            }
            if saved > 0 { MusicDownloadActivity.finish(count: saved) } else { MusicDownloadActivity.end() }
            self?.worker = nil
            await self?.enforceStorageLimit()
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
            if isWaitingForNetwork != offline || isWaitingForWiFi != wifi {
                isWaitingForNetwork = offline
                isWaitingForWiFi = wifi
                refreshActivity(force: true)
            }
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
        bytes[song.id] = nil
        transfers[song.id] = nil
        if outcome == .saved { runSaved += 1 }
        let wasQueued = isQueued(song.id)
        queue.removeAll { $0.id == song.id }
        if outcome != .saved { resumeData[song.id] = nil }
        if wasQueued, outcome == .retry || outcome == .failed, !hasFailed(song.id) { failed.append(song) }
        saveQueue()
        return outcome == .saved
    }

    private func fetch(_ song: MusicSong) async -> Outcome {
        guard let credential = AppServices.authManager.state.credential, let request = request(for: song, credential) else {
            return .retry
        }
        let id = song.id
        bytes[id] = (0, 0, .now)
        refreshActivity(force: true)
        let finished = await MusicTransfers.shared.download(request, songID: id, resumeData: resumeData.removeValue(forKey: id)) { written, total in
            Task { @MainActor in MusicDownloads.shared.reportProgress(written: written, total: total, for: id) }
        }
        if let error = finished.error {
            if error.code == .cancelled { return .cancelled }
            if let resume = error.downloadTaskResumeData { resumeData[id] = resume }
            log.error("Couldn't save \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return Self.retryable.contains(error.code) ? .retry : .failed
        }
        guard let file = finished.file, (200...299).contains(finished.status) else {
            finished.file.map { try? FileManager.default.removeItem(at: $0) }
            log.error("Couldn't save \(id, privacy: .public): the server answered \(finished.status, privacy: .public)")
            return finished.status >= 500 || finished.status == 429 ? .retry : .failed
        }
        // Cancelled while it downloaded.
        guard isQueued(id) else {
            try? FileManager.default.removeItem(at: file)
            return .cancelled
        }
        return await keep(song, file: file, fileExtension: finished.fileExtension, userID: credential.userID) ? .saved : .failed
    }

    private func request(for song: MusicSong, _ credential: ServerCredential) -> URLRequest? {
        guard let url = MusicAPI.client.audioStreamURL(credential: credential, deviceId: Self.deviceID, trackId: song.id,
                                                       container: song.container,
                                                       bitrateCap: MusicSettings.downloadBitrate) else { return nil }
        var request = URLRequest(url: url)
        for (name, value) in CustomHTTPHeaders.current { request.setValue(value, forHTTPHeaderField: name) }
        // The system carries on with it in the background, where the Wi-Fi check can't run.
        if !UserDefaults.standard.bool(forKey: MusicSettings.downloadOnMobileDataKey) {
            request.allowsCellularAccess = false
            request.allowsExpensiveNetworkAccess = false
        }
        return request
    }

    /// Moves a downloaded file into place with the song's cover and lyrics.
    private func keep(_ song: MusicSong, file: URL, fileExtension: String, userID: String) async -> Bool {
        let name = "\(song.id).\(fileExtension)"
        let destination = Self.folder.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.moveItem(at: file, to: destination)
        } catch {
            log.error("Couldn't save \(song.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
        let size = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        index.songs[song.id] = Saved(song: song, file: name, userID: userID, bytes: size, savedAt: .now)
        saveIndex()
        savedThisRun.insert(song.id)
        await saveCover(for: song)
        if let lyrics = await MusicLyricsSource.shared.lyricsToSave(for: song),
           let data = try? JSONEncoder().encode(lyrics) {
            try? data.write(to: Self.lyricsURL(song.id))
        }
        return true
    }

    /// A song that finished with nothing waiting for it: handed over in the background, or
    /// from before the app was closed.
    private func claim(_ finished: MusicTransfers.Finished) async {
        guard let file = finished.file else { return }
        // At launch the profile is still being read.
        for _ in 0..<30 where userID == nil { try? await Task.sleep(for: .seconds(1)) }
        guard (200...299).contains(finished.status), let song = queue.first(where: { $0.id == finished.songID }),
              let userID = userID else {
            try? FileManager.default.removeItem(at: file)
            return
        }
        guard await keep(song, file: file, fileExtension: finished.fileExtension, userID: userID) else { return }
        log.notice("Saved \(song.id, privacy: .public), downloaded in the background")
        if worker == nil { await enforceStorageLimit() }
        queue.removeAll { $0.id == song.id }
        runSaved += 1
        saveQueue()
        refreshActivity(force: true)
    }

    /// Leaving the foreground: every song still waiting goes to the system to download, so
    /// the queue carries on while the app is suspended.
    func handOff() {
        guard !queue.isEmpty, isOnline, !MusicSettings.downloadsWaitForWiFi,
              let credential = AppServices.authManager.state.credential else { return }
        for song in queue where progress[song.id] == nil {
            if let request = request(for: song, credential) { MusicTransfers.shared.handOff(request, songID: song.id) }
        }
    }

    // MARK: Smart downloads

    private static let recentKey = "music.autoRecent"
    private static let seenAlbumsKey = "music.seenNewAlbums"
    @ObservationIgnored private var lastSmartRefresh = Date.distantPast

    /// Songs downloaded because they were played lately, so they can go once they aren't.
    private var keptRecent: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: Self.recentKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: Self.recentKey) }
    }

    /// Keep Recently Played and New Albums from Favorite Artists, at most every half hour
    /// unless a setting just changed.
    func refreshSmartDownloads(force: Bool = false) async {
        guard force || Date.now.timeIntervalSince(lastSmartRefresh) > 30 * 60,
              AppServices.authManager.state.credential != nil, PlatformStorage.keepsMusicDownloads else { return }
        lastSmartRefresh = .now
        await keepRecentlyPlayed()
        if MusicSettings.downloadsNewAlbums { await downloadNewAlbums() }
        if worker == nil { await enforceStorageLimit() }
    }

    private func keepRecentlyPlayed() async {
        let count = MusicSettings.keepRecentCount
        var recent: [MusicSong] = []
        if count > 0 {
            guard let page = try? await MusicAPI.call({
                try await $0.getMusicTracks(credential: $1, authHeader: $2, libraryId: nil, sort: .datePlayed,
                                            ascending: false, filter: .init(playedOnly: true), limit: count)
            }) else { return }
            recent = page.tracks
        }
        let wanted = Set(recent.map(\.id))
        // Ones that dropped off the list go, unless they're favorites.
        let dropped = keptRecent.subtracting(wanted).compactMap { index.songs[$0]?.song }
            .filter { !MusicFavorites.shared.isFavorite($0.id, server: $0.isFavorite) }
        if !dropped.isEmpty { remove(dropped) }
        let missing = recent.filter { !isDownloaded($0.id) && !isQueued($0.id) }
        keptRecent = keptRecent.intersection(wanted).union(missing.map(\.id))
        if !missing.isEmpty { download(missing) }
    }

    /// Albums by favorite artists that weren't there the last time it looked. The first look
    /// only notes what's there, so turning it on doesn't download every album they have.
    private func downloadNewAlbums() async {
        guard let artists = try? await MusicAPI.call({
            try await $0.getMusicArtists(credential: $1, authHeader: $2, libraryId: nil, filter: .init(favoritesOnly: true), limit: 200)
        }).artists, !artists.isEmpty else { return }
        let ids = artists.map(\.id).joined(separator: ",")
        guard let albums = try? await MusicAPI.call({
            try await $0.getMusicAlbums(credential: $1, authHeader: $2, libraryId: nil, sort: .dateAdded, ascending: false,
                                        filter: MusicFilter(artistId: ids), limit: 50)
        }).albums else { return }
        let defaults = UserDefaults.standard
        let firstLook = defaults.object(forKey: Self.seenAlbumsKey) == nil
        var seen = Set(defaults.stringArray(forKey: Self.seenAlbumsKey) ?? [])
        for album in albums where !seen.contains(album.id) {
            seen.insert(album.id)
            if !firstLook { download(await MusicActions.albumSongs(album), album: album) }
        }
        defaults.set(Array(seen), forKey: Self.seenAlbumsKey)
    }

    /// Over Storage Limit: the least played songs go first, oldest first among equals.
    /// Favorites, the recently played ones being kept and what's downloading now stay. Play
    /// counts and favorites come fresh from the server, since a saved song's are as they
    /// were when it downloaded; without the server nothing is removed.
    func enforceStorageLimit() async {
        guard let limit = MusicSettings.storageLimitBytes, totalBytes > limit else { return }
        let ids = mine.map(\.song.id)
        var fresh: [String: MusicSong] = [:]
        for start in stride(from: 0, to: ids.count, by: 200) {
            let chunk = Array(ids[start..<min(start + 200, ids.count)])
            let answer = try? await MusicAPI.call { try await $0.getSongs(credential: $1, authHeader: $2, ids: chunk) }
            guard let songs = answer ?? nil else { return }
            for song in songs { fresh[song.id] = song }
        }
        var total = totalBytes
        guard total > limit else { return }
        let protected = keptRecent.union(savedThisRun).union(queue.map(\.id))
        let candidates = mine
            .map { (saved: $0, song: fresh[$0.song.id] ?? $0.song) }
            .filter { !protected.contains($0.song.id) && !MusicFavorites.shared.isFavorite($0.song.id, server: $0.song.isFavorite) }
            .sorted { ($0.song.playCount, $0.saved.savedAt) < ($1.song.playCount, $1.saved.savedAt) }
            .map(\.saved)
        var removing: [MusicSong] = []
        for saved in candidates where total > limit {
            removing.append(saved.song)
            total -= saved.bytes
        }
        guard !removing.isEmpty else { return }
        log.notice("Over the storage limit: removing \(removing.count, privacy: .public) songs")
        remove(removing)
    }

    // MARK: Live Activity

    private func refreshActivity(force: Bool = false) {
        guard force || Date.now.timeIntervalSince(lastActivityUpdate) >= 1 else { return }
        lastActivityUpdate = .now
        guard let song = queue.first(where: { progress[$0.id] != nil }) ?? queue.first else { return }
        let transfer = bytes[song.id]
        let elapsed = transfer.map { Date.now.timeIntervalSince($0.since) } ?? 0
        let speed = elapsed > 1 ? Double(transfer?.written ?? 0) / elapsed : 0
        MusicDownloadActivity.update(
            .init(title: song.name, artist: song.artistLine, next: queue.first { $0.id != song.id }?.name,
                  written: transfer?.written ?? 0, total: transfer?.total ?? 0, bytesPerSecond: speed,
                  saved: runSaved, count: runSaved + queue.count,
                  waitingForWiFi: isWaitingForWiFi, waitingForNetwork: isWaitingForNetwork,
                  coverURL: MusicAPI.artworkURL(song, width: 120), albumID: song.albumId))
    }

    private func reportProgress(written: Int64, total: Int64, for songID: String) {
        guard progress[songID] != nil else { return }
        if total > 0 { progress[songID] = Double(written) / Double(total) }
        bytes[songID] = (written, max(total, 0), bytes[songID]?.since ?? .now)
        refreshActivity()
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
