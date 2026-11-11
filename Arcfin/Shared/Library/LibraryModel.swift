// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import JellyfinAPI

/// Browse's search, deep links and picked file, shared by the iPhone, iPad and Mac `LibraryView`.
@MainActor @Observable
final class LibraryModel {
    var searchQuery = ""
    var openedLibrary: JellyfinLibrary?
    var showDocPicker = false
    private(set) var pickedURL: URL?
    var navigateToLocalPlayer = false
    var navigateToDownloadsDeepLink = false

    /// Live TV and Music aren't playable yet (no live-TV tuner support, no music player
    /// UI) — hide them from the library list rather than showing a section that just
    /// leads to a dead end.
    /// `includeLiveTV` is for the platforms whose Browse has a Live TV screen to open.
    static func libraries(in mediaRepo: MediaRepository, includeLiveTV: Bool = false) -> [JellyfinLibrary] {
        let hidden = LibraryVisibility.hiddenIDs
        let libraries = mediaRepo.libraries.filter {
            ($0.collectionType != .livetv || includeLiveTV) && $0.collectionType != .music && !hidden.contains($0.id)
        }
        // The server only lists a Playlists library once a playlist exists; the tile is
        // always there so the first one can be made from it.
        guard !libraries.isEmpty, !libraries.contains(where: { $0.collectionType == .playlists }) else { return libraries }
        return libraries + [JellyfinLibrary(id: LibraryDetailModel.allPlaylistsID, name: "Playlists", collectionType: .playlists)]
    }

    func play(_ url: URL) {
        pickedURL = url
        navigateToLocalPlayer = true
    }

    func search(from note: Notification) {
        if let term = note.userInfo?["term"] as? String { searchQuery = term }
    }

    /// A search or Downloads asked for while Browse wasn't on screen yet.
    func applyPendingRequests() {
        if let term = UserDefaults.standard.string(forKey: "arcfin.pendingSearch") {
            UserDefaults.standard.removeObject(forKey: "arcfin.pendingSearch")
            searchQuery = term
        }
        if UserDefaults.standard.bool(forKey: "arcfin.pendingShowDownloads") {
            UserDefaults.standard.removeObject(forKey: "arcfin.pendingShowDownloads")
            navigateToDownloadsDeepLink = true
        }
    }

    func showDownloads() {
        UserDefaults.standard.removeObject(forKey: "arcfin.pendingShowDownloads")
        searchQuery = ""
        navigateToDownloadsDeepLink = true
    }

    /// Find… (⌘F) can come before Browse has ever been open, so it's left as a flag.
    func takePendingFindFocus() -> Bool {
        guard UserDefaults.standard.bool(forKey: "arcfin.pendingFindFocus") else { return false }
        UserDefaults.standard.removeObject(forKey: "arcfin.pendingFindFocus")
        return true
    }

    func openFileRequested() {
        showDocPicker = true
        // After the tab bar's own handler, which buffers it for an unmounted Browse.
        Task { UserDefaults.standard.removeObject(forKey: "arcfin.pendingOpenFile") }
    }

    /// File › Open Video File… while Browse wasn't on screen yet.
    func openPendingFile() {
        if UserDefaults.standard.bool(forKey: "arcfin.pendingOpenFile") {
            UserDefaults.standard.removeObject(forKey: "arcfin.pendingOpenFile")
            showDocPicker = true
        }
    }
}
