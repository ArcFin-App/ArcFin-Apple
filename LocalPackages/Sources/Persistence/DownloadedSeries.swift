import Foundation
import SwiftData

/// Series-level metadata for downloaded episodes — one row per series that has at least one
/// downloaded episode, fetched once the first time any of its episodes is downloaded so the
/// downloads list can show a proper series container (poster, backdrop, overview) instead of
/// just grouping episodes under a plain text header.
@Model
public final class DownloadedSeries {
    @Attribute(.unique) public var seriesId: String

    public var name: String
    public var overview: String?
    public var genres: [String]
    public var communityRating: Double?
    public var officialRating: String?
    public var productionYear: Int?

    /// Resolved against DownloadStore.directory(for: seriesId) at read time — same file
    /// layout convention as DownloadedItem, just keyed by the series' own id.
    public var posterFileName: String?
    public var backdropFileName: String?

    public init(
        seriesId: String, name: String, overview: String? = nil, genres: [String] = [],
        communityRating: Double? = nil, officialRating: String? = nil, productionYear: Int? = nil,
        posterFileName: String? = nil, backdropFileName: String? = nil
    ) {
        self.seriesId = seriesId
        self.name = name
        self.overview = overview
        self.genres = genres
        self.communityRating = communityRating
        self.officialRating = officialRating
        self.productionYear = productionYear
        self.posterFileName = posterFileName
        self.backdropFileName = backdropFileName
    }
}
