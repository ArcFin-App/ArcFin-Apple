// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// Each profile's own settings on this device. They all live in one UserDefaults, so on every
/// profile change the outgoing profile's values are put away and the incoming one's come back.
/// A profile that has none yet starts at the defaults: starting from the last profile's
/// values would give it someone else's settings, and the next sync would send them to its
/// record on the server.
public enum ProfileSettings {
    /// Each profile's, but not synced.
    public static let localKeys: [String] = [
        "homeShelfKnown",
        "defaultExternalPlayer",
        "lastPlaybackRate",
        "smartDownloadsIgnored", "smartDownloadsKeptShows",
        "arcfin.showTrackMemory",
        "recentSearches",
    ]

    /// Synced and each profile's, but swapped with the Seerr sign-in and its password.
    public static let swappedWithSeerr: Set<String> = ["seerrURL", "seerrUsername", "seerrAuthMethod"]

    public static var keys: [String] {
        SettingsSyncRegistry.entries.map(\.key).filter { !swappedWithSeerr.contains($0) } + localKeys
    }

    private static let ownerKey = "arcfin.profileSettings.owner"
    private static func storeKey(_ profile: String) -> String { "arcfin.profileSettings.\(profile)" }

    /// Puts `profile`'s settings in place. `profiles` is every profile on this device.
    public static func activate(profile: String, profiles: [String], defaults: UserDefaults = .standard) {
        let owner = defaults.string(forKey: ownerKey)
        guard owner != profile else { return }
        defaults.set(profile, forKey: ownerKey)
        guard let owner else {
            // The first time: the values here have been everyone's. The profile in use keeps
            // them; the others start from what they last synced, or from these.
            seed(profiles.filter { $0 != profile }, defaults: defaults)
            return
        }
        // A profile just removed has nothing to keep.
        if profiles.contains(owner) { defaults.set(snapshot(defaults), forKey: storeKey(owner)) }
        let restored = defaults.dictionary(forKey: storeKey(profile)) ?? [:]
        for key in keys {
            if let value = restored[key] { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
        }
    }

    /// A removed profile's settings.
    public static func forget(profile: String, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: storeKey(profile))
    }

    private static func snapshot(_ defaults: UserDefaults) -> [String: Any] {
        var values: [String: Any] = [:]
        for key in keys { values[key] = defaults.object(forKey: key) }
        return values
    }

    private static func seed(_ profiles: [String], defaults: UserDefaults) {
        let live = snapshot(defaults)
        let types = Dictionary(uniqueKeysWithValues: SettingsSyncRegistry.entries.map { ($0.key, $0.type) })
        for profile in profiles where defaults.object(forKey: storeKey(profile)) == nil {
            var values = live
            for (key, value) in SettingsSyncEngine.lastSynced(profile: profile, defaults: defaults) ?? [:] {
                guard let type = types[key], !swappedWithSeerr.contains(key),
                      let stored = type.stored(value, key: key) else { continue }
                values[key] = stored
            }
            defaults.set(values, forKey: storeKey(profile))
        }
    }
}
