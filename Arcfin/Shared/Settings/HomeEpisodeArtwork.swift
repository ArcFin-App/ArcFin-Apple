// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// Settings › Home Shelves › Episode Artwork: an episode's own still in Continue Watching and
/// Next Up, or its show's artwork, which also keeps a scene from giving anything away.
enum HomeEpisodeArtwork: String, CaseIterable, Identifiable {
    case episode, series

    static let key = "homeEpisodeArtwork"
    static var current: HomeEpisodeArtwork {
        UserDefaults.standard.string(forKey: key).flatMap(HomeEpisodeArtwork.init) ?? .episode
    }

    var id: String { rawValue }
    var label: LocalizedStringKey {
        switch self {
        case .episode: "Episode"
        case .series: "Show"
        }
    }
}

struct HomeEpisodeArtworkSection: View {
    @AppStorage(HomeEpisodeArtwork.key) private var artwork = HomeEpisodeArtwork.episode
    @Environment(AuthManager.self) private var authManager

    var body: some View {
        Section {
            SettingsPicker("Episode Artwork", detail: "In Continue Watching and Next Up: the episode's own still, or its show's artwork.",
                           selection: $artwork, options: HomeEpisodeArtwork.allCases) { Text($0.label) }
            .syncLocked(HomeEpisodeArtwork.key, authManager)
        }
    }
}
