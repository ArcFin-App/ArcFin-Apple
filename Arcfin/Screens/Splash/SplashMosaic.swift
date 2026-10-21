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
    static let maxPosters = 18
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

/// The library's recent posters standing in a ring that slowly turns in 3D around the mark,
/// the nearest cards bright and large, the far side dim and small behind it.
struct SplashPosterCarousel: View {
    let posters: [Image]
    /// 0…1 entrance: the ring widens from the centre and fades up.
    var reveal: Double
    var isAnimated: Bool

    var body: some View {
        GeometryReader { proxy in
            let count = min(posters.count, 12)
            let radius = min(proxy.size.width, 520) * 0.62 * reveal
            let cardWidth = min(proxy.size.width, 520) * 0.26
            TimelineView(.animation(paused: !isAnimated)) { timeline in
                let spin = isAnimated ? timeline.date.timeIntervalSinceReferenceDate * 10 : 0
                ZStack {
                    ForEach(0..<count, id: \.self) { index in
                        let angle = (Double(index) / Double(count)) * 360 + spin
                        let radians = angle * .pi / 180
                        // depth: 1 nearest the viewer, -1 directly behind the mark
                        let depth = cos(radians)
                        posters[index]
                            .resizable()
                            .scaledToFill()
                            .frame(width: cardWidth, height: cardWidth * 1.5)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(.white.opacity(0.12), lineWidth: 1)
                            )
                            .rotation3DEffect(.degrees(-angle), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                            .scaleEffect(0.62 + 0.38 * (depth + 1) / 2)
                            .brightness(-0.45 * (1 - (depth + 1) / 2))
                            .offset(x: sin(radians) * radius)
                            .zIndex(depth)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                // Seen slightly from above, like a turntable.
                .rotation3DEffect(.degrees(14), axis: (x: 1, y: 0, z: 0), perspective: 0.4)
                .opacity(reveal)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
