// SPDX-License-Identifier: AGPL-3.0-or-later

import TVServices
import Foundation

class ContentProvider: TVTopShelfContentProvider {

    override func loadTopShelfContent() async -> (any TVTopShelfContent)? {
        var seen = Set<String>()
        let items = (TopShelfBridge.loadContinueWatching() + TopShelfBridge.loadNextUp() + TopShelfBridge.loadRecentlyAdded()
                     + TopShelfBridge.loadLiveChannels())
            .filter { seen.insert($0.id).inserted }
        guard !items.isEmpty else { return nil }
        return TVTopShelfCarouselContent(style: .details, items: items.map(makeItem(_:)))
    }

    private func makeItem(_ item: TopShelfMediaItem) -> TVTopShelfCarouselItem {
        let ci = TVTopShelfCarouselItem(identifier: item.id)
        ci.title = item.artworkHasLogo == true ? nil : item.title
        ci.contextTitle = item.contextTitle
        ci.summary = item.summary
        ci.genre = item.genre
        ci.duration = item.duration ?? 0
        if let year = item.year {
            ci.creationDate = Calendar.current.date(from: DateComponents(year: year))
        }
        if let title = item.ratingTitle, let value = item.ratingValue {
            ci.namedAttributes = [TVTopShelfNamedAttribute(name: title, values: [value])]
        }
        if let url = TopShelfBridge.artworkURL(for: item) ?? item.backdropURL ?? item.imageURL {
            ci.setImageURL(url, for: .screenScale1x)
            ci.setImageURL(url, for: .screenScale2x)
        }
        ci.previewVideoURL = item.previewVideoURL
        let deepLink = TopShelfBridge.playURL(for: item.id)
        ci.playAction    = TVTopShelfAction(url: deepLink)
        ci.displayAction = TVTopShelfAction(url: deepLink)
        return ci
    }
}
