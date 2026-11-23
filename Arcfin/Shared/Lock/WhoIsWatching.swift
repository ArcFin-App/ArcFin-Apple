// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// Apple TV's Always Ask Who's Watching (#688): the profile picker when Arcfin opens, and
/// when you come back after a while with nothing playing. Kept on this device, not synced.
@MainActor
enum WhoIsWatching {
    nonisolated static let settingKey = "alwaysAskWhoIsWatching"
    /// Offered once per device when a second profile is added, whatever the answer.
    nonisolated static let offeredKey = "arcfin.whoIsWatchingOffered"
    nonisolated static let minimumAway: TimeInterval = 30 * 60

    /// A paused film or music left playing means someone is still watching or listening; that
    /// return isn't asked, nor later when they stop.
    nonisolated static func shouldAsk(isOn: Bool, profileCount: Int, isColdLaunch: Bool, secondsAway: TimeInterval,
                                      isPlayerOpen: Bool, isMusicPlaying: Bool) -> Bool {
        guard isOn, profileCount >= 2 else { return false }
        if isColdLaunch { return true }
        return secondsAway >= minimumAway && !isPlayerOpen && !isMusicPlaying
    }

    static var isOn: Bool {
        PlatformMetrics.asksWhoIsWatching && UserDefaults.standard.bool(forKey: settingKey)
    }

    /// The cold launch asks, so everything that waits for the lock waits for the picker too.
    static func asksAtLaunch(profileCount: Int) -> Bool {
        shouldAsk(isOn: isOn, profileCount: profileCount, isColdLaunch: true, secondsAway: 0,
                  isPlayerOpen: false, isMusicPlaying: false)
    }

    /// When a second profile is saved: not where the setting doesn't exist, once it's on, or
    /// once it has been offered.
    static var canOffer: Bool {
        PlatformMetrics.asksWhoIsWatching && !UserDefaults.standard.bool(forKey: settingKey)
            && !UserDefaults.standard.bool(forKey: offeredKey)
    }
}
