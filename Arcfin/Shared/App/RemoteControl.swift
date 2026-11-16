// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Observation
import JellyfinAPI

/// Carries out what the web app and the dashboard send this device: Play On, the playback
/// controls and messages. Whichever socket the server picked hands the command over here.
@MainActor
@Observable
final class RemoteControl {
    static let shared = RemoteControl()

    /// For the open player. Each command is a new value, so the same one twice still arrives.
    struct Command: Equatable {
        let id = UUID()
        let kind: Kind
    }

    enum Kind: Equatable {
        case pause, unpause, playPause, stop
        case seek(ticks: Int64)
        case rewind, fastForward, nextTrack, previousTrack
        case setVolume(Float), volumeUp, volumeDown, mute, unmute, toggleMute
        case audioTrack(Int)
        /// nil turns subtitles off.
        case subtitleTrack(Int?)
        case message(String)
    }

    struct Message: Identifiable, Equatable {
        let id = UUID()
        let header: String
        let text: String
    }

    private(set) var command: Command?
    /// A message sent while no player is open, shown over the app.
    var message: Message?

    func handle(_ remote: JellyfinRemoteCommand) {
        switch remote {
        case .play(let ids, let startTicks):
            play(id: ids[0], startTicks: startTicks)
        case .playstate(let state, let seekTicks):
            switch state {
            case .stop: send(.stop)
            case .pause: send(.pause)
            case .unpause: send(.unpause)
            case .playPause: send(.playPause)
            case .seek: if let seekTicks { send(.seek(ticks: seekTicks)) }
            case .rewind: send(.rewind)
            case .fastForward: send(.fastForward)
            case .nextTrack: send(.nextTrack)
            case .previousTrack: send(.previousTrack)
            }
        case .general(let name, let arguments):
            general(name, arguments)
        }
    }

    private func general(_ name: String, _ arguments: [String: String]) {
        switch name {
        case "DisplayMessage":
            let text = arguments["Text"] ?? ""
            let header = arguments["Header"] ?? ""
            guard !(text.isEmpty && header.isEmpty) else { return }
            if PlayerActivity.shared.isPlayerOpen {
                send(.message(header.isEmpty || text.isEmpty ? header + text : "\(header): \(text)"))
            } else {
                message = Message(header: header, text: text)
            }
        case "DisplayContent":
            guard let id = arguments["ItemId"], !PlayerActivity.shared.isPlayerOpen else { return }
            UserDefaults.standard.set(id, forKey: "arcfin.pendingPlayID")
            NotificationCenter.default.post(name: .arcfinPlayItem, object: nil, userInfo: ["itemID": id])
        case "SetVolume":
            if let volume = arguments["Volume"].flatMap(Float.init) { send(.setVolume(min(max(volume / 100, 0), 1))) }
        case "VolumeUp": send(.volumeUp)
        case "VolumeDown": send(.volumeDown)
        case "Mute": send(.mute)
        case "Unmute": send(.unmute)
        case "ToggleMute": send(.toggleMute)
        case "SetAudioStreamIndex":
            if let index = arguments["Index"].flatMap(Int.init) { send(.audioTrack(index)) }
        case "SetSubtitleStreamIndex":
            if let index = arguments["Index"].flatMap(Int.init) { send(.subtitleTrack(index < 0 ? nil : index)) }
        default:
            break
        }
    }

    private func send(_ kind: Kind) {
        command = Command(kind: kind)
    }

    /// Whatever is playing closes first; Home then opens the new title at the position asked for.
    private func play(id: String, startTicks: Int64?) {
        Task {
            if PlayerActivity.shared.isPlayerOpen {
                send(.stop)
                for _ in 0..<20 where PlayerActivity.shared.isPlayerOpen {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                // The cover's dismissal has to finish before Home can present another.
                try? await Task.sleep(for: .milliseconds(600))
            }
            WatchRoute.open(id: id, startTicks: startTicks)
        }
    }
}
