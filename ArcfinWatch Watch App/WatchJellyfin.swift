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
        configuration.timeoutIntervalForResource = 20
        return URLSession(configuration: configuration)
    }()

    func playingSessions() async throws -> [WatchSession] {
        await Self.waitForNetwork()
        var comps = URLComponents(url: credential.serverURL.appendingPathComponent("Sessions"), resolvingAgainstBaseURL: false)
        comps?.queryItems = [
            .init(name: "controllableByUserId", value: credential.userID),
            .init(name: "activeWithinSeconds", value: "960"),
        ]
        guard let url = comps?.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue(credential.authHeader, forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10
        let (data, response) = try await Self.session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode([SessionResponse].self, from: data).compactMap(\.session)
    }

    /// POST /Sessions/{id}/Playing/{command}: PlayPause, Stop, Seek, NextTrack, PreviousTrack.
    func playstate(_ command: String, seekTicks: Int64? = nil, sessionID: String) async {
        var comps = URLComponents(url: credential.serverURL.appendingPathComponent("Sessions/\(sessionID)/Playing/\(command)"),
                                  resolvingAgainstBaseURL: false)
        if let seekTicks { comps?.queryItems = [.init(name: "seekPositionTicks", value: String(seekTicks))] }
        guard let url = comps?.url else { return }
        await post(URLRequest(url: url))
    }

    /// POST /Sessions/{id}/Command: SetVolume, ToggleMute, SetAudioStreamIndex, SetSubtitleStreamIndex.
    func command(_ name: String, arguments: [String: String] = [:], sessionID: String) async {
        var request = URLRequest(url: credential.serverURL.appendingPathComponent("Sessions/\(sessionID)/Command"))
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["Name": name, "Arguments": arguments] as [String: Any])
        await post(request)
    }

    func artworkURL(itemID: String) -> URL? {
        var comps = URLComponents(url: credential.serverURL.appendingPathComponent("Items/\(itemID)/Images/Primary"),
                                  resolvingAgainstBaseURL: false)
        comps?.queryItems = [.init(name: "fillWidth", value: "200"), .init(name: "api_key", value: credential.accessToken)]
        return comps?.url
    }

    private func post(_ request: URLRequest) async {
        var request = request
        request.httpMethod = "POST"
        request.setValue(credential.authHeader, forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10
        _ = try? await Self.session.data(for: request)
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
        enum CodingKeys: String, CodingKey {
            case id = "Id", name = "Name", runTimeTicks = "RunTimeTicks", seriesName = "SeriesName"
            case indexNumber = "IndexNumber", parentIndexNumber = "ParentIndexNumber", mediaStreams = "MediaStreams"
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
        let episode = item.indexNumber.map { number in item.parentIndexNumber.map { "S\($0) E\(number)" } ?? "E\(number)" }
        let subtitle = item.seriesName.map { [$0, episode].compactMap { $0 }.joined(separator: " · ") }
        return WatchSession(
            id: id, deviceName: deviceName ?? "", itemID: itemID, title: item.name ?? "", subtitle: subtitle,
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
