// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI
import SeerrAPI
import AuthCore

// MARK: - Hero

/// The hero at the top of Home on iPhone, iPad and Mac. Each platform draws the slides
/// behind it.
struct HomeHeroBanner<Background: View>: View {
    let isPortrait: Bool
    let items: [MediaItem]
    let carousel: HomeHeroCarousel
    let openItem: (MediaItem) -> Void
    @ViewBuilder let background: Background

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                background
                    .overlay(imageFade.allowsHitTesting(false))
                    .animation(DT.Animation.slow, value: carousel.index)
                    .contentShape(Rectangle())
                    // simultaneousGesture, not .onTapGesture directly — a plain tap gesture
                    // stacked on top of the page-style TabView below was winning gesture
                    // priority and blocking swipe-to-change-page entirely.
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            if let item = items[safe: carousel.index] { openItem(item) }
                        }
                    )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            HStack(spacing: 0) {
                LinearGradient(colors: [DT.Color.backgroundPrimary.opacity(0.3), .clear],
                               startPoint: .leading, endPoint: .trailing).frame(width: 48)
                Spacer()
                LinearGradient(colors: [.clear, DT.Color.backgroundPrimary.opacity(0.3)],
                               startPoint: .leading, endPoint: .trailing).frame(width: 48)
            }
            .allowsHitTesting(false)

            HomeHeroInfo(items: items, carousel: carousel, openItem: openItem)
                .padding(.bottom, isPortrait ? 32 : 24)
        }
        .background(DT.Color.backgroundPrimary)
    }

    private var imageFade: some View {
        LinearGradient(
            stops: [.init(color: .clear, location: 0.3),
                    .init(color: DT.Color.backgroundPrimary.opacity(0.5), location: 0.75),
                    .init(color: DT.Color.backgroundPrimary, location: 1)],
            startPoint: .top, endPoint: .bottom
        )
    }
}

/// Shown behind a hero slide whose image is missing or still loading.
struct HomeHeroPlaceholder: View {
    let index: Int

    var body: some View {
        let p: [[Color]] = [
            [Color(hex: "2A1410"), Color(hex: "140C0B")],
            [Color(hex: "1c0e00"), Color(hex: "0e0a00")],
            [Color(hex: "1A1A1D"), Color(hex: "0B0B0C")],
        ]
        return LinearGradient(colors: p[index % p.count] + [DT.Color.backgroundPrimary],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// The current slide's logo, details, Play and More Info, and the page dots.
private struct HomeHeroInfo: View {
    let items: [MediaItem]
    let carousel: HomeHeroCarousel
    let openItem: (MediaItem) -> Void

    @Environment(MediaRepository.self) private var mediaRepo

    private var heroIsResumable: Bool {
        guard let ud = items[safe: carousel.index]?.userData else { return false }
        return ud.playbackPositionTicks > 0 && !ud.played
    }

    private var heroEpisodeLabel: String? {
        guard let item = items[safe: carousel.index] else { return nil }
        return HomeText.episodeLabel(item)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let item = items[safe: carousel.index] {
                CachedAsyncImage(url: mediaRepo.logoURL(for: item)) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFit()
                            .frame(maxWidth: 240 * DT.Scale.font, maxHeight: 76 * DT.Scale.font)
                            .shadow(color: .black.opacity(0.7), radius: 12)
                    } else if case .empty = phase {
                        // Still loading: reserve the logo's space but show nothing, so the
                        // plain-text title doesn't flash up and then swap for the logo.
                        Color.clear.frame(height: 76 * DT.Scale.font)
                    } else {
                        Text(item.name)
                            .scaledFont(size: 28, weight: .heavy)
                            .foregroundStyle(.white)
                            .tracking(-0.8)
                            .multilineTextAlignment(.center)
                            .shadow(color: .black.opacity(0.9), radius: 10)
                            .padding(.horizontal, 32)
                    }
                }
                .id(carousel.index)
                .transition(.opacity)
                .animation(DT.Animation.motion(.easeInOut(duration: 0.3)), value: carousel.index)
                .task(id: items.map(\.id)) { await carousel.prefetchLogos(items, mediaRepo: mediaRepo) }

                HStack(spacing: 8) {
                    if let rating = item.communityRating, rating > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill").scaledFont(size: 10)
                            Text(String(format: "%.1f", rating)).scaledFont(size: 12, weight: .semibold)
                        }
                        .foregroundStyle(DT.Color.palette("f59e0b"))
                    }
                    Text(HomeText.heroMeta(item))
                        .scaledFont(size: 12)
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.top, 7)
                .animation(nil, value: carousel.index)

                if let pct = item.userData?.playedPercentage, pct > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.25)).frame(height: 3)
                            Capsule().fill(DT.Color.accent).frame(width: geo.size.width * CGFloat(min(pct / 100, 1)), height: 3)
                        }
                    }
                    .frame(width: 120, height: 3)
                    .padding(.top, 8)
                    .animation(nil, value: carousel.index)
                }
            }

            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    Button {
                        guard let item = items[safe: carousel.index] else { return }
                        carousel.play(item)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill").scaledFont(size: 12)
                            Text(heroIsResumable ? "Resume" : "Play").scaledFont(size: 14, weight: .bold)
                            if let episodeLabel = heroEpisodeLabel {
                                Text(episodeLabel)
                                    .scaledFont(size: 11, weight: .semibold)
                                    .opacity(0.85)
                            }
                        }
                        .foregroundStyle(DT.Color.onAccent)
                        .padding(.horizontal, 28).padding(.vertical, 11)
                    }
                    .glassEffect(.regular.tint(DT.Color.accent).interactive(), in: .rect(cornerRadius: 10))

                    Button {
                        if let item = items[safe: carousel.index] { openItem(item) }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle").scaledFont(size: 12)
                            Text("More Info").scaledFont(size: 13, weight: .semibold)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20).padding(.vertical, 11)
                    }
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 10))
                }
            }
            // The buttons sit on the artwork, so their glass stays dark under the white labels.
            .alwaysDark()
            .padding(.top, 16)

            if items.count > 1 {
                HStack(spacing: 6) {
                    ForEach(0..<items.count, id: \.self) { i in
                        Capsule()
                            .fill(i == carousel.index ? .white : Color.white.opacity(0.3))
                            .frame(width: i == carousel.index ? 18 : 6, height: 5)
                            .onTapGesture { withAnimation(DT.Animation.standard) { carousel.index = i } }
                            .animation(DT.Animation.fast, value: carousel.index)
                    }
                }
                .padding(.top, 14)
                .accessibilityElement()
                .accessibilityLabel("Featured")
                .accessibilityValue("\(carousel.index + 1) of \(items.count)")
                .accessibilityAdjustableAction { direction in
                    let next = carousel.index + (direction == .increment ? 1 : -1)
                    withAnimation(DT.Animation.standard) { carousel.index = min(max(next, 0), items.count - 1) }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Toolbar avatar

/// The signed-in user's picture, or their initials, on the Settings button.
struct HomeAvatar: View {
    @Environment(AuthManager.self) private var authManager

    var body: some View {
        if let cred = authManager.state.credential, let tag = cred.userImageTag {
            CachedAsyncImage(url: JellyfinMediaClient.userImageURL(baseURL: cred.baseURL, userID: cred.userID, tag: tag, token: cred.accessToken)) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFill()
                default: initialsView
                }
            }
            .clipShape(Circle())
        } else {
            initialsView
        }
    }

    private var initialsView: some View {
        Text(authManager.state.displayInitials)
            .font(.system(.caption2, design: .default, weight: .bold))
            .foregroundStyle(DT.Color.onAccent)
    }
}

private extension AuthState {
    var displayInitials: String {
        guard case .authenticated(let cred) = self else { return "?" }
        return cred.displayName.split(separator: " ")
            .prefix(2).compactMap { $0.first }.map { String($0).uppercased() }.joined()
    }
}

// MARK: - Connection failed banner

/// Above the shelves while the server can't be reached, or the first load is taking long.
struct HomeConnectionBanner: View {
    let hasDownloads: Bool

    @Environment(AuthManager.self) private var authManager
    @Environment(MediaRepository.self) private var mediaRepo
    @AppStorage("offlineModeEnabled") private var offlineModeEnabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "wifi.slash")
                    .font(.system(.title3))
                    .foregroundStyle(DT.Color.palette("f59e0b"))
                VStack(alignment: .leading, spacing: 2) {
                    Text(mediaRepo.isLoading ? "Still trying to reach your server" : "Can't reach your server")
                        .font(.system(.footnote, design: .default, weight: .semibold))
                        .foregroundStyle(DT.Color.textPrimary)
                    Text(mediaRepo.isLoading
                         ? "This is taking longer than usual. Your downloads work without a connection."
                         : "Check your connection or Server Settings, then retry.")
                        .font(.system(.caption))
                        .foregroundStyle(DT.Color.textSecondary)
                }
                Spacer()
                if mediaRepo.isLoading {
                    ProgressView().tint(DT.Color.accent)
                } else {
                    Button("Retry") {
                        guard case .authenticated(let cred) = authManager.state else { return }
                        Task { await mediaRepo.load(credential: cred, authClient: authManager.authClient, force: true) }
                    }
                    .font(.system(.footnote, design: .default, weight: .semibold))
                    .foregroundStyle(DT.Color.accent)
                }
            }
            Button {
                offlineModeEnabled = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle.fill")
                    Text(hasDownloads ? "Watch Downloads Instead" : "Turn On Offline Mode")
                }
                .font(.system(.caption, design: .default, weight: .semibold))
                .foregroundStyle(DT.Color.accent)
            }
        }
        .padding(12)
        .background(DT.Color.palette("f59e0b").opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: DT.Radius.lg).stroke(DT.Color.palette("f59e0b").opacity(0.25), lineWidth: 1))
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.bottom, DT.Spacing.md)
    }
}

// MARK: - Shelves

/// One of Home's shelves on iPhone, iPad and Mac, or nothing when it has nothing to show.
/// Each platform draws the cards.
struct HomeShelfView<Card: View>: View {
    let shelf: HomeShelf
    let model: HomeModel
    let mergeContinueWatchingAndUpNext: Bool
    let seerrDiscoverEnabled: Bool
    let streamingServicesData: Data
    let seeAll: (SeeAllShelf) -> Void
    let openSeerrItem: (SeerrItem) -> Void
    /// A title's card: a landscape one for "resume this" rows, a poster otherwise.
    @ViewBuilder let card: (MediaItem, _ isLandscape: Bool) -> Card

    @Environment(MediaRepository.self) private var mediaRepo
    @Environment(SeerrRepository.self) private var seerrRepo

    private var mergedContinueAndNextItems: [MediaItem] {
        HomeModel.continueAndNext(in: mediaRepo)
    }

    /// Sequencing/visibility is data-driven (order + on/off per HomeShelfSettingsView) —
    /// each case's own content/empty-state gating is unchanged from before this existed.
    var body: some View {
        switch shelf {
        case .continueWatching:
            if mergeContinueWatchingAndUpNext {
                if !mergedContinueAndNextItems.isEmpty {
                    ShelfRow(title: "Continue Watching", onSeeAll: {
                        seeAll(SeeAllShelf(title: "Continue Watching", items: mergedContinueAndNextItems, isLandscape: true))
                    }) {
                        ForEach(mergedContinueAndNextItems) { item in
                            card(item, true)
                        }
                    }
                }
            } else if !mediaRepo.continueWatching.isEmpty {
                ShelfRow(title: "Continue Watching", onSeeAll: {
                    seeAll(SeeAllShelf(title: "Continue Watching", items: mediaRepo.continueWatching, isLandscape: true))
                }) {
                    ForEach(mediaRepo.continueWatching) { item in
                        card(item, true)
                    }
                }
            }
        case .nextUp:
            if !mergeContinueWatchingAndUpNext, !mediaRepo.nextUp.isEmpty {
                ShelfRow(title: "Next Up", onSeeAll: {
                    seeAll(SeeAllShelf(title: "Next Up", items: mediaRepo.nextUp, isLandscape: true))
                }) {
                    ForEach(mediaRepo.nextUp) { item in
                        card(item, true)
                    }
                }
            }
        case .recentlyAddedMovies:
            // Placeholders only until the first load finishes; an empty answer hides the shelf.
            if !mediaRepo.recentlyAddedMovies.isEmpty || (!mediaRepo.loaded && !mediaRepo.connectionFailed) {
                ShelfRow(title: "Recently Added Movies", badge: "NEW", onSeeAll: {
                    seeAll(SeeAllShelf(title: "Recently Added Movies", items: mediaRepo.recentlyAddedMovies))
                }) {
                    posters(mediaRepo.recentlyAddedMovies)
                }
            }
        case .recentlyAddedShows:
            if !mediaRepo.recentlyAddedShows.isEmpty || (!mediaRepo.loaded && !mediaRepo.connectionFailed) {
                ShelfRow(title: "Recently Added Shows", badge: "NEW", onSeeAll: {
                    seeAll(SeeAllShelf(title: "Recently Added Shows", items: mediaRepo.recentlyAddedShows))
                }) {
                    posters(mediaRepo.recentlyAddedShows)
                }
            }
        case .recentlyReleasedMovies:
            if !mediaRepo.recentlyReleasedMovies.isEmpty {
                ShelfRow(title: "Recently Released Movies", onSeeAll: {
                    seeAll(SeeAllShelf(title: "Recently Released Movies", items: mediaRepo.recentlyReleasedMovies))
                }) {
                    posters(mediaRepo.recentlyReleasedMovies)
                }
            }
        case .recentlyAiredEpisodes:
            if !mediaRepo.recentlyAiredEpisodes.isEmpty {
                ShelfRow(title: "Recently Aired Episodes", onSeeAll: {
                    seeAll(SeeAllShelf(title: "Recently Aired Episodes", items: mediaRepo.recentlyAiredEpisodes, isLandscape: true))
                }) {
                    ForEach(mediaRepo.recentlyAiredEpisodes) { item in
                        card(item, true)
                    }
                }
            }
        case .watchAgain:
            if !mediaRepo.watchAgain.isEmpty {
                ShelfRow(title: "Watch Again", onSeeAll: {
                    seeAll(SeeAllShelf(title: "Watch Again", items: mediaRepo.watchAgain))
                }) {
                    posters(mediaRepo.watchAgain)
                }
            }
        case .genreShelves:
            ForEach(mediaRepo.genreShelves, id: \.genre) { shelf in
                let title = "More \(shelf.genre)"
                ShelfRow(title: title, onSeeAll: {
                    seeAll(SeeAllShelf(title: title, items: shelf.items))
                }) {
                    posters(shelf.items)
                }
            }
        case .becauseYouWatched:
            if let recommendation = mediaRepo.becauseYouWatched {
                let title = "Because You Watched \(recommendation.source.name)"
                ShelfRow(title: title, onSeeAll: {
                    seeAll(SeeAllShelf(title: title, items: recommendation.items))
                }) {
                    posters(recommendation.items)
                }
            }
        case .favorites:
            if !mediaRepo.favorites.isEmpty {
                ShelfRow(title: "Favorites", onSeeAll: {
                    seeAll(SeeAllShelf(title: "Favorites", items: mediaRepo.favorites))
                }) {
                    posters(mediaRepo.favorites)
                }
            }
        case .topRatedUnwatched:
            if !mediaRepo.topRatedUnwatched.isEmpty {
                ShelfRow(title: "Top Rated, Unwatched", onSeeAll: {
                    seeAll(SeeAllShelf(title: "Top Rated, Unwatched", items: mediaRepo.topRatedUnwatched))
                }) {
                    posters(mediaRepo.topRatedUnwatched)
                }
            }
        case .suggested:
            if !mediaRepo.suggestions.isEmpty {
                ShelfRow(title: "Suggested for You", onSeeAll: {
                    seeAll(SeeAllShelf(title: "Suggested for You", items: mediaRepo.suggestions))
                }) {
                    posters(mediaRepo.suggestions)
                }
            }
        case .recommendations:
            ForEach(mediaRepo.recommendations) { category in
                let title = HomeShelfLoader.recommendationTitle(category)
                ShelfRow(title: title, onSeeAll: {
                    seeAll(SeeAllShelf(title: title, items: category.items))
                }) {
                    posters(category.items)
                }
            }
        case .nowAvailable:
            if seerrRepo.isConfigured, !model.nowAvailable.isEmpty {
                ShelfRow(title: "Now Available", onSeeAll: {
                    seeAll(SeeAllShelf(title: "Now Available", items: model.nowAvailable))
                }) {
                    posters(model.nowAvailable)
                }
            }
        case .streamingServices:
            if seerrRepo.hasCatalog {
                ForEach(StreamingServicePrefs.decode(streamingServicesData)) { provider in
                    if let items = model.serviceRows[provider.id], !items.isEmpty {
                        HomeSeerrShelf(title: "Popular on \(provider.name)", items: items, open: openSeerrItem)
                    }
                }
            }
        case .seerrWatchlist:
            if seerrRepo.isConfigured, seerrDiscoverEnabled, !seerrRepo.watchlist.isEmpty {
                HomeSeerrShelf(title: "Watchlist", items: seerrRepo.watchlist, open: openSeerrItem)
            }
        case .seerrTrending:
            if seerrRepo.hasCatalog, seerrDiscoverEnabled, !seerrRepo.trending.isEmpty {
                HomeSeerrShelf(title: "Trending", items: seerrRepo.trending, open: openSeerrItem)
            }
        case .seerrPopularMovies:
            if seerrRepo.hasCatalog, seerrDiscoverEnabled, !seerrRepo.popularMovies.isEmpty {
                HomeSeerrShelf(title: "Popular Movies", items: seerrRepo.popularMovies, open: openSeerrItem)
            }
        case .seerrPopularSeries:
            if seerrRepo.hasCatalog, seerrDiscoverEnabled, !seerrRepo.popularTV.isEmpty {
                HomeSeerrShelf(title: "Popular Series", items: seerrRepo.popularTV, open: openSeerrItem)
            }
        }
    }

    private func posters(_ items: [MediaItem]) -> some View {
        HomePosterCards(items: items) { card($0, false) }
    }
}

/// A shelf's posters, or placeholder cards while it has none yet.
struct HomePosterCards<Card: View>: View {
    let items: [MediaItem]
    var placeholderCount = 6
    @ViewBuilder let card: (MediaItem) -> Card

    var body: some View {
        if items.isEmpty {
            ForEach(0..<placeholderCount, id: \.self) { _ in
                PosterCard(title: "Loading Title")
            }
            .redacted(reason: .placeholder)
        } else {
            ForEach(items) { item in
                card(item)
            }
        }
    }
}

// MARK: - Seerr shelf

private struct HomeSeerrShelf: View {
    let title: String
    let items: [SeerrItem]
    let open: (SeerrItem) -> Void

    @Environment(MediaRepository.self) private var mediaRepo
    @Environment(SeerrRepository.self) private var seerrRepo

    var body: some View {
        ShelfRow(title: title, onSeeAll: nil) {
            ForEach(items) { item in
                Button { open(item) } label: {
                    PosterCard(
                        title: item.title,
                        subtitle: subtitle(for: item),
                        imageURL: item.posterURL
                    )
                }
                .buttonStyle(PressableButtonStyle())
                .contextMenu { HomeSeerrQuickLookMenu(item: item) }
            }
        }
    }

    private func subtitle(for item: SeerrItem) -> String? {
        let status: String? = mediaRepo.hasInLibrary(item) ? String(localized: "In Library")
            : seerrRepo.isRequested(item) ? String(localized: "Requested") : nil
        return [item.year, status].compactMap { $0 }.joined(separator: " · ").nilIfEmpty
    }
}

// MARK: - Context menus

/// A title's quick actions and details, at the bottom of a poster's long-press menu.
struct HomeQuickLookMenu: View {
    let item: MediaItem

    var body: some View {
        ItemQuickActions(item: item)
        Label(item.name, systemImage: item.type == .series ? "tv" : "film")
        if let year = item.productionYear {
            Label(String(year), systemImage: "calendar")
        }
        if let rating = item.communityRating {
            Label(String(format: "%.1f / 10", rating), systemImage: "star.fill")
        }
        if let overview = item.overview, !overview.isEmpty {
            Label(String(overview.prefix(60)) + "…", systemImage: "text.alignleft")
        }
    }
}

private struct HomeSeerrQuickLookMenu: View {
    let item: SeerrItem

    @Environment(MediaRepository.self) private var mediaRepo
    @Environment(SeerrRepository.self) private var seerrRepo

    var body: some View {
        Label(item.title, systemImage: item.mediaType == .tv ? "tv" : "film")
        if let year = item.year {
            Label(year, systemImage: "calendar")
        }
        if !mediaRepo.hasInLibrary(item), !seerrRepo.isRequested(item) {
            Button {
                Task { try? await seerrRepo.createRequest(mediaType: item.mediaType, mediaId: item.id) }
            } label: {
                Label("Request via Seerr", systemImage: "plus.circle")
            }
        }
    }
}

// MARK: - Artwork

enum HomeArtwork {
    /// Continue Watching / Up Next use landscape cards for everything (movies included),
    /// matching the convention most streaming apps use for "resume this" rows — a movie's
    /// thumb/backdrop, or an episode's own screenshot.
    @MainActor
    static func landscapeURL(for item: MediaItem, in mediaRepo: MediaRepository) -> URL? {
        if item.type == .episode {
            return mediaRepo.imageURL(for: item, type: .primary, fillWidth: 400)
        }
        return mediaRepo.imageURL(for: item, type: .thumb, fillWidth: 400)
            ?? mediaRepo.imageURL(for: item, type: .backdrop, fillWidth: 400)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
