// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

/// Copy Title, and Copy IMDb Link / Copy TMDB Link when the server knows those IDs. Hidden
/// where there's no pasteboard (Apple TV).
struct CopyItemMenu: View {
    let item: MediaItem

    var body: some View {
        if ExternalApps.canCopy {
            Button { ExternalApps.copy(item.name) } label: {
                Label("Copy Title", systemImage: "doc.on.doc")
            }
            if let url = item.imdbURL {
                Button { ExternalApps.copy(url.absoluteString) } label: {
                    Label("Copy IMDb Link", systemImage: "link")
                }
            }
            if let url = item.tmdbURL {
                Button { ExternalApps.copy(url.absoluteString) } label: {
                    Label("Copy TMDB Link", systemImage: "link")
                }
            }
        }
    }
}

extension MediaItem {
    var imdbURL: URL? {
        imdbId.flatMap { URL(string: "https://www.imdb.com/title/\($0)/") }
    }

    /// Only movies and shows: an episode's TMDB ID needs its show's to make a link.
    var tmdbURL: URL? {
        guard let tmdbId else { return nil }
        switch type {
        case .movie: return URL(string: "https://www.themoviedb.org/movie/\(tmdbId)")
        case .series: return URL(string: "https://www.themoviedb.org/tv/\(tmdbId)")
        default: return nil
        }
    }
}
