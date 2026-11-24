// SPDX-License-Identifier: AGPL-3.0-or-later

import JellyfinAPI

/// Which of a season's episodes the download sheet lists, ticks and queues. `taken` holds the
/// ids already downloaded or downloading, which can't be picked.
enum SeasonEpisodePicks {
    static func listed(_ episodes: [MediaItem]) -> [MediaItem] {
        episodes.filter { !$0.isVirtual }
    }

    static func selectable(_ episodes: [MediaItem], taken: Set<String>) -> [MediaItem] {
        listed(episodes).filter { !taken.contains($0.id) }
    }

    static func defaults(_ episodes: [MediaItem], taken: Set<String>, unwatchedOnly: Bool) -> Set<String> {
        Set(selectable(episodes, taken: taken).filter { !(unwatchedOnly && $0.userData?.played == true) }.map(\.id))
    }

    static func nextUnwatched(_ episodes: [MediaItem], taken: Set<String>, count: Int = 3) -> Set<String> {
        Set(selectable(episodes, taken: taken).filter { $0.userData?.played != true }.prefix(count).map(\.id))
    }

    /// In the season's own order, so the queue downloads them as they air.
    static func ordered(_ episodes: [MediaItem], picked: Set<String>, taken: Set<String>) -> [MediaItem] {
        selectable(episodes, taken: taken).filter { picked.contains($0.id) }
    }
}
