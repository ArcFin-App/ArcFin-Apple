// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI
import SeerrAPI
import AuthCore

/// What Home's focused card is, for the hero. Cards report into it as focus moves, so Home's
/// own body doesn't depend on focus and a move doesn't rebuild every shelf (#655).
@MainActor @Observable
final class TVHomeFocus {
    /// The last library title focused. Never cleared: focus moving to the hero's own buttons
    /// keeps the hero on it.
    private(set) var itemID: String?
    /// The row of the focused card, or nil while it's on something that isn't a card.
    private(set) var row: String?
    /// Spotlight Home: the focused card's row and the title its hero shows.
    private(set) var modernRow: String?
    private(set) var modernHero: TVHomeHeroSubject?
    /// Goes up on every card focus, for the hero to react to.
    private(set) var moves = 0

    func cardFocused(row: String, item: TVHomeHeroSubject?) {
        self.row = row
        if case .media(let media) = item { itemID = media.id }
        moves += 1
    }

    func modernCardFocused(row: String, item: TVHomeHeroSubject) {
        modernRow = row
        modernHero = item
    }
}

/// What a Home card stands for in the hero: a library title or a Seerr one.
enum TVHomeHeroSubject: Equatable {
    case media(MediaItem)
    case seerr(SeerrItem)

    var id: String {
        switch self {
        case .media(let item): "media-\(item.id)"
        case .seerr(let item): "seerr-\(item.id)"
        }
    }
}

enum TVHomeText {
    static let continueWatchingRow = "Continue Watching"

    /// "S1 · E4 · Episode Name" for episodes, the title for everything else.
    static func title(_ item: MediaItem) -> String {
        guard item.type == .episode else { return item.name }
        let s = item.parentIndexNumber.map { "S\($0)" }
        let e = item.indexNumber.map { "E\($0)" }
        let badge = [s, e].compactMap { $0 }.joined(separator: " · ")
        return badge.isEmpty ? item.name : "\(badge) · \(item.name)"
    }

    /// The show for episodes, the year for everything else.
    static func subtitle(_ item: MediaItem) -> String? {
        if item.type == .episode { return item.seriesName }
        return item.productionYear.map { String($0) }
    }
}

/// Home's shelves under the hero, or Spotlight Home's rows with Continue Watching first. Its
/// inputs don't change as focus moves, so SwiftUI keeps it as it is while the hero follows
/// focus.
struct TVHomeShelves: View {
    let shelves: [HomeShelf]
    let modernHome: Bool
    let model: HomeModel
    let focus: TVHomeFocus

    @Environment(AuthManager.self) private var authManager
    @Environment(MediaRepository.self) private var mediaRepo
    @Environment(SeerrRepository.self) private var seerrRepo
    @AppStorage("seerrDiscoverEnabled") private var seerrDiscoverEnabled = true
    @AppStorage("mergeContinueWatchingAndUpNext") private var mergeContinueWatchingAndUpNext = false
    @AppStorage(StreamingServicePrefs.key) private var streamingServicesData = Data()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if modernHome { continueWatchingRow }
            ForEach(shelves) { shelf in
                shelfView(for: shelf)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("shelf.\(shelf.rawValue)")
            }
        }
    }

    @ViewBuilder
    private var continueWatchingRow: some View {
        let items = mergeContinueWatchingAndUpNext ? HomeModel.continueAndNext(in: mediaRepo) : mediaRepo.continueWatching
        if !items.isEmpty {
            let title = TVHomeText.continueWatchingRow
            row(title: title, rowID: title) {
                ForEach(items) { item in
                    Button { model.detailItem = item } label: {
                        PosterCard(
                            title: TVHomeText.title(item),
                            subtitle: TVHomeText.subtitle(item),
                            progress: item.userData?.playedPercentage.map { $0 / 100 },
                            imageURL: HomeArtwork.tvURL(for: item, in: mediaRepo)
                        )
                        .unwatchedBadge(item)
                        .background { probe(row: title, subject: .media(item)) }
                    }
                    .buttonStyle(TVCardButtonStyle())
                    .focusEffectDisabled()
                    .contextMenu { TVHomeItemMenu(item: item) { model.playbackRequest = $0 } }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("shelf.\(HomeShelf.continueWatching.rawValue)")
        }
    }

    @ViewBuilder
    private func shelfView(for shelf: HomeShelf) -> some View {
        switch shelf {
        case .continueWatching:
            EmptyView()
        case .nextUp:
            if !mergeContinueWatchingAndUpNext, !mediaRepo.nextUp.isEmpty {
                mediaShelf(title: String(localized: "Next Up"), items: mediaRepo.nextUp)
            }
        case .recentlyAddedMovies:
            if !mediaRepo.recentlyAddedMovies.isEmpty {
                mediaShelf(title: String(localized: "Recently Added Movies"), badge: String(localized: "NEW"), items: mediaRepo.recentlyAddedMovies)
            }
        case .recentlyAddedShows:
            if !mediaRepo.recentlyAddedShows.isEmpty {
                mediaShelf(title: String(localized: "Recently Added Shows"), badge: String(localized: "NEW"), items: mediaRepo.recentlyAddedShows)
            }
        case .recentlyReleasedMovies:
            if !mediaRepo.recentlyReleasedMovies.isEmpty {
                mediaShelf(title: String(localized: "Recently Released Movies"), items: mediaRepo.recentlyReleasedMovies)
            }
        case .recentlyAiredEpisodes:
            if !mediaRepo.recentlyAiredEpisodes.isEmpty {
                mediaShelf(title: String(localized: "Recently Aired Episodes"), items: mediaRepo.recentlyAiredEpisodes)
            }
        case .watchAgain:
            if !mediaRepo.watchAgain.isEmpty {
                mediaShelf(title: String(localized: "Watch Again"), items: mediaRepo.watchAgain)
            }
        case .serverPicks:
            ForEach(mediaRepo.promotedCollections, id: \.collection.id) { shelf in
                mediaShelf(title: shelf.collection.name, rowID: "picks-\(shelf.collection.id)", items: shelf.items)
            }
        case .genreShelves:
            ForEach(mediaRepo.genreShelves, id: \.genre) { shelf in
                mediaShelf(title: String(localized: "More \(shelf.genre)"), rowID: "genre-\(shelf.genre)", items: shelf.items)
            }
        case .becauseYouWatched:
            if let recommendation = mediaRepo.becauseYouWatched {
                mediaShelf(title: String(localized: "Because You Watched \(recommendation.source.name)"), rowID: HomeShelf.becauseYouWatched.rawValue, items: recommendation.items)
            }
        case .favorites:
            if !mediaRepo.favorites.isEmpty {
                mediaShelf(title: String(localized: "Favorites"), items: mediaRepo.favorites)
            }
        case .topRatedUnwatched:
            if !mediaRepo.topRatedUnwatched.isEmpty {
                mediaShelf(title: String(localized: "Top Rated, Unwatched"), items: mediaRepo.topRatedUnwatched)
            }
        case .suggested:
            if !mediaRepo.suggestions.isEmpty {
                mediaShelf(title: String(localized: "Suggested for You"), items: mediaRepo.suggestions)
            }
        case .recommendations:
            ForEach(mediaRepo.recommendations) { category in
                mediaShelf(title: HomeShelfLoader.recommendationTitle(category), rowID: "recommendation-\(category.recommendationType)-\(category.id)", items: category.items)
            }
        case .nowAvailable:
            if seerrRepo.isConfigured, !model.nowAvailable.isEmpty {
                mediaShelf(title: String(localized: "Now Available"), items: model.nowAvailable)
            }
        case .streamingServices:
            if seerrRepo.hasCatalog {
                ForEach(StreamingServicePrefs.decode(streamingServicesData)) { provider in
                    if let items = model.serviceRows[provider.id], !items.isEmpty {
                        seerrShelf(title: String(localized: "Popular on \(provider.name)"), rowID: "service-\(provider.id)", items: items)
                    }
                }
            }
        case .seerrWatchlist:
            if seerrRepo.isConfigured, seerrDiscoverEnabled, !seerrRepo.watchlist.isEmpty {
                seerrShelf(title: String(localized: "Watchlist"), items: seerrRepo.watchlist)
            }
        case .seerrTrending:
            if seerrRepo.hasCatalog, seerrDiscoverEnabled, !seerrRepo.trending.isEmpty {
                seerrShelf(title: String(localized: "Trending"), items: seerrRepo.trending)
            }
        case .seerrPopularMovies:
            if seerrRepo.hasCatalog, seerrDiscoverEnabled, !seerrRepo.popularMovies.isEmpty {
                seerrShelf(title: String(localized: "Popular Movies"), items: seerrRepo.popularMovies)
            }
        case .seerrPopularSeries:
            if seerrRepo.hasCatalog, seerrDiscoverEnabled, !seerrRepo.popularTV.isEmpty {
                seerrShelf(title: String(localized: "Popular Series"), items: seerrRepo.popularTV)
            }
        case .liveFavoriteChannels, .liveOnNow, .liveRecentChannels:
            if HomeShelf.hasLiveTV(in: mediaRepo) {
                liveTVShelf(shelf)
            }
        }
    }

    /// A Live TV shelf: channels or what's on now, each playing its channel.
    private func liveTVShelf(_ shelf: HomeShelf) -> some View {
        let live = model.liveTV
        let entries: [(channel: LiveTVChannel, program: LiveTVProgram?)] = switch shelf {
        case .liveFavoriteChannels: live.favorites.map { ($0, nil) }
        case .liveRecentChannels: live.recents.map { ($0, nil) }
        default: live.onNow.map { (LiveTVChannel(id: $0.channelId, name: $0.channelName ?? "", currentProgram: $0), $0) }
        }
        let queue = entries.map(\.channel)
        return VStack(spacing: 0) {
            if !entries.isEmpty {
                row(title: shelf.title, rowID: shelf.rawValue) {
                    ForEach(entries, id: \.channel.id) { entry in
                        Button { live.play(entry.channel, among: queue, model: model) } label: {
                            LiveTVHomeCard(channel: entry.channel, program: entry.program)
                                .background { probe(row: shelf.rawValue, subject: nil) }
                        }
                        .buttonStyle(TVCardButtonStyle())
                        .focusEffectDisabled()
                    }
                }
            }
        }
        .task { await live.load(shelf, authManager: authManager) }
    }

    private func mediaShelf(title: String, rowID: String? = nil, badge: String? = nil, items: [MediaItem]) -> some View {
        let rowID = rowID ?? title
        return row(title: title, rowID: rowID, badge: badge) {
            ForEach(items) { item in
                NavigationLink(value: item) {
                    PosterCard(
                        title: item.name,
                        subtitle: item.productionYear.map { String($0) },
                        imageURL: mediaRepo.tvImageURL(for: item, fillWidth: 640)
                    )
                    .unwatchedBadge(item)
                    .background { probe(row: rowID, subject: .media(item)) }
                }
                .buttonStyle(TVCardButtonStyle())
                .focusEffectDisabled()
                .contextMenu { TVHomeItemMenu(item: item) { model.playbackRequest = $0 } }
            }
        }
    }

    private func seerrShelf(title: String, rowID: String? = nil, items: [SeerrItem]) -> some View {
        let rowID = rowID ?? title
        return row(title: title, rowID: rowID) {
            ForEach(items) { item in
                Button { openSeerrShelfItem(item) } label: {
                    PosterCard(
                        title: item.title,
                        subtitle: [item.year, mediaRepo.hasInLibrary(item) ? "In Library" : nil]
                            .compactMap { $0 }.joined(separator: " · ").nilIfEmpty,
                        imageURL: item.backdropURL ?? item.posterURL
                    )
                    .background { probe(row: rowID, subject: .seerr(item)) }
                }
                .buttonStyle(TVCardButtonStyle())
                .focusEffectDisabled()
            }
        }
    }

    /// The library's own copy when the server has the title, even where Seerr hasn't caught
    /// up yet; otherwise the title's Seerr page.
    private func openSeerrShelfItem(_ item: SeerrItem) {
        Task {
            let local = await model.libraryCopy(of: item, authManager: authManager)
            if let local { model.detailItem = local } else { model.seerrDetailItem = item }
        }
    }

    /// Reports the card's focus. Classic Home's hero only follows library titles; Spotlight
    /// Home's follows Seerr ones too.
    private func probe(row: String, subject: TVHomeHeroSubject?) -> some View {
        CardFocusProbe { [focus, modernHome] in
            focus.cardFocused(row: row, item: subject)
            if modernHome, let subject { focus.modernCardFocused(row: row, item: subject) }
        }
    }

    /// `rowID` tells rows apart where titles repeat, as Recommendations' can.
    private func row<Content: View>(
        title: String,
        rowID: String,
        badge: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 23, weight: .bold))
                    .foregroundStyle(DT.Color.textPrimary)
                if let badge {
                    Text(badge)
                        .font(.system(size: 23, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(Capsule().fill(DT.Color.accent.opacity(0.3)))
                        .overlay(Capsule().stroke(DT.Color.accent.opacity(0.5), lineWidth: 1))
                }
            }
            .padding(.horizontal, 80)
            .padding(.bottom, 14)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) { content() }
                    .padding(.horizontal, 80)
                    .padding(.top, 20)
                    .focusSection()
            }
            .scrollClipDisabled()
        }
        .padding(.bottom, 40)
        .focusSection()
        .background {
            if modernHome {
                GeometryReader { proxy in
                    Color.clear.preference(key: ModernRowHeights.self, value: [.init(id: rowID, height: proxy.size.height)])
                }
            }
        }
    }
}

/// Home rebuilds this only when the shelves or the layout change. The shelf list is worked out
/// afresh on every Home redraw, so comparing it by value is what keeps a focus move from
/// rebuilding every shelf. The shelves' own data still updates them directly.
extension TVHomeShelves: @MainActor Equatable {
    static func == (lhs: TVHomeShelves, rhs: TVHomeShelves) -> Bool {
        lhs.shelves == rhs.shelves && lhs.modernHome == rhs.modernHome
            && lhs.model === rhs.model && lhs.focus === rhs.focus
    }
}

/// A Home card's long-press menu.
struct TVHomeItemMenu: View {
    let item: MediaItem
    let play: (PlaybackRequest) -> Void

    var body: some View {
        if item.type == .movie || item.type == .episode {
            let ticks = item.userData?.played == true ? 0 : (item.userData?.playbackPositionTicks ?? 0)
            Button {
                play(PlaybackRequest(item: item, startTicks: ticks))
            } label: {
                Label(ticks > 0 ? "Resume" : "Play", systemImage: "play.fill")
            }
        }
        ItemQuickActions(item: item)
        Label(item.name, systemImage: item.type == .series ? "tv" : "film")
        if let year = item.productionYear { Label(String(year), systemImage: "calendar") }
        if let rating = item.communityRating {
            Label(String(localized: "\(rating.ratingText) / 10"), systemImage: "star.fill")
        }
    }
}

/// Each Spotlight Home row's height, in the order the rows are stacked.
struct ModernRowHeights: PreferenceKey {
    struct Row: Equatable {
        let id: String
        let height: CGFloat
    }

    static let defaultValue: [Row] = []

    static func reduce(value: inout [Row], nextValue: () -> [Row]) {
        value += nextValue()
    }
}

/// Tells Home when a card takes focus: inside a button's label, `isFocused` is the button's
/// own focus.
struct CardFocusProbe: View {
    let onFocus: () -> Void
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Color.clear
            .onChange(of: isFocused) { _, focused in
                if focused { onFocus() }
            }
    }
}
