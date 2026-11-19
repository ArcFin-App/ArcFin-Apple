// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import JellyfinAPI

/// Apple Music isn't offered here (see PlatformMetrics.playsAppleMusic).
@MainActor @Observable
final class AppleMusicCatalog {
    static let shared = AppleMusicCatalog()

    struct Song: Identifiable, Hashable {
        let id: String
        let title: String
        let artist: String
        let album: String?
        let artworkURL: URL?
    }

    let canPlay = false
    let problem: String? = nil

    func requestAccess() async {}
    func search(_ term: String, excluding library: [MusicSong]) async -> [Song] { [] }
    func play(_ song: Song) async {}
}
