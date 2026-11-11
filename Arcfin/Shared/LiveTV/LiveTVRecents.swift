// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import JellyfinAPI

/// The channels watched most recently on this device, newest first, for Home's Recently
/// Watched Channels and the player's way back to the last channel. Kept per user.
@MainActor
enum LiveTVRecents {
    private struct Stored: Codable {
        let id: String
        let name: String
        let number: String?
        let imageTag: String?
    }

    private static let limit = 12

    private static func key(_ userID: String) -> String { "arcfin.liveTVRecents.\(userID)" }

    static func channels(for userID: String) -> [LiveTVChannel] {
        guard let data = UserDefaults.standard.data(forKey: key(userID)),
              let stored = try? JSONDecoder().decode([Stored].self, from: data) else { return [] }
        return stored.map { LiveTVChannel(id: $0.id, name: $0.name, number: $0.number, primaryImageTag: $0.imageTag) }
    }

    static func record(_ channel: LiveTVChannel, for userID: String) {
        var list = channels(for: userID).filter { $0.id != channel.id }
        list.insert(channel, at: 0)
        let stored = list.prefix(limit).map { Stored(id: $0.id, name: $0.name, number: $0.number, imageTag: $0.primaryImageTag) }
        if let data = try? JSONEncoder().encode(Array(stored)) {
            UserDefaults.standard.set(data, forKey: key(userID))
        }
    }
}
