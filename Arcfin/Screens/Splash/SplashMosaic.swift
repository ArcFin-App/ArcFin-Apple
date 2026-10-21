// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import JellyfinAPI
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Posters of recently added titles, saved to disk so the next launch's splash can show them
/// instantly: at that moment nothing is signed in or loaded yet, so they can't come from the
/// network. Cleared on sign-out so one account's library never appears for another.
enum SplashMosaicStore {
    static let maxPosters = 36
    private static let idsFile = "ids.json"

    private static var directory: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("splash-mosaic", isDirectory: true)
    }

    /// Small enough to read on the main thread while the splash appears.
    static func loadImages() -> [Image] {
        guard let directory else { return [] }
        return (0..<maxPosters).compactMap { index in
            let path = directory.appendingPathComponent("\(index).jpg").path
            return PlatformImage(contentsOfFile: path).map(Image.init(platformImage:))
        }
    }

    /// Re-downloads only when the set of titles changed since the last save.
    static func save(_ items: [MediaItem], imageURL: (MediaItem) -> URL?) async {
        guard let directory else { return }
        var seen = Set<String>()
        let picks = items.filter { $0.primaryImageTag != nil && seen.insert($0.id).inserted }.prefix(maxPosters)
        let ids = picks.map(\.id)
        let idsURL = directory.appendingPathComponent(idsFile)
        if let data = try? Data(contentsOf: idsURL),
           let saved = try? JSONDecoder().decode([String].self, from: data), saved == ids { return }

        let jobs = picks.map { (id: $0.id, url: imageURL($0)) }
        var images: [Data] = []
        for job in jobs {
            guard let url = job.url,
                  let (data, _) = try? await URLSession.arcfin.data(from: url), !data.isEmpty
            else { continue }
            images.append(data)
        }
        guard images.count >= 6 else { return }

        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (index, data) in images.enumerated() {
            try? data.write(to: directory.appendingPathComponent("\(index).jpg"), options: .atomic)
        }
        if let data = try? JSONEncoder().encode(ids) { try? data.write(to: idsURL, options: .atomic) }
    }

    static func clear() {
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory)
    }
}

/// A tilted wall of posters, each column drifting in the opposite direction to its neighbour.
struct SplashMosaicView: View {
    let posters: [Image]
    /// 0…1: how far the staggered column fade-in has got.
    var reveal: Double
    var isAnimated: Bool

    private let columnCount = 8
    /// Each column is one run of posters shown twice, so scrolling by exactly one run loops
    /// seamlessly.
    private let run = 6

    var body: some View {
        GeometryReader { proxy in
            let columnWidth = max(proxy.size.width, proxy.size.height) / 7
            let posterHeight = columnWidth * 1.5
            let spacing: CGFloat = 8
            let cycle = (posterHeight + spacing) * CGFloat(run)

            TimelineView(.animation(paused: !isAnimated)) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(0..<columnCount, id: \.self) { column in
                        let speed = 14 + CGFloat(column % 3) * 4
                        let travelled = isAnimated ? CGFloat(time * speed).truncatingRemainder(dividingBy: cycle) : cycle / 2
                        // Alternate columns run up and down.
                        let drift = column.isMultiple(of: 2) ? travelled : cycle - travelled
                        VStack(spacing: spacing) {
                            ForEach(0..<(run * 2), id: \.self) { row in
                                posters[(column * run + row % run) % posters.count]
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: columnWidth, height: posterHeight)
                                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            }
                        }
                        .offset(y: drift - cycle)
                        .opacity(min(max(reveal * Double(columnCount) - Double(column) * 0.6, 0), 1))
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .rotationEffect(.degrees(-14))
                .scaleEffect(1.45)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
