// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// Remembers the audio and subtitle language chosen for a show, so every later episode starts
/// the way the last one was left. Keyed by series, stored on this device only.
enum ShowTrackMemory {
    static let enabledKey = "rememberTracksPerShow"
    private static let storageKey = "arcfin.showTrackMemory"
    private static let maxShows = 300

    struct Entry: Codable, Equatable {
        var audio: String?
        var subtitle: String?
        var subtitlesOff = false
    }

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    static var rememberedShowCount: Int { all().count }

    static func load(seriesID: String) -> Entry? { all()[seriesID] }

    static func save(_ entry: Entry, seriesID: String) {
        var entries = all()
        entries[seriesID] = entry
        // Oldest entries aren't tracked, so past the cap simply drop arbitrary ones.
        while entries.count > maxShows, let key = entries.keys.first(where: { $0 != seriesID }) {
            entries[key] = nil
        }
        write(entries)
    }

    static func clear() { UserDefaults.standard.removeObject(forKey: storageKey) }

    private static func all() -> [String: Entry] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: Entry].self, from: data)
        else { return [:] }
        return decoded
    }

    private static func write(_ entries: [String: Entry]) {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
