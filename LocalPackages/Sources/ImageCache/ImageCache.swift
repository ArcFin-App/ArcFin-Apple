import Foundation
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
}
