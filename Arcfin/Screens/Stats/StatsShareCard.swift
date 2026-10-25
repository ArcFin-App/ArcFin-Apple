// SPDX-License-Identifier: AGPL-3.0-or-later

#if !os(tvOS)
import SwiftUI
import ImageIO
import JellyfinAPI

/// A picture of the period's stats to post: rendered here, shared as an image.
struct StatsShareSheet: View {
    let stats: WatchStats
    let name: String?

    @Environment(MediaRepository.self) private var mediaRepo
    @Environment(\.dismiss) private var dismiss
    @State private var format = StatsShareCard.Format.story
    @State private var artwork: StatsShareCard.Artwork?
    @State private var rendered: CGImage?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Picker("Size", selection: $format) {
                    ForEach(StatsShareCard.Format.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                Group {
                    if let rendered {
                        Image(decorative: rendered, scale: 1)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.lg, style: .continuous))
                            .shadow(color: .black.opacity(0.35), radius: 20, y: 10)
                            .accessibilityLabel("Your stats card for \(stats.name)")
                    } else {
                        ProgressView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let rendered {
                    let image = Image(decorative: rendered, scale: 1)
                    ShareLink(item: image, preview: SharePreview("My \(stats.period == .allTime ? "Stats" : stats.name) on Arcfin", image: image)) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.system(.headline))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(DT.Color.accent)
                    .foregroundStyle(DT.Color.onAccent)
                }
            }
            .padding(DT.Spacing.pagePad)
            .screenBackground()
            .navigationTitle("Share Your Stats")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 720)
        #endif
        .task(id: format) {
            if artwork == nil { artwork = await loadArtwork() }
            render()
        }
    }

    private func render() {
        let card = StatsShareCard(stats: stats, name: name, format: format, artwork: artwork ?? .init())
        let renderer = ImageRenderer(content: card.environment(\.colorScheme, .dark))
        renderer.scale = 3
        rendered = renderer.cgImage
    }

    /// ImageRenderer draws only what's already in memory, so the artwork is fetched first.
    private func loadArtwork() async -> StatsShareCard.Artwork {
        let backdropItem = stats.topShows.first?.item ?? stats.topMovies.first?.item
        let backdropURL = backdropItem.flatMap { mediaRepo.imageURL(for: $0, type: .backdrop, fillWidth: 1200) }
        let showURL = stats.topShows.first.flatMap { mediaRepo.imageURL(for: $0.item, fillWidth: 400) }
        let movieURL = stats.topMovies.first.flatMap { mediaRepo.imageURL(for: $0.item, fillWidth: 400) }
        async let backdrop = image(backdropURL)
        async let show = image(showURL)
        async let movie = image(movieURL)
        return await .init(backdrop: backdrop, topShow: show, topMovie: movie)
    }

    private func image(_ url: URL?) async -> CGImage? {
        guard let url, let data = await URLSession.arcfin.imageData(from: url),
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
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

    struct Artwork {
        var backdrop: CGImage?
        var topShow: CGImage?
        var topMovie: CGImage?
    }

    let stats: WatchStats
    let name: String?
    let format: Format
    let artwork: Artwork

    private let cyan = Color(red: 0.024, green: 0.714, blue: 0.831)

    var body: some View {
        let headline = StatsFormat.headline(stats.seconds)
        ZStack {
            background
            VStack(alignment: .leading, spacing: format == .story ? 22 : 14) {
                header
                VStack(alignment: .leading, spacing: 2) {
                    Text(name.map { "\($0)'s \(periodPhrase)" } ?? "My \(periodPhrase)")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(headline.value)
                            .font(.system(size: format == .story ? 76 : 62, weight: .heavy, design: .rounded))
                        Text(headline.unit)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(cyan)
                    }
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    Text("of movies and TV")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
                counts
                if format == .story {
                    if let show = stats.topShows.first {
                        feature(label: "Top show", title: show.item.name,
                                detail: "\(show.episodes) \(show.episodes == 1 ? "episode" : "episodes")", poster: artwork.topShow)
                    }
                    if let movie = stats.topMovies.first {
                        feature(label: "Top movie", title: movie.item.name,
                                detail: movie.playCount > 1 ? "Watched \(movie.playCount) times" : movie.item.productionYear.map(String.init) ?? "", poster: artwork.topMovie)
                    }
                } else if let show = stats.topShows.first {
                    feature(label: "Top show", title: show.item.name,
                            detail: "\(show.episodes) \(show.episodes == 1 ? "episode" : "episodes")", poster: artwork.topShow)
                } else if let movie = stats.topMovies.first {
                    feature(label: "Top movie", title: movie.item.name, detail: "", poster: artwork.topMovie)
                }
                chips
                Spacer(minLength: 0)
                footer
            }
            .padding(26)
        }
        .frame(width: format.size.width, height: format.size.height)
        .clipped()
    }

    private var periodPhrase: String {
        switch stats.period {
        case .week: "week"
        case .month: "month"
        case .year: "year"
        case .allTime: "watch history"
        }
    }

    private var background: some View {
        ZStack {
            Color(red: 0.04, green: 0.04, blue: 0.06)
            if let backdrop = artwork.backdrop {
                Image(decorative: backdrop, scale: 1)
                    .resizable()
                    .scaledToFill()
                    .frame(width: format.size.width, height: format.size.height * 0.55)
                    .clipped()
                    .opacity(0.55)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            LinearGradient(colors: [.black.opacity(0.2), Color(red: 0.04, green: 0.04, blue: 0.06)],
                           startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.6))
            RadialGradient(colors: [cyan.opacity(0.35), .clear], center: UnitPoint(x: 1, y: 1),
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
            Text((stats.period == .allTime ? stats.heading : stats.name).uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(cyan)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(cyan.opacity(0.15), in: Capsule())
        }
    }

    private var counts: some View {
        HStack(spacing: 8) {
            count(stats.movies, stats.movies == 1 ? "Movie" : "Movies")
            count(stats.episodes, stats.episodes == 1 ? "Episode" : "Episodes")
            count(stats.shows, stats.shows == 1 ? "Show" : "Shows")
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

    private func feature(label: String, title: String, detail: String, poster: CGImage?) -> some View {
        HStack(spacing: 12) {
            Group {
                if let poster {
                    Image(decorative: poster, scale: 1).resizable().scaledToFill()
                } else {
                    Color.white.opacity(0.1)
                }
            }
            .frame(width: 46, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(cyan)
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
        let items = [
            stats.genres.first.map { ("theatermasks.fill", $0.name) },
            stats.longestStreak > 1 ? ("flame.fill", "\(stats.longestStreak)-day streak") : nil,
            stats.busiestWeekday.map { ("calendar", "\(Calendar.current.weekdaySymbols[$0])s") },
        ].compactMap { $0 }
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
            Text("Watched on Jellyfin")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
        }
    }
}
#endif
