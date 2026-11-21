// SPDX-License-Identifier: AGPL-3.0-or-later

#if !os(tvOS)
import Foundation
import JellyfinAPI
import LiveActivityKit
import WidgetKit

/// Publishes Continue Watching and Recently Added to the widgets: a JSON snapshot plus a small
/// image file per item in the shared App Group container, then a timeline reload.
enum WidgetSnapshotUpdater {
    private static let maxItems = 6
    private static let maxRecentlyAdded = 12

    /// Sign-out / profile removal: empties the widgets right away.
    static func clear() {
        WidgetSnapshotStore.clear()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// `artworkURL` is the landscape art for Continue Watching, `posterURL` the portrait
    /// poster for Recently Added.
    @MainActor
    static func update(
        items: [MediaItem],
        recentlyAdded: [MediaItem],
        artworkURL: (MediaItem) -> URL?,
        posterURL: (MediaItem) -> URL?
    ) async {
        // Home hasn't loaded yet (cold launch, offline): keep the last titles rather than empty
        // the widgets. Sign-out and a profile switch clear the snapshot through clear().
        if items.isEmpty, recentlyAdded.isEmpty, let previous = WidgetSnapshotStore.load(),
           !previous.items.isEmpty || !(previous.recentlyAdded ?? []).isEmpty {
            return
        }
        var keep = Set<String>()
        var entries: [WidgetSnapshot.Item] = []
        for item in items.prefix(maxItems) {
            let fileName = await storeImage(prefix: "cw", item: item, url: artworkURL(item))
            if let fileName { keep.insert(fileName) }
            entries.append(entry(for: item, fileName: fileName))
        }
        var added: [WidgetSnapshot.Item] = []
        for item in recentlyAdded.prefix(maxRecentlyAdded) {
            let fileName = await storeImage(prefix: "ra", item: item, url: posterURL(item))
            if let fileName { keep.insert(fileName) }
            added.append(entry(for: item, fileName: fileName))
        }

        let previous = WidgetSnapshotStore.load()
        guard entries != previous?.items || added != (previous?.recentlyAdded ?? []) else { return }
        WidgetSnapshotStore.save(WidgetSnapshot(items: entries, recentlyAdded: added))
        WidgetSnapshotStore.prunePosters(keeping: keep)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Images are keyed by item id and kept between updates, so an unchanged shelf costs no
    /// downloads at all.
    @MainActor
    private static func storeImage(prefix: String, item: MediaItem, url: URL?) async -> String? {
        let name = "\(prefix)-\(item.id).jpg"
        if WidgetSnapshotStore.hasPoster(fileName: name) { return name }
        guard let url, let data = await URLSession.arcfin.imageData(from: url) else { return nil }
        WidgetSnapshotStore.writePoster(data, fileName: name)
        return name
    }

    private static func entry(for item: MediaItem, fileName: String?) -> WidgetSnapshot.Item {
        .init(
            id: item.id,
            title: item.type == .episode ? (item.seriesName ?? item.name) : item.name,
            subtitle: subtitle(for: item),
            detail: item.type == .episode ? item.name : nil,
            progress: min(max((item.userData?.playedPercentage ?? 0) / 100, 0), 1),
            posterFileName: fileName)
    }

    private static func subtitle(for item: MediaItem) -> String? {
        guard item.type == .episode else { return item.productionYear.map(String.init) }
        let code = [item.parentIndexNumber.map { "S\($0)" }, item.indexNumber.map { "E\($0)" }]
            .compactMap { $0 }.joined(separator: " · ")
        return code.isEmpty ? nil : code
    }
}
#endif
