// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

// Posted by onOpenURL when the Top Shelf launches a play deep link.
extension Notification.Name {
    static let arcfinPlayItem = Notification.Name("arcfinPlayItem")
    /// Posted by onOpenURL for arcfin://downloads — tapping the download Live Activity.
    static let arcfinShowDownloads = Notification.Name("arcfinShowDownloads")
    /// Browse to the front, for an album or artist opened from Now Playing.
    static let arcfinShowMusic = Notification.Name("arcfinShowMusic")
    /// Posted by onOpenURL for arcfin://resume — the Resume Watching control.
    static let arcfinResume = Notification.Name("arcfinResume")
    /// Posted when a notification about a Seerr request or watchlist item is tapped.
    static let arcfinShowDiscover = Notification.Name("arcfinShowDiscover")
    /// Posted with a "term" in userInfo to show in-app search results (Siri / Shortcuts).
    static let arcfinSearch = Notification.Name("arcfinSearch")
    /// Posted with an "id" (Seerr entry id) to open that title's Seerr page.
    static let arcfinOpenSeerrTitle = Notification.Name("arcfinOpenSeerrTitle")
    /// Posted when the user switches away from the Home tab, so a shuffled Home can reorder
    /// itself while it is off-screen.
    static let arcfinHomeTabLeft = Notification.Name("arcfinHomeTabLeft")
    /// Posted by the macOS app menu's Settings… command (Cmd+,) — there's no scene-level
    /// binding into MainTabView's private navigation state to reach otherwise, so this
    /// follows the same NotificationCenter pattern arcfinShowDownloads already established.
    /// The Mac's Go menu: "tab" in userInfo is a BottomNavItem raw value.
    static let arcfinSelectTab = Notification.Name("arcfinSelectTab")
    /// View › Refresh on the Mac.
    static let arcfinRefresh = Notification.Name("arcfinRefresh")
    /// Posted once the player's stop report and watched mark have reached the server.
    static let arcfinPlaybackReported = Notification.Name("arcfinPlaybackReported")
    /// File › Open Video File… on the Mac.
    static let arcfinOpenFile = Notification.Name("arcfinOpenFile")
    /// Posted once AppServices.hasPassedLock turns true, for screens that wait for the app lock
    /// without a view to observe it (CarPlay).
    static let arcfinPassedLock = Notification.Name("arcfinPassedLock")
}
