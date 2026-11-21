// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import AuthCore

/// A command another client sent to this device through Jellyfin: the web app's "Play On",
/// or the dashboard's controls.
public enum JellyfinRemoteCommand: Sendable, Equatable {
    /// Play these titles now, from the one at `startIndex`.
    case play(itemIds: [String], startPositionTicks: Int64?, startIndex: Int? = nil)
    /// Play Next (`next`) or Play Last: add these to what's playing.
    case queue(itemIds: [String], next: Bool)
    case playstate(Playstate, seekPositionTicks: Int64?)
    /// `name` is Jellyfin's GeneralCommandType; argument values always arrive as strings.
    case general(name: String, arguments: [String: String])

    public enum Playstate: String, Sendable {
        case stop = "Stop", pause = "Pause", unpause = "Unpause", playPause = "PlayPause"
        case seek = "Seek", nextTrack = "NextTrack", previousTrack = "PreviousTrack"
        case rewind = "Rewind", fastForward = "FastForward"
    }

    /// The general commands Arcfin carries out, posted with its capabilities.
    public static let supportedGeneralCommands = [
        "DisplayMessage", "DisplayContent", "SetVolume", "VolumeUp", "VolumeDown",
        "Mute", "Unmute", "ToggleMute", "SetAudioStreamIndex", "SetSubtitleStreamIndex",
    ]

    /// A WebSocket message of type Play, Playstate or GeneralCommand; nil for anything else.
    public static func parse(messageType: String, json: Data) -> JellyfinRemoteCommand? {
        let decoder = JSONDecoder()
        switch messageType {
        case "Play":
            guard let data = (try? decoder.decode(Envelope<PlayData>.self, from: json))?.data,
                  let ids = data.itemIds, !ids.isEmpty
            else { return nil }
            switch data.playCommand {
            case nil, "PlayNow":
                return .play(itemIds: ids, startPositionTicks: data.startPositionTicks, startIndex: data.startIndex)
            case "PlayNext": return .queue(itemIds: ids, next: true)
            case "PlayLast": return .queue(itemIds: ids, next: false)
            default: return nil
            }
        case "Playstate":
            guard let data = (try? decoder.decode(Envelope<PlaystateData>.self, from: json))?.data,
                  let command = Playstate(rawValue: data.command)
            else { return nil }
            return .playstate(command, seekPositionTicks: data.seekPositionTicks)
        case "GeneralCommand":
            guard let data = (try? decoder.decode(Envelope<GeneralData>.self, from: json))?.data else { return nil }
            return .general(name: data.name, arguments: data.arguments ?? [:])
        default:
            return nil
        }
    }

    private struct Envelope<Payload: Decodable>: Decodable {
        let data: Payload?
        enum CodingKeys: String, CodingKey { case data = "Data" }
    }

    private struct PlayData: Decodable {
        let itemIds: [String]?
        let startPositionTicks: Int64?
        let startIndex: Int?
        let playCommand: String?
        enum CodingKeys: String, CodingKey {
            case itemIds = "ItemIds", startPositionTicks = "StartPositionTicks", playCommand = "PlayCommand"
            case startIndex = "StartIndex"
        }
    }

    private struct PlaystateData: Decodable {
        let command: String
        let seekPositionTicks: Int64?
        enum CodingKeys: String, CodingKey { case command = "Command", seekPositionTicks = "SeekPositionTicks" }
    }

    private struct GeneralData: Decodable {
        let name: String
        let arguments: [String: String]?
        enum CodingKeys: String, CodingKey { case name = "Name", arguments = "Arguments" }
    }
}

extension JellyfinMediaClient {
    /// POST /Sessions/Capabilities/Full: tells the server this device can be controlled, so
    /// the web app offers it in "Play On" and the dashboard's controls reach it.
    public func postRemoteControlCapabilities(credential: ServerCredential, authHeader: String) async {
        var req = URLRequest(url: credential.baseURL.appendingPathComponent("Sessions/Capabilities/Full"))
        req.httpMethod = "POST"
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 10
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "PlayableMediaTypes": ["Video", "Audio"],
            "SupportedCommands": JellyfinRemoteCommand.supportedGeneralCommands,
            "SupportsMediaControl": true,
            "SupportsPersistentIdentifier": true,
        ] as [String: Any])
        _ = try? await URLSession.arcfin.data(for: req)
    }
}

// MARK: - Controlling another device (#457)

extension JellyfinMediaClient {
    /// The sessions this profile can control: its own on other devices, and any that let it.
    public func controllableSessions(credential: ServerCredential, authHeader: String) async throws -> [JellyfinSession] {
        var comps = URLComponents(url: credential.baseURL.appendingPathComponent("Sessions"), resolvingAgainstBaseURL: false)
        comps?.queryItems = [
            .init(name: "controllableByUserId", value: credential.userID),
            .init(name: "activeWithinSeconds", value: "960"),
        ]
        guard let url = comps?.url else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 10
        let (data, resp) = try await URLSession.arcfin.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode([SessionResponse].self, from: data).map { $0.toSession() }
    }

    /// POST /Sessions/{id}/Playing/{command}: Pause, Unpause, PlayPause, Stop, Seek,
    /// NextTrack, PreviousTrack, Rewind, FastForward.
    public func sendPlaystate(_ command: JellyfinRemoteCommand.Playstate, seekTicks: Int64? = nil, sessionId: String,
                              credential: ServerCredential, authHeader: String) async {
        var comps = URLComponents(url: credential.baseURL.appendingPathComponent("Sessions/\(sessionId)/Playing/\(command.rawValue)"),
                                  resolvingAgainstBaseURL: false)
        if let seekTicks { comps?.queryItems = [.init(name: "seekPositionTicks", value: String(seekTicks))] }
        guard let url = comps?.url else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 10
        _ = try? await URLSession.arcfin.data(for: req)
    }

    /// POST /Sessions/{id}/Command: SetVolume, Mute, Unmute, SetAudioStreamIndex,
    /// SetSubtitleStreamIndex and the like. Argument values are strings, as Jellyfin expects.
    public func sendGeneralCommand(_ name: String, arguments: [String: String] = [:], sessionId: String,
                                   credential: ServerCredential, authHeader: String) async {
        var req = URLRequest(url: credential.baseURL.appendingPathComponent("Sessions/\(sessionId)/Command"))
        req.httpMethod = "POST"
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 10
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["Name": name, "Arguments": arguments] as [String: Any])
        _ = try? await URLSession.arcfin.data(for: req)
    }

    /// POST /Sessions/{id}/Playing: plays these titles on that device now.
    public func play(itemIds: [String], startTicks: Int64?, sessionId: String,
                     credential: ServerCredential, authHeader: String) async throws {
        var comps = URLComponents(url: credential.baseURL.appendingPathComponent("Sessions/\(sessionId)/Playing"),
                                  resolvingAgainstBaseURL: false)
        var items: [URLQueryItem] = [
            .init(name: "playCommand", value: "PlayNow"),
            .init(name: "itemIds", value: itemIds.joined(separator: ",")),
        ]
        if let startTicks, startTicks > 0 { items.append(.init(name: "startPositionTicks", value: String(startTicks))) }
        comps?.queryItems = items
        guard let url = comps?.url else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(authHeader, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 10
        let (_, resp) = try await URLSession.arcfin.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}
