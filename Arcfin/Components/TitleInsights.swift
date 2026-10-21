// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI
import SeerrAPI

/// The lower half of a title's page: review scores, the next episode, where else it's
/// streaming, and a details list. Library titles bring what Jellyfin knows (`detail`);
/// Seerr, when it's set up, adds review scores, streaming services and production facts by
/// the title's TMDB id. Without Seerr, only the Jellyfin part shows.
struct TitleInsights: View {
    let tmdbId: Int?
    let mediaType: RequestMediaType?
    var detail: MediaItemDetail? = nil

    @Environment(SeerrRepository.self) private var seerrRepo
    @Environment(\.openURL) private var openURL

    @State private var info: SeerrRelatedInfo?
    @State private var ratings: SeerrRatings?
    @State private var region = ""

    var body: some View {
        VStack(alignment: .leading, spacing: DT.Spacing.lg) {
            if let ratings, !ratings.isEmpty { ratingsRow(ratings) }
            if let next = info?.nextEpisode { nextEpisodeRow(next) }
            if let watch = info?.watch, !watch.isEmpty {
                whereToWatch(watch)
            }
            if !detailRows.isEmpty { detailsList }
            if !links.isEmpty { linksRow }
        }
        .task(id: tmdbId) { await load() }
    }

    private func load() async {
        guard seerrRepo.hasCatalog, let tmdbId, let mediaType else { return }
        region = await seerrRepo.region()
        async let fetchedInfo = seerrRepo.relatedInfo(mediaType: mediaType, tmdbId: tmdbId)
        async let fetchedRatings = seerrRepo.ratings(mediaType: mediaType, tmdbId: tmdbId)
        (info, ratings) = await (fetchedInfo, fetchedRatings)
    }

    // MARK: - Ratings

    private func ratingsRow(_ ratings: SeerrRatings) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                if let score = ratings.criticsScore {
                    scoreChip(
                        systemImage: score >= 60 ? "checkmark.seal.fill" : "xmark.seal.fill",
                        tint: score >= 60 ? Color(hex: "10b981") : Color(hex: "f59e0b"),
                        value: "\(score)%", label: ratings.criticsRating ?? "Critics",
                        url: ratings.rottenTomatoesURL)
                }
                if let score = ratings.audienceScore {
                    scoreChip(
                        systemImage: "person.3.fill",
                        tint: score >= 60 ? Color(hex: "10b981") : Color(hex: "f59e0b"),
                        value: "\(score)%", label: "Audience", url: ratings.rottenTomatoesURL)
                }
                if let imdb = ratings.imdbScore {
                    scoreChip(systemImage: "star.fill", tint: Color(hex: "f5c518"),
                              value: String(format: "%.1f", imdb), label: "IMDb", url: ratings.imdbURL)
                }
            }
        }
    }

    private func scoreChip(systemImage: String, tint: Color, value: String, label: String, url: URL?) -> some View {
        Button { if let url { openURL(url) } } label: {
            HStack(spacing: 8) {
                Image(systemName: systemImage).foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 0) {
                    Text(value).font(.system(.subheadline, weight: .bold)).foregroundStyle(DT.Color.textPrimary)
                    Text(label).font(.caption2).foregroundStyle(DT.Color.textSecondary)
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(DT.Color.backgroundSecondary.opacity(0.8), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(url == nil)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value)")
    }

    // MARK: - Next episode

    private func nextEpisodeRow(_ next: SeerrNextEpisode) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.title3)
                .foregroundStyle(DT.Color.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Next Episode")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DT.Color.textSecondary)
                Text("S\(next.seasonNumber) · E\(next.episodeNumber)\(next.name.isEmpty ? "" : " — \(next.name)")")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DT.Color.textPrimary)
                    .lineLimit(1)
                if let date = next.airDate {
                    Text(date.formatted(date: .complete, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(DT.Color.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(DT.Color.backgroundSecondary.opacity(0.8), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Where to watch

    /// Every way to watch it in Seerr's country, grouped the way the services sell it.
    private func whereToWatch(_ watch: SeerrWatchAvailability) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(region.isEmpty ? "Where to Watch" : "Where to Watch in \(Locale.current.localizedString(forRegionCode: region) ?? region)")
                .font(DT.Font.cardTitle)
                .foregroundStyle(DT.Color.textPrimary)
            providerGroup("Stream", watch.streaming)
            providerGroup("Free", watch.free)
            providerGroup("With Ads", watch.ads)
            providerGroup("Rent", watch.rent)
            providerGroup("Buy", watch.buy)
            // JustWatch supplies this data through TMDB, which asks for it to be credited.
            Text("Availability from JustWatch")
                .font(.caption2)
                .foregroundStyle(DT.Color.textSecondary.opacity(0.7))
        }
    }

    @ViewBuilder
    private func providerGroup(_ title: String, _ providers: [SeerrWatchProvider]) -> some View {
        if !providers.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DT.Color.textSecondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(providers) { provider in
                            VStack(spacing: 5) {
                                CachedAsyncImage(url: provider.logoURL) { phase in
                                    switch phase {
                                    case .success(let image): image.resizable().scaledToFill()
                                    default: DT.Color.backgroundTertiary
                                    }
                                }
                                .frame(width: 52, height: 52)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1))
                                Text(provider.name)
                                    .font(.caption2)
                                    .foregroundStyle(DT.Color.textPrimary.opacity(0.85))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(width: 70)
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("\(provider.name), \(title.lowercased())")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Details

    private var detailRows: [(String, String)] {
        var rows: [(String, String)] = []
        let original = detail?.originalTitle ?? info?.originalTitle
        let name = detail?.item.name
        if let original, !original.isEmpty, original != name { rows.append(("Original Title", original)) }
        if let language = info?.originalLanguage, let languageName = Locale.current.localizedString(forLanguageCode: language) {
            rows.append(("Original Language", languageName))
        }
        if let status = detail?.status ?? info?.status { rows.append(("Status", status == "Continuing" ? "Returning" : status)) }
        if let premiere = detail?.premiereDate {
            rows.append((detail?.item.type == .series ? "First Aired" : "Released", premiere.formatted(date: .long, time: .omitted)))
        }
        if let end = detail?.endDate, detail?.status == "Ended" { rows.append(("Last Aired", end.formatted(date: .long, time: .omitted))) }
        if let days = detail?.airDays, !days.isEmpty {
            rows.append(("Airs", days.joined(separator: ", ") + (detail?.airTime.map { " at \($0)" } ?? "")))
        }
        if let seasons = info?.numberOfSeasons { rows.append(("Seasons", "\(seasons)")) }
        if let creators = info?.createdBy, !creators.isEmpty { rows.append(("Created by", creators.joined(separator: ", "))) }
        if let networks = info?.networks, !networks.isEmpty { rows.append(("Network", networks.prefix(3).joined(separator: ", "))) }
        let studios = detail?.studios ?? []
        if !studios.isEmpty, mediaType != .tv { rows.append(("Studio", studios.prefix(3).joined(separator: ", "))) }
        let countries = info?.countries.isEmpty == false ? info!.countries : (detail?.productionLocations ?? [])
        if !countries.isEmpty { rows.append(("Country", countries.prefix(3).joined(separator: ", "))) }
        if let budget = info?.budget { rows.append(("Budget", money(budget))) }
        if let revenue = info?.revenue { rows.append(("Box Office", money(revenue))) }
        for file in detail?.files ?? [] {
            var parts: [String] = []
            if let container = file.container { parts.append(container.uppercased()) }
            if let size = file.sizeBytes, size > 0 { parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)) }
            if let bitrate = file.bitrate, bitrate > 0 { parts.append("\(bitrate / 1_000_000) Mb/s") }
            if !parts.isEmpty {
                let label = (detail?.files.count ?? 0) > 1 ? (file.name ?? "File") : "File"
                rows.append((label, parts.joined(separator: " · ")))
            }
        }
        if let tags = detail?.tags, !tags.isEmpty { rows.append(("Tags", tags.prefix(6).joined(separator: ", "))) }
        return rows
    }

    private var detailsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Details")
                .font(DT.Font.cardTitle)
                .foregroundStyle(DT.Color.textPrimary)
            VStack(spacing: 0) {
                ForEach(Array(detailRows.enumerated()), id: \.offset) { index, row in
                    if index > 0 { Divider().overlay(Color.white.opacity(0.05)).padding(.leading, 14) }
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.0)
                            .font(.system(.footnote, weight: .semibold))
                            .foregroundStyle(DT.Color.textSecondary)
                        Spacer(minLength: 16)
                        Text(row.1)
                            .font(.footnote)
                            .foregroundStyle(DT.Color.textPrimary)
                            .multilineTextAlignment(.trailing)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .accessibilityElement(children: .combine)
                }
            }
            .background(DT.Color.backgroundSecondary.opacity(0.7), in: RoundedRectangle(cornerRadius: DT.Radius.md))
        }
    }

    // MARK: - Links

    private var links: [ExternalLink] {
        var result = detail?.externalLinks ?? []
        if result.isEmpty, let imdb = info?.imdbId, let url = URL(string: "https://www.imdb.com/title/\(imdb)") {
            result.append(ExternalLink(name: "IMDb", url: url))
        }
        return result
    }

    private var linksRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(links) { link in
                    Button { openURL(link.url) } label: {
                        Label(link.name, systemImage: "arrow.up.right.square")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 12)
                            .frame(minHeight: 36)
                            .background(Color.white.opacity(0.08), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(DT.Color.textPrimary)
                }
            }
        }
    }

    private func money(_ amount: Int) -> String {
        amount.formatted(.currency(code: "USD").notation(.compactName))
    }
}
