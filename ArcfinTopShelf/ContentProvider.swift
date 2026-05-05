import TVServices
import Foundation

class ContentProvider: TVTopShelfContentProvider {

    override func loadTopShelfContent() async -> (any TVTopShelfContent)? {
        let items = Self.loadItems()
        guard !items.isEmpty else { return nil }

        let shelfItems: [TVTopShelfSectionedItem] = items.map { item in
            let si = TVTopShelfSectionedItem(identifier: item.id)
            si.title = item.title
            if let url = item.imageURL {
                si.setImageURL(url, for: .screenScale1x)
            }
            let deepLink = URL(string: "arcfin://play/\(item.id)")!
            si.playAction = TVTopShelfAction(url: deepLink)
            si.displayAction = TVTopShelfAction(url: deepLink)
            return si
        }

        let collection = TVTopShelfItemCollection(items: shelfItems)
        collection.title = "Continue Watching"
        return TVTopShelfSectionedContent(sections: [collection])
    }

    // MARK: - Bridge (reads shared App Group written by main app)

    private struct StoredItem: Decodable {
        let id: String
        let title: String
        let subtitle: String?
        let imageURL: URL?
        let progress: Double
    }

    private static func loadItems() -> [StoredItem] {
        guard
            let defaults = UserDefaults(suiteName: "group.com.psmattas.arcfin"),
            let data = defaults.data(forKey: "topShelf.continueWatching"),
            let items = try? JSONDecoder().decode([StoredItem].self, from: data)
        else { return [] }
        return items
    }
}
