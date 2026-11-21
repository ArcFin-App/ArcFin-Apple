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

    /// Browse's library tiles, in the same order on every device: Movies, Shows, Live TV,
    /// Collections, Playlists, then the rest as the server lists them. Each Jellyfin user has
    /// their own library order, so the server's alone moved tiles between profiles.
    /// Music only where there are music screens (#386). Live TV only for profiles allowed it.
    static func libraries(in mediaRepo: MediaRepository, includeLiveTV: Bool = false,
                          includeMusic: Bool = false) -> [JellyfinLibrary] {
        let hidden = LibraryVisibility.hiddenIDs
        var libraries = mediaRepo.libraries.filter {
            ($0.collectionType != .livetv || includeLiveTV) && ($0.collectionType != .music || includeMusic)
                && !hidden.contains($0.id)
        }
        // The server only lists a Playlists library once a playlist exists; the tile is
        // always there so the first one can be made from it.
        if !libraries.isEmpty, !libraries.contains(where: { $0.collectionType == .playlists }) {
            libraries.append(JellyfinLibrary(id: LibraryDetailModel.allPlaylistsID, name: String(localized: "Playlists"), collectionType: .playlists))
        }
        return libraries.enumerated()
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .map(\.element)
    }

    private static func rank(_ library: JellyfinLibrary) -> Int {
        switch library.collectionType {
        case .movies: 0
        case .tvshows: 1
        case .livetv: 2
        case .boxsets: 3
        case .playlists: 4
        default: 5
        }
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
