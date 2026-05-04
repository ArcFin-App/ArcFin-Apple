import TVServices

// Principal class for the TV Top Shelf Extension.
// Info.plist: NSExtensionPrincipalClass = "$(PRODUCT_MODULE_NAME).TopShelfProvider"

final class TopShelfProvider: TVTopShelfContentProvider {

    override func loadTopShelfContent(completionHandler: @escaping (TVTopShelfContent?) -> Void) {
        let stored = TopShelfBridge.loadContinueWatching()
        guard !stored.isEmpty else {
            completionHandler(nil)
            return
        }

        let shelfItems: [TVTopShelfSectionedItem] = stored.map { item in
            let si = TVTopShelfSectionedItem(identifier: item.id)
            si.title = item.title
            si.summary = item.subtitle

            if let imageURL = item.imageURL {
                si.setImageURL(imageURL, for: .screenScale1x)
            }

            let deepLink = TopShelfBridge.playURL(for: item.id)
            si.playAction = TVTopShelfAction(url: deepLink)
            si.displayAction = TVTopShelfAction(url: deepLink)
            return si
        }

        let collection = TVTopShelfItemCollection(items: shelfItems)
        collection.title = "Continue Watching"

        let content = TVTopShelfSectionedContent(sections: [collection])
        completionHandler(content)
    }
}
