#if canImport(UIKit)
import UIKit
import JellyfinAPI
import AuthCore

/// Fetches and crops Jellyfin trickplay sprite-sheet tiles into individual scrub-preview
/// thumbnails, caching whole tiles (each holds many frames) rather than individual crops.
@MainActor
final class TrickplayLoader {
    private let credential: ServerCredential
    private let client: JellyfinMediaClient
    private let itemId: String
    private let info: JellyfinTrickplayInfo
    private var tileCache: [Int: UIImage] = [:]
    private var inFlight: [Int: Task<UIImage?, Never>] = [:]

    init(credential: ServerCredential, client: JellyfinMediaClient, itemId: String, info: JellyfinTrickplayInfo) {
        self.credential = credential
        self.client = client
        self.itemId = itemId
        self.info = info
    }

    func thumbnail(forPositionTicks ticks: Int64) async -> UIImage? {
        guard info.intervalMs > 0, info.thumbnailCount > 0 else { return nil }
        let positionMs = Int(Double(ticks) / 10_000)
        let thumbIndex = min(max(positionMs / info.intervalMs, 0), info.thumbnailCount - 1)
        let gridSize = max(info.tileWidth * info.tileHeight, 1)
        let tileIndex = thumbIndex / gridSize
        let indexInTile = thumbIndex % gridSize
        let row = indexInTile / info.tileWidth
        let col = indexInTile % info.tileWidth

        guard let tileImage = await loadTile(tileIndex), let cgTile = tileImage.cgImage else { return nil }
        let cropRect = CGRect(x: col * info.width, y: row * info.height, width: info.width, height: info.height)
        guard let cropped = cgTile.cropping(to: cropRect) else { return nil }
        return UIImage(cgImage: cropped)
    }

    private func loadTile(_ tileIndex: Int) async -> UIImage? {
        if let cached = tileCache[tileIndex] { return cached }
        if let existing = inFlight[tileIndex] { return await existing.value }
        let url = client.trickplayTileURL(credential: credential, itemId: itemId, width: info.width, tileIndex: tileIndex)
        let task = Task<UIImage?, Never> {
            guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
            return UIImage(data: data)
        }
        inFlight[tileIndex] = task
        let image = await task.value
        inFlight[tileIndex] = nil
        if let image { tileCache[tileIndex] = image }
        return image
    }
}
#endif
