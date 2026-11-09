// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import SwiftUI
import Nuke
import AuthCore
import JellyfinAPI
import Telemetry

// MARK: - Pipeline

public enum ImageCache: Sendable {

    private static let log = Telemetry.logger(category: "ImageCache")

    /// Rebuilt when the custom headers change, keeping the same on-disk cache.
    public static var shared: ImagePipeline {
        PipelineBox.pipeline(for: CustomHTTPHeaders.current)
    }

    private enum PipelineBox {
        private static let lock = NSLock()
        nonisolated(unsafe) private static var cached: (headers: [String: String], pipeline: ImagePipeline)?

        static func pipeline(for headers: [String: String]) -> ImagePipeline {
            lock.lock()
            defer { lock.unlock() }
            if let cached, cached.headers == headers { return cached.pipeline }
            var config = ImagePipeline.Configuration.withDataCache(name: "com.psmattas.arcfin.images")
            config.dataCachePolicy = .automatic
            if !headers.isEmpty {
                let session = URLSessionConfiguration.default
                session.httpAdditionalHeaders = headers
                session.urlCache = nil
                config.dataLoader = DataLoader(configuration: session)
            }
            let pipeline = ImagePipeline(configuration: config)
            cached = (headers, pipeline)
            return pipeline
        }
    }

    /// Bytes the on-disk image cache currently holds.
    public static var diskCacheSize: Int {
        (shared.configuration.dataCache as? DataCache)?.totalSize ?? 0
    }

    /// Empties both the decoded in-memory cache and the on-disk one; images re-download on
    /// demand afterwards.
    public static func clear() {
        shared.cache.removeAll()
        (shared.configuration.dataCache as? DataCache)?.removeAll()
    }

    #if canImport(UIKit)
    public typealias PlatformImage = UIImage
    #elseif canImport(AppKit)
    public typealias PlatformImage = NSImage
    #endif

    /// An already decoded image from the in-memory cache, if there is one: lets a view show
    /// it on its very first frame instead of flashing a placeholder.
    public static func memoryImage(for url: URL) -> PlatformImage? {
        shared.cache[ImageRequest(url: url)]?.image
    }

    /// Loads through the shared pipeline: memory cache, then disk cache, then network, with
    /// decoding off the main thread and duplicate in-flight requests coalesced.
    public static func load(_ url: URL) async throws -> PlatformImage {
        do {
            return try await shared.image(for: url)
        } catch {
            // Jellyfin's resize cache can answer one size of an image with an empty 200
            // forever; the original size still loads.
            guard !Task.isCancelled, let original = JellyfinMediaClient.unresizedImageURL(url) else { throw error }
            let image = try await shared.image(for: original)
            shared.cache[ImageRequest(url: url)] = ImageContainer(image: image)
            return image
        }
    }

    /// Loads all URLs into the Nuke decoded cache concurrently so images render
    /// without a network round-trip or decode stall.
    public static func preheat(urls: [URL]) {
        let captured = urls
        Task.detached(priority: .utility) {
            await withTaskGroup(of: Void.self) { group in
                for url in captured {
                    group.addTask { _ = try? await ImageCache.load(url) }
                }
            }
        }
    }
}

// MARK: - LazyHeroImage

/// Full-bleed hero backdrop backed by Nuke's decoded image cache.
/// Crossfades between images using SwiftUI animation — no layout jump.
public struct LazyHeroImage: View {
    public let url: URL?
    private let placeholder: AnyView

    @State private var displayed: Image?
    @State private var version: Int = 0

    public init<P: View>(url: URL?, @ViewBuilder placeholder: () -> P) {
        self.url = url
        self.placeholder = AnyView(placeholder())
    }

    public var body: some View {
        // Overlays keep the image's own size out of layout: filling a frame with art that isn't
        // the frame's shape made this view taller or wider than the screen, which moved
        // everything laid out around it.
        Color.clear
            .overlay { placeholder }
            .overlay {
                if let displayed {
                    displayed
                        .resizable()
                        .scaledToFill()
                        .id(version)
                        .transition(.opacity)
                }
            }
        .task(id: url) {
            guard let url else { return }
            guard let response = try? await ImageCache.load(url) else { return }
            #if canImport(UIKit)
            let loaded = Image(uiImage: response)
            #else
            let loaded = Image(nsImage: response)
            #endif
            withAnimation(.easeInOut(duration: 0.35)) {
                displayed = loaded
                version &+= 1
            }
        }
    }
}
