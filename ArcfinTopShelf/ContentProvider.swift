// SPDX-License-Identifier: AGPL-3.0-or-later

import TVServices
import Foundation

class ContentProvider: TVTopShelfContentProvider {

    override func loadTopShelfContent() async -> (any TVTopShelfContent)? {
        let items = TopShelfBridge.loadContinueWatching() + TopShelfBridge.loadRecentlyAdded()
        guard !items.isEmpty else { return nil }
        return TVTopShelfCarouselContent(style: .details, items: items.map(makeItem(_:)))
    }

    private func makeItem(_ item: TopShelfMediaItem) -> TVTopShelfCarouselItem {
        let ci = TVTopShelfCarouselItem(identifier: item.id)
        ci.title = item.title
        ci.contextTitle = item.contextTitle
        ci.summary = item.summary
        ci.genre = item.genre
        ci.duration = item.duration ?? 0
        if let year = item.year {
            ci.creationDate = Calendar.current.date(from: DateComponents(year: year))
        }
        if let url = item.backdropURL ?? item.imageURL {
            ci.setImageURL(url, for: .screenScale1x)
            ci.setImageURL(url, for: .screenScale2x)
        }
        let deepLink = TopShelfBridge.playURL(for: item.id)
        ci.playAction    = TVTopShelfAction(url: deepLink)
        ci.displayAction = TVTopShelfAction(url: deepLink)
        return ci
    }
}
