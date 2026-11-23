// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import ImageIO
import JellyfinAPI
import AuthCore
import Telemetry
import os

/// Fetches and crops Jellyfin trickplay sprite-sheet tiles into individual scrub-preview
/// thumbnails, caching whole tiles (each holds many frames) rather than individual crops.
/// The tiles come from the server, or from the files a download saved them to.
@MainActor
final class TrickplayLoader {
    private enum Tiles {
        case server(credential: ServerCredential, authHeader: String, client: JellyfinMediaClient, itemId: String)
        /// In tile order: a tile that failed to download keeps an empty name.
        case files(directory: URL, fileNames: [String])
    }
    private let tiles: Tiles
    private let info: JellyfinTrickplayInfo
    private static let log = Telemetry.logger(category: "Trickplay")
    /// A few decoded sheets, most recent last: each is large, and a scrub only moves between
    /// neighbouring ones, so keeping every sheet of a film added up (on Apple TV especially).
    private var tileCache: [Int: CGImage] = [:]
    private var tileOrder: [Int] = []
    private static let cachedTiles = 4
    private var inFlight: [Int: Task<CGImage?, Never>] = [:]

    init(credential: ServerCredential, authHeader: String, client: JellyfinMediaClient, itemId: String, info: JellyfinTrickplayInfo) {
        tiles = .server(credential: credential, authHeader: authHeader, client: client, itemId: itemId)
        self.info = info
    }

    init(directory: URL, fileNames: [String], info: JellyfinTrickplayInfo) {
        tiles = .files(directory: directory, fileNames: fileNames)
        self.info = info
    }

    func thumbnail(forPositionTicks ticks: Int64) async -> PlatformImage? {
        guard info.intervalMs > 0, info.thumbnailCount > 0 else { return nil }
        let positionMs = Int(Double(ticks) / 10_000)
        let thumbIndex = min(max(positionMs / info.intervalMs, 0), info.thumbnailCount - 1)
        let gridSize = max(info.tileWidth * info.tileHeight, 1)
        let tileIndex = thumbIndex / gridSize
        let indexInTile = thumbIndex % gridSize
        let row = indexInTile / info.tileWidth
        let col = indexInTile % info.tileWidth

        guard let cgTile = await loadTile(tileIndex) else { return nil }
        let cropRect = CGRect(x: col * info.width, y: row * info.height, width: info.width, height: info.height)
        guard let cropped = cgTile.cropping(to: cropRect) else { return nil }
        return PlatformImage.from(cgImage: cropped)
    }

    private func loadTile(_ tileIndex: Int) async -> CGImage? {
        if let cached = tileCache[tileIndex] {
            tileOrder.removeAll { $0 == tileIndex }
            tileOrder.append(tileIndex)
            return cached
        }
        if let existing = inFlight[tileIndex] { return await existing.value }
        let task: Task<CGImage?, Never>
        switch tiles {
        case .files(let directory, let fileNames):
            guard fileNames.indices.contains(tileIndex), !fileNames[tileIndex].isEmpty else { return nil }
            let url = directory.appendingPathComponent(fileNames[tileIndex])
            task = Task.detached(priority: .userInitiated) { Self.decoded(CGImageSourceCreateWithURL(url as CFURL, nil)) }
        case .server(let credential, let authHeader, let client, let itemId):
            task = serverTile(tileIndex, url: client.trickplayTileURL(credential: credential, itemId: itemId, width: info.width, tileIndex: tileIndex),
                              authHeader: authHeader)
        }
        inFlight[tileIndex] = task
        let image = await task.value
        inFlight[tileIndex] = nil
        if let image {
            tileCache[tileIndex] = image
            tileOrder.removeAll { $0 == tileIndex }
            tileOrder.append(tileIndex)
            while tileOrder.count > Self.cachedTiles { tileCache[tileOrder.removeFirst()] = nil }
        }
        return image
    }

    private func serverTile(_ tileIndex: Int, url: URL, authHeader: String) -> Task<CGImage?, Never> {
        Task<CGImage?, Never> {
            do {
                var req = URLRequest(url: url)
                // The api_key query param alone 401s on this endpoint — unlike Items/Images,
                // Videos/.../Trickplay actually checks the Authorization header.
                req.setValue(authHeader, forHTTPHeaderField: "Authorization")
                let (data, response) = try await URLSession.arcfin.data(for: req)
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                let image = status == 200
                    ? await Task.detached(priority: .userInitiated) { Self.decoded(CGImageSourceCreateWithData(data as CFData, nil)) }.value
                    : nil
                guard let image else {
                    Self.log.error("Tile \(tileIndex, privacy: .public) fetch failed: status \(status, privacy: .public), \(data.count, privacy: .public) bytes")
                    return nil
                }
                return image
            } catch {
                Self.log.error("Tile \(tileIndex, privacy: .public) request failed: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
    }

    /// Decoded here, off the main thread, rather than when the first crop is drawn.
    private nonisolated static func decoded(_ source: CGImageSource?) -> CGImage? {
        guard let source else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }
}
