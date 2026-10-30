// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import JellyfinAPI

/// How Home names a title on its cards and in the hero on iPhone, iPad and Mac.
enum HomeText {
    static func title(_ item: MediaItem) -> String {
        if item.type == .episode {
            return item.seriesName?.nilIfEmpty ?? item.name.nilIfEmpty ?? "Unknown"
        }
        return item.name.nilIfEmpty ?? "Unknown"
    }

    static func subtitle(_ item: MediaItem) -> String? {
        if item.type == .episode {
            let s = item.parentIndexNumber.map { "S\($0)" }
            let e = item.indexNumber.map { "E\($0)" }
            let code = [s, e].compactMap { $0 }.joined()
            let episodeName = item.name.nilIfEmpty
            return [code.nilIfEmpty, episodeName].compactMap { $0 }.joined(separator: " · ").nilIfEmpty
        }
        return item.productionYear.map { "\($0)" }
    }

    static func heroMeta(_ item: MediaItem) -> String {
        var parts: [String] = []
        if let year = item.productionYear { parts.append(String(year)) }
        switch item.type {
        case .series:  parts.append("Series")
        case .episode: parts.append(subtitle(item) ?? "Episode")
        default:       parts.append("Movie")
        }
        return parts.joined(separator: " · ")
    }

    /// "S1E4" on the hero's Play button for an episode.
    static func episodeLabel(_ item: MediaItem) -> String? {
        guard item.type == .episode else { return nil }
        let s = item.parentIndexNumber.map { "S\($0)" }
        let e = item.indexNumber.map { "E\($0)" }
        return [s, e].compactMap { $0 }.joined().nilIfEmpty
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
