// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

/// What a share card shows: the watch stats or the listening stats of one period.
enum StatsShareContent {
    case video(WatchStats)
    case music(MusicStats)

    var period: StatsPeriod {
        switch self {
        case .video(let stats): stats.period
        case .music(let stats): stats.period
        }
    }

    var periodName: String {
        switch self {
        case .video(let stats): stats.periodName
        case .music(let stats): stats.periodName
        }
    }

    var periodHeading: String {
        switch self {
        case .video(let stats): stats.periodHeading
        case .music(let stats): stats.periodHeading
        }
    }
}

/// The card itself, always dark, laid out at a fixed size for social posts.
struct StatsShareCard: View {
    enum Format: String, CaseIterable, Identifiable {
        case story, post
        var id: String { rawValue }
        var title: String { self == .story ? String(localized: "Story") : String(localized: "Post") }
        var size: CGSize { self == .story ? CGSize(width: 360, height: 640) : CGSize(width: 360, height: 450) }
    }

    /// The backdrop and the covers of the first and second feature, fetched before rendering.
    struct Artwork {
        var backdrop: CGImage?
        var first: CGImage?
        var second: CGImage?
    }

    let content: StatsShareContent
    let name: String?
    let format: Format
    let artwork: Artwork

    private let coral = Color(red: 1, green: 0.416, blue: 0.302)

    var body: some View {
        let headline = StatsFormat.styled(
            headlineValue,
            value: .system(size: format == .story ? 76 : 62, weight: .heavy, design: .rounded), valueColor: .white,
            unit: .system(size: 20, weight: .bold), unitColor: coral)
        ZStack {
            background
            VStack(alignment: .leading, spacing: format == .story ? 22 : 14) {
                header
                VStack(alignment: .leading, spacing: 2) {
                    Text(owner)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                    Text(headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(headlineCaption)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
                counts
                features
                chips
                Spacer(minLength: 0)
                footer
            }
            .padding(26)
        }
        .frame(width: format.size.width, height: format.size.height)
        .clipped()
    }

    private var headlineValue: AttributedString {
        switch content {
        case .video(let stats): StatsFormat.headline(stats.seconds)
        case .music(let stats): stats.headline
        }
    }

    private var headlineCaption: String {
        switch content {
        case .video: String(localized: "of movies and TV")
        case .music(let stats): stats.seconds == nil ? String(localized: "listens") : String(localized: "of music")
        }
    }

    @ViewBuilder
    private var features: some View {
        switch content {
        case .video(let stats):
            if format == .story {
                if let show = stats.topShows.first {
                    feature(label: String(localized: "Top show"), title: show.item.name,
                            detail: String(localized: "\(show.episodes) episodes"), poster: artwork.first)
                }
                if let movie = stats.topMovies.first {
                    feature(label: String(localized: "Top movie"), title: movie.item.name,
                            detail: movie.playCount > 1 ? String(localized: "Watched \(movie.playCount) times") : movie.item.productionYear.map(String.init) ?? "", poster: artwork.second)
                }
            } else if let show = stats.topShows.first {
                feature(label: String(localized: "Top show"), title: show.item.name,
                        detail: String(localized: "\(show.episodes) episodes"), poster: artwork.first)
            } else if let movie = stats.topMovies.first {
                feature(label: String(localized: "Top movie"), title: movie.item.name, detail: "", poster: artwork.second)
            }
        case .music(let stats):
            if let song = stats.topSongs.first {
                feature(label: String(localized: "Top song"), title: song.name, detail: song.detail ?? "",
                        poster: artwork.first, square: true)
            }
            if format == .story, let artist = stats.topArtists.first {
                feature(label: String(localized: "Top artist"), title: artist.name,
                        detail: String(localized: "\(artist.plays) plays"), poster: artwork.second, square: true)
            }
        }
    }

    /// Whole phrases: the period's word changes with whose it is in some languages.
    private var owner: String {
        let isMusic = if case .music = content { true } else { false }
        return switch (content.period, name, isMusic) {
        case (.week, nil, _): String(localized: "My week")
        case (.month, nil, _): String(localized: "My month")
        case (.year, nil, _): String(localized: "My year")
        case (.allTime, nil, false): String(localized: "My watch history")
        case (.allTime, nil, true): String(localized: "My listening history")
        case (.week, let name?, _): String(localized: "\(name)'s week")
        case (.month, let name?, _): String(localized: "\(name)'s month")
        case (.year, let name?, _): String(localized: "\(name)'s year")
        case (.allTime, let name?, false): String(localized: "\(name)'s watch history")
        case (.allTime, let name?, true): String(localized: "\(name)'s listening history")
        }
    }

    private var background: some View {
        ZStack {
            Color(red: 0.043, green: 0.043, blue: 0.047)
            if let backdrop = artwork.backdrop {
                Image(decorative: backdrop, scale: 1)
                    .resizable()
                    .scaledToFill()
                    .frame(width: format.size.width, height: format.size.height * 0.55)
                    .clipped()
                    .opacity(0.55)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            LinearGradient(colors: [.black.opacity(0.2), Color(red: 0.043, green: 0.043, blue: 0.047)],
                           startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.6))
            RadialGradient(colors: [coral.opacity(0.35), .clear], center: UnitPoint(x: 1, y: 1),
                           startRadius: 0, endRadius: format.size.width)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image("ArcfinLogo")
                .resizable()
                .frame(width: 26, height: 26)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            Text("Arcfin")
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(.white)
            Spacer()
            Text((content.period == .allTime ? content.periodHeading : content.periodName).uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(coral)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(coral.opacity(0.15), in: Capsule())
        }
    }

    private var counts: some View {
        HStack(spacing: 8) {
            switch content {
            case .video(let stats):
                count(stats.movies, stats.movies == 1 ? String(localized: "Movie") : String(localized: "Movies"))
                count(stats.episodes, stats.episodes == 1 ? String(localized: "Episode") : String(localized: "Episodes"))
                count(stats.shows, stats.shows == 1 ? String(localized: "Show") : String(localized: "Shows"))
            case .music(let stats):
                count(stats.songCount, stats.songCount == 1 ? String(localized: "Song") : String(localized: "Songs"))
                count(stats.artistCount, stats.artistCount == 1 ? String(localized: "Artist") : String(localized: "Artists"))
                count(stats.albumCount, stats.albumCount == 1 ? String(localized: "Album") : String(localized: "Albums"))
            }
        }
    }

    private func count(_ value: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(value)")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func feature(label: String, title: String, detail: String, poster: CGImage?, square: Bool = false) -> some View {
        HStack(spacing: 12) {
            Group {
                if let poster {
                    Image(decorative: poster, scale: 1).resizable().scaledToFill()
                } else {
                    Color.white.opacity(0.1)
                }
            }
            .frame(width: square ? 56 : 46, height: square ? 56 : 68)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(coral)
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var chips: some View {
        let items: [(String, String)] = switch content {
        case .video(let stats): [
            stats.genres.first.map { ("theatermasks.fill", $0.name) },
            stats.longestStreak > 1 ? ("flame.fill", String(localized: "\(stats.longestStreak)-day streak")) : nil,
            stats.busiestWeekday.map { ("calendar", Calendar.current.standaloneWeekdaySymbols[$0]) },
        ].compactMap { $0 }
        case .music(let stats): [
            stats.genres.first.map { ("guitars.fill", $0.name) },
            stats.topAlbums.first.map { ("square.stack.fill", $0.name) },
        ].compactMap { $0 }
        }
        return HStack(spacing: 6) {
            ForEach(items, id: \.1) { icon, text in
                HStack(spacing: 4) {
                    Image(systemName: icon)
                    Text(text).lineLimit(1)
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 9).padding(.vertical, 6)
                .background(.white.opacity(0.1), in: Capsule())
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("Made by Arcfin")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
            Text(footerSource)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private var footerSource: String {
        switch content {
        case .video: String(localized: "Watched on Jellyfin")
        case .music(let stats): stats.source == .listenBrainz ? String(localized: "Counted by ListenBrainz") : String(localized: "Played on Jellyfin")
        }
    }
}
