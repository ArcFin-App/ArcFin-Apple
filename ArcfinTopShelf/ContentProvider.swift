import TVServices
import Foundation

class ContentProvider: TVTopShelfContentProvider {

    override func loadTopShelfContent() async -> (any TVTopShelfContent)? {
        let continueWatching = TopShelfBridge.loadContinueWatching()
        let recentlyAdded    = TopShelfBridge.loadRecentlyAdded()
        guard !continueWatching.isEmpty || !recentlyAdded.isEmpty else { return nil }

        var sections: [TVTopShelfItemCollection<TVTopShelfSectionedItem>] = []

        if !continueWatching.isEmpty {
            let col = TVTopShelfItemCollection(items: continueWatching.map(makeItem(_:)))
            col.title = "Continue Watching"
            sections.append(col)
        }

        if !recentlyAdded.isEmpty {
            let col = TVTopShelfItemCollection(items: recentlyAdded.map(makeItem(_:)))
            col.title = "Recently Added"
            sections.append(col)
        }

        return TVTopShelfSectionedContent(sections: sections)
    }

    private func makeItem(_ item: TopShelfMediaItem) -> TVTopShelfSectionedItem {
        let si = TVTopShelfSectionedItem(identifier: item.id)
        si.title = item.title
        if let url = item.imageURL {
            si.setImageURL(url, for: .screenScale1x)
        }
        let deepLink = TopShelfBridge.playURL(for: item.id)
        si.playAction    = TVTopShelfAction(url: deepLink)
        si.displayAction = TVTopShelfAction(url: deepLink)
        return si
    }
}
