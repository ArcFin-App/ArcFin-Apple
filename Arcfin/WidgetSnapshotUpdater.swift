// SPDX-License-Identifier: AGPL-3.0-or-later

#if canImport(UIKit) && !os(tvOS)
import Foundation
import JellyfinAPI
import LiveActivityKit
import WidgetKit

/// Publishes the Continue Watching shelf to the widgets: a JSON snapshot plus a small poster
/// file per item in the shared App Group container, then a timeline reload.
enum WidgetSnapshotUpdater {
    private static let maxItems = 6

    @MainActor
    static func update(items: [MediaItem], imageURL: (MediaItem) -> URL?) async {
        let selected = Array(items.prefix(maxItems))
        let jobs = selected.map { (item: $0, url: imageURL($0)) }

        var entries: [WidgetSnapshot.Item] = []
        var keep = Set<String>()
        for job in jobs {
            let item = job.item
            var fileName: String?
            if let url = job.url, let (data, _) = try? await URLSession.arcfin.data(from: url), !data.isEmpty {
                let name = "\(item.id).jpg"
                WidgetSnapshotStore.writePoster(data, fileName: name)
                fileName = name
                keep.insert(name)
            }
            entries.append(.init(
                id: item.id,
                title: item.type == .episode ? (item.seriesName ?? item.name) : item.name,
                subtitle: subtitle(for: item),
                progress: min(max((item.userData?.playedPercentage ?? 0) / 100, 0), 1),
                posterFileName: fileName))
        }

        let snapshot = WidgetSnapshot(items: entries)
        if snapshot.items != WidgetSnapshotStore.load()?.items {
            WidgetSnapshotStore.save(snapshot)
            WidgetSnapshotStore.prunePosters(keeping: keep)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private static func subtitle(for item: MediaItem) -> String? {
        guard item.type == .episode else { return item.productionYear.map(String.init) }
        let season = item.parentIndexNumber.map { "S\($0)" }
        let episode = item.indexNumber.map { "E\($0)" }
        let code = [season, episode].compactMap { $0 }.joined()
        return code.isEmpty ? item.name : "\(code) · \(item.name)"
    }
}
#endif
