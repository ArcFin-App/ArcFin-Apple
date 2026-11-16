// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import AuthCore

/// A command another client sent to this device through Jellyfin: the web app's "Play On",
/// or the dashboard's controls.
public enum JellyfinRemoteCommand: Sendable, Equatable {
    /// Play these titles now. Queue commands (Play Next, Play Last…) aren't modeled.
    case play(itemIds: [String], startPositionTicks: Int64?)
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
                  data.playCommand == nil || data.playCommand == "PlayNow",
                  let ids = data.itemIds, !ids.isEmpty
            else { return nil }
            return .play(itemIds: ids, startPositionTicks: data.startPositionTicks)
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
        let playCommand: String?
        enum CodingKeys: String, CodingKey {
            case itemIds = "ItemIds", startPositionTicks = "StartPositionTicks", playCommand = "PlayCommand"
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
            "PlayableMediaTypes": ["Video"],
            "SupportedCommands": JellyfinRemoteCommand.supportedGeneralCommands,
            "SupportsMediaControl": true,
            "SupportsPersistentIdentifier": true,
        ] as [String: Any])
        _ = try? await URLSession.arcfin.data(for: req)
    }
}
