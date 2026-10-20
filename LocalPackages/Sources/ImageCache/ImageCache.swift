// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import SwiftUI
import Nuke
import Telemetry

// MARK: - Pipeline

public enum ImageCache: Sendable {

    private static let log = Telemetry.logger(category: "ImageCache")

    public static let shared: ImagePipeline = {
        var config = ImagePipeline.Configuration.withDataCache(name: "com.psmattas.arcfin.images")
        config.dataCachePolicy = .automatic
        return ImagePipeline(configuration: config)
    }()

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

    /// Loads all URLs into the Nuke decoded cache concurrently so images render
    /// without a network round-trip or decode stall.
    public static func preheat(urls: [URL]) {
        let captured = urls
        Task.detached(priority: .utility) {
            await withTaskGroup(of: Void.self) { group in
                for url in captured {
                    group.addTask { _ = try? await ImageCache.shared.image(for: url) }
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
        ZStack {
            placeholder
            if let displayed {
                displayed
                    .resizable()
                    .scaledToFill()
                    .id(version)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: url) {
            guard let url else { return }
            guard let response = try? await ImageCache.shared.image(for: url) else { return }
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
