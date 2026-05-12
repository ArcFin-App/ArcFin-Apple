import Foundation
import SwiftUI
import Nuke
import NukeUI
import Telemetry

// MARK: - Pipeline

public enum ImageCache: Sendable {

    private static let log = Telemetry.logger(category: "ImageCache")

    public static let shared: ImagePipeline = {
        var config = ImagePipeline.Configuration.withDataCache(name: "com.psmattas.arcfin.images")
        config.dataCachePolicy = .automatic
        return ImagePipeline(configuration: config)
    }()

    /// Warms the Nuke cache for a batch of URLs so they render without a loading delay.
    public static func preheat(urls: [URL]) {
        let requests = urls.map { ImageRequest(url: $0) }
        ImagePreheater(pipeline: shared).startPreheating(with: requests)
    }
}

// MARK: - LazyHeroImage

/// Full-bleed hero backdrop using Nuke's decoded image cache with a smooth crossfade.
/// Avoids the layout-recalculation jump that AsyncImage produces when images swap.
public struct LazyHeroImage<Placeholder: View>: View {
    let url: URL?
    @ViewBuilder let placeholder: () -> Placeholder

    public init(url: URL?, @ViewBuilder placeholder: () -> Placeholder) {
        self.url = url
        self.placeholder = placeholder
    }

    public var body: some View {
        LazyImage(url: url) { state in
            if let image = state.image {
                image.resizable().scaledToFill()
            } else {
                placeholder()
            }
        }
        .pipeline(ImageCache.shared)
        .transition(.fade(duration: 0.35))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
