// SPDX-License-Identifier: AGPL-3.0-or-later

import ImageCache
import SwiftUI
import TVServices

/// The Top Shelf carousel has no logo or progress fields, so both are drawn into its image.
enum TopShelfArtwork {
    static func refresh() async {
        guard let directory = TopShelfBridge.artworkDirectory else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var continueWatching = TopShelfBridge.loadContinueWatching()
        var nextUp = TopShelfBridge.loadNextUp()
        var recentlyAdded = TopShelfBridge.loadRecentlyAdded()
        await addArtwork(to: &continueWatching, in: directory)
        await addArtwork(to: &nextUp, in: directory)
        await addArtwork(to: &recentlyAdded, in: directory)
        guard !Task.isCancelled else { return }

        TopShelfBridge.save(continueWatching: continueWatching, nextUp: nextUp, recentlyAdded: recentlyAdded)
        removeUnused(keeping: Set((continueWatching + nextUp + recentlyAdded).compactMap(\.artworkFileName)), in: directory)
        TVTopShelfContentProvider.topShelfContentDidChange()
    }

    private static func addArtwork(to items: inout [TopShelfMediaItem], in directory: URL) async {
        let accent = UIColor(DT.Color.accent)
        for index in items.indices {
            let item = items[index]
            guard let backdropURL = item.backdropURL ?? item.imageURL,
                  let backdrop = try? await ImageCache.load(backdropURL) else { continue }
            let logo = if let logoURL = item.logoURL { try? await ImageCache.load(logoURL) } else { nil as UIImage? }
            let progress = item.progress
            guard logo != nil || progress > 0 else { continue }

            // The percentage is in the name because the system caches images by URL.
            let name = "\(item.id)-\(Int((progress * 100).rounded())).jpg"
            let url = directory.appendingPathComponent(name)
            let saved = await Task.detached(priority: .utility) {
                render(backdrop: backdrop, logo: logo, progress: progress, accent: accent, to: url)
            }.value
            guard saved else { continue }
            items[index].artworkFileName = name
            items[index].artworkHasLogo = logo != nil
        }
    }

    // Top left stays clear of the system's details and of the dock below the collapsed shelf.
    private nonisolated static func render(backdrop: UIImage, logo: UIImage?, progress: Double, accent: UIColor, to url: URL) -> Bool {
        let canvas = CGSize(width: 1920, height: 1080)
        let left: CGFloat = 90
        let maxLogo = CGSize(width: 640, height: 200)
        let barSize = CGSize(width: 640, height: 10)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let data = UIGraphicsImageRenderer(size: canvas, format: format).jpegData(withCompressionQuality: 0.85) { context in
            let fill = max(canvas.width / backdrop.size.width, canvas.height / backdrop.size.height)
            let drawn = CGSize(width: backdrop.size.width * fill, height: backdrop.size.height * fill)
            backdrop.draw(in: CGRect(x: (canvas.width - drawn.width) / 2, y: (canvas.height - drawn.height) / 2,
                                     width: drawn.width, height: drawn.height))

            let colors = [UIColor.black.withAlphaComponent(0.65).cgColor, UIColor.clear.cgColor] as CFArray
            if let scrim = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                context.cgContext.drawLinearGradient(scrim, start: .zero, end: CGPoint(x: 1100, y: 500), options: [])
            }

            var y: CGFloat = 90
            if let logo {
                let fit = min(maxLogo.width / logo.size.width, maxLogo.height / logo.size.height)
                let size = CGSize(width: logo.size.width * fit, height: logo.size.height * fit)
                logo.draw(in: CGRect(origin: CGPoint(x: left, y: y), size: size))
                y += size.height + 28
            }
            if progress > 0 {
                let track = CGRect(origin: CGPoint(x: left, y: y), size: barSize)
                UIColor.white.withAlphaComponent(0.3).setFill()
                UIBezierPath(roundedRect: track, cornerRadius: barSize.height / 2).fill()
                var filled = track
                filled.size.width = max(barSize.height, track.width * min(progress, 1))
                accent.setFill()
                UIBezierPath(roundedRect: filled, cornerRadius: barSize.height / 2).fill()
            }
        }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    private static func removeUnused(keeping names: Set<String>, in directory: URL) {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files where !names.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }
}
