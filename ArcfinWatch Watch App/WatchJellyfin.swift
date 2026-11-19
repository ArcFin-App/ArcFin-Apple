// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Network

/// One device playing on this profile, from GET /Sessions.
struct WatchSession: Identifiable, Equatable, Sendable {
    struct Track: Identifiable, Equatable, Sendable {
        let index: Int
        let title: String
        var id: Int { index }
    }

    let id: String
    let deviceName: String
    let itemID: String
    /// The album's, for a song: songs rarely have art of their own.
    let artworkItemID: String
    let title: String
    let subtitle: String?
    let isPaused: Bool
    let positionTicks: Int64
    let runTimeTicks: Int64
    let volumeLevel: Int?
    let isMuted: Bool
    let audioIndex: Int?
    let subtitleIndex: Int?
    let audioTracks: [Track]
    let subtitleTracks: [Track]
}

/// The few Jellyfin calls the remote makes. The watch can't link the app's JellyfinAPI
/// package (it imports VideoToolbox), so these are its own.
struct WatchJellyfin: Sendable {
    let credential: WatchCredential

    /// Waits for the network, so a request at launch doesn't fail before the watch's
    /// connection (often through the iPhone) is up.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForResource = 30
        return URLSession(configuration: configuration)
    }()

    /// The address that answered last, tried first next time: the watch may be at home or away.
    @MainActor private static var lastWorking: URL?

    func playingSessions() async throws -> [WatchSession] {
        await Self.waitForNetwork()
        let (data, response) = try await send { server in
            var comps = URLComponents(url: server.appendingPathComponent("Sessions"), resolvingAgainstBaseURL: false)
            comps?.queryItems = [
                .init(name: "controllableByUserId", value: credential.userID),
                .init(name: "activeWithinSeconds", value: "960"),
            ]
            return comps?.url.map { URLRequest(url: $0) }
        }
        guard (200...299).contains(response.statusCode) else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode([SessionResponse].self, from: data).compactMap(\.session)
    }

    /// POST /Sessions/{id}/Playing/{command}: PlayPause, Stop, Seek, NextTrack, PreviousTrack.
    func playstate(_ command: String, seekTicks: Int64? = nil, sessionID: String) async {
        _ = try? await send(method: "POST") { server in
            var comps = URLComponents(url: server.appendingPathComponent("Sessions/\(sessionID)/Playing/\(command)"),
                                      resolvingAgainstBaseURL: false)
            if let seekTicks { comps?.queryItems = [.init(name: "seekPositionTicks", value: String(seekTicks))] }
            return comps?.url.map { URLRequest(url: $0) }
        }
    }

    /// POST /Sessions/{id}/Command: SetVolume, ToggleMute, SetAudioStreamIndex, SetSubtitleStreamIndex.
    func command(_ name: String, arguments: [String: String] = [:], sessionID: String) async {
        let body = try? JSONSerialization.data(withJSONObject: ["Name": name, "Arguments": arguments] as [String: Any])
        _ = try? await send(method: "POST") { server in
            var request = URLRequest(url: server.appendingPathComponent("Sessions/\(sessionID)/Command"))
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
            return request
        }
    }

    func artworkURL(itemID: String) -> URL? {
        guard let server = Self.lastWorking ?? credential.serverURLs.first,
              var comps = URLComponents(url: server.appendingPathComponent("Items/\(itemID)/Images/Primary"),
                                        resolvingAgainstBaseURL: false) else { return nil }
        comps.queryItems = [.init(name: "fillWidth", value: "200"), .init(name: "api_key", value: credential.accessToken)]
        return comps.url
    }

    /// Tries the address that worked last, then the others, until one answers at all. An
    /// answer of any status counts: it's the server, so another address won't do better.
    private func send(method: String = "GET", _ build: (URL) -> URLRequest?) async throws -> (Data, HTTPURLResponse) {
        let preferred = Self.lastWorking.flatMap { credential.serverURLs.contains($0) ? $0 : nil }
        let servers = (preferred.map { [$0] } ?? []) + credential.serverURLs.filter { $0 != preferred }
        var lastError: any Error = URLError(.cannotConnectToHost)
        for server in servers {
            guard var request = build(server) else { continue }
            request.httpMethod = method
            request.setValue(credential.authHeader, forHTTPHeaderField: "Authorization")
            // Short, so an address that can't be reached from here gives way quickly.
            request.timeoutInterval = servers.count > 1 ? 5 : 10
            do {
                let (data, response) = try await Self.session.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
                Self.lastWorking = server
                return (data, http)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    /// waitsForConnectivity alone still lets a request made before the path is known fail at
    /// once; a short wait for a satisfied path first covers that.
    nonisolated private static func waitForNetwork() async {
        let monitor = NWPathMonitor()
        let satisfied = AsyncStream<Void> { continuation in
            monitor.pathUpdateHandler = { path in
                if path.status == .satisfied { continuation.yield() }
            }
            continuation.onTermination = { _ in monitor.cancel() }
            monitor.start(queue: DispatchQueue(label: "arcfin.watch.pathwait"))
        }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { for await _ in satisfied { return } }
            group.addTask { try? await Task.sleep(for: .seconds(3)) }
            await group.next()
            group.cancelAll()
        }
    }
}

private struct SessionResponse: Decodable {
    struct Item: Decodable {
        struct Stream: Decodable {
            let index: Int?
            let type: String?
            let displayTitle: String?
            let language: String?
            enum CodingKeys: String, CodingKey {
                case index = "Index", type = "Type", displayTitle = "DisplayTitle", language = "Language"
            }
        }
        let id: String?
        let name: String?
        let runTimeTicks: Int64?
        let seriesName: String?
        let indexNumber: Int?
        let parentIndexNumber: Int?
        let mediaStreams: [Stream]?
        let type: String?
        let albumId: String?
        let album: String?
        let artists: [String]?
        let albumArtist: String?
        enum CodingKeys: String, CodingKey {
            case id = "Id", name = "Name", runTimeTicks = "RunTimeTicks", seriesName = "SeriesName"
            case indexNumber = "IndexNumber", parentIndexNumber = "ParentIndexNumber", mediaStreams = "MediaStreams"
            case type = "Type", albumId = "AlbumId", album = "Album", artists = "Artists", albumArtist = "AlbumArtist"
        }
    }
    struct PlayState: Decodable {
        let isPaused: Bool?
        let positionTicks: Int64?
        let volumeLevel: Int?
        let isMuted: Bool?
        let audioStreamIndex: Int?
        let subtitleStreamIndex: Int?
        enum CodingKeys: String, CodingKey {
            case isPaused = "IsPaused", positionTicks = "PositionTicks", volumeLevel = "VolumeLevel"
            case isMuted = "IsMuted", audioStreamIndex = "AudioStreamIndex", subtitleStreamIndex = "SubtitleStreamIndex"
        }
    }
    let id: String
    let deviceName: String?
    let nowPlayingItem: Item?
    let playState: PlayState?
    let supportsRemoteControl: Bool?
    enum CodingKeys: String, CodingKey {
        case id = "Id", deviceName = "DeviceName", nowPlayingItem = "NowPlayingItem"
        case playState = "PlayState", supportsRemoteControl = "SupportsRemoteControl"
    }

    /// Only devices playing something that take commands.
    var session: WatchSession? {
        guard supportsRemoteControl == true, let item = nowPlayingItem, let itemID = item.id else { return nil }
        let isSong = item.type == "Audio"
        let subtitle: String?
        if isSong {
            let artist = item.artists.flatMap { $0.isEmpty ? nil : $0.joined(separator: ", ") } ?? item.albumArtist
            subtitle = artist ?? item.album
        } else {
            let episode = item.indexNumber.map { number in item.parentIndexNumber.map { "S\($0) E\(number)" } ?? "E\(number)" }
            subtitle = item.seriesName.map { [$0, episode].compactMap { $0 }.joined(separator: " · ") }
        }
        return WatchSession(
            id: id, deviceName: deviceName ?? "", itemID: itemID,
            artworkItemID: isSong ? item.albumId ?? itemID : itemID, title: item.name ?? "", subtitle: subtitle,
            isPaused: playState?.isPaused ?? false, positionTicks: playState?.positionTicks ?? 0,
            runTimeTicks: item.runTimeTicks ?? 0, volumeLevel: playState?.volumeLevel,
            isMuted: playState?.isMuted ?? false, audioIndex: playState?.audioStreamIndex,
            subtitleIndex: playState?.subtitleStreamIndex,
            audioTracks: Self.tracks(item.mediaStreams, type: "Audio"),
            subtitleTracks: Self.tracks(item.mediaStreams, type: "Subtitle"))
    }

    private static func tracks(_ streams: [Item.Stream]?, type: String) -> [WatchSession.Track] {
        (streams ?? []).compactMap { stream in
            guard stream.type == type, let index = stream.index else { return nil }
            return WatchSession.Track(index: index, title: stream.displayTitle ?? stream.language ?? "\(type) \(index)")
        }
    }
}

// MARK: - Music on the watch

struct WatchPlaylist: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let songCount: Int?
}

struct WatchSong: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let artist: String?
    let albumID: String?
    let seconds: Double?
}

private struct WatchItemsResponse: Decodable {
    struct Item: Decodable {
        let id: String
        let name: String?
        let albumId: String?
        let artists: [String]?
        let albumArtist: String?
        let runTimeTicks: Int64?
        let childCount: Int?
        enum CodingKeys: String, CodingKey {
            case id = "Id", name = "Name", albumId = "AlbumId", artists = "Artists", albumArtist = "AlbumArtist"
            case runTimeTicks = "RunTimeTicks", childCount = "ChildCount"
        }
    }
    let items: [Item]
    enum CodingKeys: String, CodingKey { case items = "Items" }
}

extension WatchJellyfin {
    func playlists() async throws -> [WatchPlaylist] {
        try await items("Users/\(credential.userID)/Items", [
            .init(name: "IncludeItemTypes", value: "Playlist"), .init(name: "MediaTypes", value: "Audio"),
            .init(name: "Recursive", value: "true"), .init(name: "SortBy", value: "SortName"),
        ]).map { WatchPlaylist(id: $0.id, name: $0.name ?? "", songCount: $0.childCount) }
    }

    func songs(inPlaylist id: String) async throws -> [WatchSong] {
        try await items("Playlists/\(id)/Items", [.init(name: "UserId", value: credential.userID)]).map(Self.song)
    }

    /// The profile's favourite songs, shuffled.
    func favoriteSongs() async throws -> [WatchSong] {
        try await items("Users/\(credential.userID)/Items", [
            .init(name: "IncludeItemTypes", value: "Audio"), .init(name: "Recursive", value: "true"),
            .init(name: "Filters", value: "IsFavorite"), .init(name: "SortBy", value: "Random"),
            .init(name: "Limit", value: "100"),
        ]).map(Self.song)
    }

    private static func song(_ item: WatchItemsResponse.Item) -> WatchSong {
        WatchSong(id: item.id, name: item.name ?? "", artist: item.artists?.first ?? item.albumArtist,
                  albumID: item.albumId, seconds: item.runTimeTicks.map { Double($0) / 10_000_000 })
    }

    private func items(_ path: String, _ query: [URLQueryItem]) async throws -> [WatchItemsResponse.Item] {
        await Self.waitForNetwork()
        let (data, response) = try await send { server in
            var comps = URLComponents(url: server.appendingPathComponent(path), resolvingAgainstBaseURL: false)
            comps?.queryItems = query
            return comps?.url.map { URLRequest(url: $0) }
        }
        guard (200...299).contains(response.statusCode) else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(WatchItemsResponse.self, from: data).items
    }

    /// The song converted to 192 kbps MP3, which the watch plays and keeps small.
    func streamURL(songID: String) -> URL? {
        guard let server = Self.lastWorking ?? credential.serverURLs.first,
              var comps = URLComponents(url: server.appendingPathComponent("Audio/\(songID)/stream.mp3"),
                                        resolvingAgainstBaseURL: false) else { return nil }
        comps.queryItems = [
            .init(name: "audioCodec", value: "mp3"), .init(name: "audioBitRate", value: "192000"),
            .init(name: "api_key", value: credential.accessToken),
        ]
        return comps.url
    }
}
