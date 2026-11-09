// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI
import SeerrAPI
import AuthCore
import ImageCache

struct HomeView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(MediaRepository.self) private var mediaRepo
    @Environment(SeerrRepository.self) private var seerrRepo

    @AppStorage("seerrDiscoverEnabled") private var seerrDiscoverEnabled = true
    @AppStorage("mergeContinueWatchingAndUpNext") private var mergeContinueWatchingAndUpNext = false
    @AppStorage(HomeShelfPrefs.orderKey) private var homeShelfOrderString = ""
    @AppStorage(HomeShelfPrefs.activeKey) private var homeShelfActiveString = ""
    @AppStorage(HomeShelfPrefs.shuffleKey) private var shuffleHomeShelves = false
    @AppStorage(StreamingServicePrefs.key) private var streamingServicesData = Data()
    @AppStorage(SeerrRepository.regionOverrideKey) private var seerrRegionOverride = ""
    @State private var model = HomeModel()

    @FocusState private var focusedItemID: String?
    // @FocusState clears to nil the instant focus moves to anything not bound to it (e.g.
    // the hero's own Play/More Info buttons) — using it directly for heroDisplayItem meant
    // moving focus up off a shelf card immediately reset the hero back to
    // continueWatching.first, discarding whatever the user had actually focused. This
    // mirrors the last real focus instead and is never cleared, only updated.
    @State private var lastFocusedItemID: String?
    @State private var heroVideoBackdropItemID: String?
    @State private var heroVideoBackdropURL: URL?
    @State private var heroVideoBackdropTask: Task<Void, Never>?
    @AppStorage("heroVideoBackdropsEnabled") private var heroVideoBackdropsEnabled = true
    @AppStorage("heroTrailerSound") private var heroTrailerSound = false
    @State private var isHomeShowing = false
    @State private var homePath = NavigationPath()
    @State private var isHeroScrolledAway = false
    @State private var heroVideoRequestedItemID: String?
    @State private var heroVideoIsPlaying = false
    @State private var heroChromeHidden = false
    @State private var heroChromeTask: Task<Void, Never>?
    @FocusState private var focusedHeroButton: HeroButton?
    @AppStorage("modernHome") private var modernHome = false
    // Modern Home: the row the focused card is in, where each row starts, and the title the
    // fixed hero shows.
    @State private var modernRow: String?
    @State private var modernRowTops: [String: CGFloat] = [:]
    @State private var modernRowHeights: [String: CGFloat] = [:]
    @State private var modernHero: ModernHeroSubject?
    /// Modern Home while the trailer plays: the focused row sits a little lower, and the hero's
    /// details and every other row fade, until the next press.
    @State private var modernRowsResting = false

    private enum HeroButton { case play, info }

    /// What Modern Home's hero shows: the focused card's title, from the library or Seerr.
    private enum ModernHeroSubject: Equatable {
        case media(MediaItem)
        case seerr(SeerrItem)

        var id: String {
            switch self {
            case .media(let item): "media-\(item.id)"
            case .seerr(let item): "seerr-\(item.id)"
            }
        }
    }

    private var heroChromeOpacity: Double { heroChromeHidden ? 0 : 1 }

    private var cwItems: [MediaItem] {
        mergeContinueWatchingAndUpNext ? HomeModel.continueAndNext(in: mediaRepo) : mediaRepo.continueWatching
    }

    /// Focus on the hero's buttons or its Continue Watching row, the only places the hero
    /// hides from.
    private var focusIsOnHero: Bool {
        focusedHeroButton != nil || focusedItemID.map { id in cwItems.contains { $0.id == id } } == true
    }

    private var focusedItem: MediaItem? {
        guard let id = lastFocusedItemID else { return nil }
        // When Merge Continue Watching & Up Next is on, cwShelf renders items sourced from
        // both arrays (HomeModel.continueAndNext) — this lookup only checked
        // continueWatching, so focusing a nextUp-sourced card in that merged row found no
        // match here, fell through to the fallback below, and left the hero stuck on the
        // first item instead of following focus along the row.
        return mediaRepo.continueWatching.first { $0.id == id }
            ?? mediaRepo.nextUp.first { $0.id == id }
            ?? mediaRepo.recentlyAdded.first { $0.id == id }
    }

    /// Only while the hero itself is on screen: with sound on, a trailer left running under
    /// the shelves, a title's page, the player or another tab would be heard there. Spotlight
    /// Home's hero never scrolls away. Pushing a page doesn't reliably end `isHomeShowing` on
    /// Apple TV, so an open page is checked directly.
    private var heroVideoAllowed: Bool {
        isHomeShowing && homePath.isEmpty && model.detailItem == nil && model.seerrDetailItem == nil
            && (modernHome || !isHeroScrolledAway) && model.playbackRequest == nil
    }

    private var heroDisplayItem: MediaItem? {
        if modernHome {
            switch modernHero {
            case .media(let item): return item
            case .seerr: return nil
            case nil: return cwItems.first ?? mediaRepo.recentlyAdded.first
            }
        }
        return focusedItem ?? mediaRepo.continueWatching.first ?? mediaRepo.recentlyAdded.first
    }

    var body: some View {
        NavigationStack(path: $homePath) {
            Group {
                if modernHome {
                    modernLayout
                } else {
                    GeometryReader { proxy in
                        let sh = proxy.size.height
                        let sw = proxy.size.width

                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 0) {
                                heroSection(screenW: sw, screenH: sh)
                                    .frame(height: sh)
                                belowFoldSection
                                    .padding(.vertical, 72)
                            }
                            .focusSection()
                        }
                        .scrollTargetBehavior(TVFoldSnappingBehavior(showcaseHeight: sh))
                        .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y > sh / 2 } action: { _, scrolledAway in
                            isHeroScrolledAway = scrolledAway
                        }
                        .ignoresSafeArea()
                    }
                }
            }
            .screenBackground()
            .onAppear { isHomeShowing = true }
            .onDisappear { isHomeShowing = false }
            .navigationDestination(item: $model.detailItem) { item in
                MediaDetailView(item: item)
            }
            .navigationDestination(for: MediaItem.self) { item in
                MediaDetailView(item: item)
            }
            .navigationDestination(item: $model.seerrDetailItem) { item in
                SeerrItemDetailView(item: item)
            }
        }
        .fullScreenCover(item: $model.playbackRequest) { request in
            PlayerView(item: request.item, startPositionTicks: request.startTicks) { next in
                model.playbackRequest = PlaybackRequest(item: next, startTicks: 0)
            }
            // The cover stays up for the next episode; a new id gives it a fresh player
            // instead of the last episode's.
            .id(request.item.id)
        }
        .task { await load() }
        .task(id: topShelfSignature) {
            guard !topShelfSignature.isEmpty else { return }
            model.saveTopShelf(mediaRepo: mediaRepo, title: topShelfTitle, subtitle: itemSubtitle)
            await TopShelfArtwork.refresh()
        }
        // The hero already shows the first Continue Watching item until something's focused.
        // Assigning focus to it here pulled the page down to that row once Home loaded.
        .onChange(of: mediaRepo.continueWatching) { _, _ in
            if focusedItemID == nil { reloadHeroVideoIfItemChanged() }
        }
        .onChange(of: focusedItemID) { _, newValue in
            if let newValue { lastFocusedItemID = newValue }
            showHeroChrome()
            reloadHeroVideoIfItemChanged()
        }
        .onChange(of: focusedHeroButton) { _, _ in
            showHeroChrome()
        }
        .onChange(of: heroVideoAllowed) { _, _ in loadHeroVideoBackdrop() }
        .onChange(of: modernHero?.id) { _, _ in
            if modernHome { reloadHeroVideoIfItemChanged() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .arcfinPlayItem)) { note in
            if let id = note.userInfo?["itemID"] as? String {
                UserDefaults.standard.removeObject(forKey: "arcfin.pendingPlayID")
                model.deepLinkItemID = id
                model.detailItem = (mediaRepo.continueWatching + mediaRepo.nextUp + mediaRepo.recentlyAdded).first { $0.id == id }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: WatchRoute.notification)) { _ in
            model.playPendingWatch(authManager: authManager)
        }
        .task(id: "\(StreamingServicePrefs.decode(streamingServicesData).map(\.id))-\(seerrRepo.hasCatalog)-\(seerrRegionOverride)") {
            await model.loadServiceRows(seerrRepo: seerrRepo)
        }
        .task(id: HomeShelfLoader.recentlyAvailable(seerrRepo.requests).map(\.id)) {
            await model.loadNowAvailable(HomeShelfLoader.recentlyAvailable(seerrRepo.requests), authManager: authManager)
        }
        .onDisappear { if shuffleHomeShelves { model.reshuffleShelves() } }
    }

    // MARK: - Load

    private func load() async {
        guard await model.loadShelves(force: false, authManager: authManager, mediaRepo: mediaRepo) else { return }
        // Preheat full-res hero backdrops + logos into the Nuke decoded cache so
        // backdrop transitions are instant with no load jump.
        let heroURLs = (mediaRepo.continueWatching + mediaRepo.recentlyAdded).flatMap { item -> [URL] in            [mediaRepo.imageURL(for: item, type: .backdrop, fillWidth: 1920),
             mediaRepo.logoURL(for: item)].compactMap { $0 }
        }
        ImageCache.preheat(urls: heroURLs)
        let pendingID = model.deepLinkItemID ?? UserDefaults.standard.string(forKey: "arcfin.pendingPlayID")
        if let id = pendingID {
            UserDefaults.standard.removeObject(forKey: "arcfin.pendingPlayID")
            model.deepLinkItemID = nil
            model.detailItem = (mediaRepo.continueWatching + mediaRepo.nextUp + mediaRepo.recentlyAdded).first { $0.id == id }
        }
        model.playPendingWatch(authManager: authManager)
        await model.loadDiscover(enabled: seerrDiscoverEnabled, mediaRepo: mediaRepo, seerrRepo: seerrRepo)
        // Modern Home starts on its first row by itself; the same title can also be in a row
        // further down, where this could put focus instead.
        if focusedItemID == nil, !modernHome {
            focusedItemID = mediaRepo.continueWatching.first?.id
        }
    }

    // MARK: - Hero section

    private func heroSection(screenW: CGFloat, screenH: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
            backdropLayer()

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: DT.Color.backgroundPrimary.opacity(0.4), location: 0.5),
                    .init(color: DT.Color.backgroundPrimary, location: 1.0)
                ],
                startPoint: .top, endPoint: .bottom
            )

            HStack(spacing: 0) {
                LinearGradient(
                    colors: [DT.Color.backgroundPrimary.opacity(0.75), .clear],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: screenW * 0.6)
                Spacer()
            }
            .opacity(heroChromeOpacity)

            VStack(alignment: .leading, spacing: 0) {
                Spacer()
                heroInfoBlock
                    .padding(.horizontal, 80)
                    .padding(.bottom, 48)
                cwShelf
                    .padding(.bottom, 60)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("shelf.\(HomeShelf.continueWatching.rawValue)")
            }
        }
        .focusSection()
        // Focus moving brings the hero back too; this covers a press that has nowhere to go.
        .onMoveCommand { _ in
            if heroChromeHidden { showHeroChrome() }
        }
    }

    @ViewBuilder
    private func backdropLayer() -> some View {
        let url = heroDisplayItem.flatMap {
            mediaRepo.imageURL(for: $0, type: .backdrop, fillWidth: 1920)
        }
        ZStack {
            LazyHeroImage(url: url) { heroFallbackGradient }
                .clipped()

            if let videoURL = heroVideoBackdropURL, let itemID = heroVideoBackdropItemID, itemID == heroDisplayItem?.id {
                HeroVideoBackdropView(
                    url: videoURL, loops: false, muted: !heroTrailerSound,
                    onStart: { heroVideoDidStart(itemID: itemID) },
                    onEnd: { endHeroVideoBackdrop(itemID: itemID) }
                )
                .transition(.opacity)
            }
        }
    }

    private var heroFallbackGradient: some View {
        LinearGradient(
            colors: [DT.Color.accentDeep.opacity(0.35), DT.Color.backgroundPrimary],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    @ViewBuilder
    private var heroInfoBlock: some View {
        if let item = heroDisplayItem {
            VStack(alignment: .leading, spacing: 16) {
                CachedAsyncImage(url: mediaRepo.logoURL(for: item)) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFit()
                            .frame(maxWidth: 300, maxHeight: 90)
                            .shadow(color: .black.opacity(0.7), radius: 12)
                    } else {
                        Text(item.name)
                            .font(.system(size: 36, weight: .heavy))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.9), radius: 10)
                    }
                }
                .id(item.id)
                .transition(.opacity)
                .animation(DT.Animation.motion(.easeInOut(duration: 0.3)), value: focusedItemID)
                .opacity(heroChromeOpacity)

                heroMetaRow(item)
                    .opacity(heroChromeOpacity)

                if let pct = item.userData?.playedPercentage, pct > 1 {
                    progressBar(pct: pct / 100)
                        .opacity(heroChromeOpacity)
                }

                HStack(spacing: 20) {
                    Button {
                        if heroChromeHidden { showHeroChrome(); return }
                        // Releases this screen's own focus claim before the player appears —
                        // a lingering @FocusState here can otherwise keep the remote's actual
                        // focus target stuck on this (now-hidden) screen instead of the
                        // player, which claims its own initial focus via .prefersDefaultFocus.
                        focusedItemID = nil
                        model.playbackRequest = PlaybackRequest(item: item, startTicks: item.userData?.playbackPositionTicks ?? 0)
                    } label: {
                        TVHeroButtonLabel(icon: "play.fill", text: "Play", isPrimary: true)
                            .opacity(heroChromeOpacity)
                    }
                    .buttonStyle(TVCardButtonStyle())
                    .focusEffectDisabled()
                    .focused($focusedHeroButton, equals: .play)

                    Button {
                        if heroChromeHidden { showHeroChrome(); return }
                        model.detailItem = item
                    } label: {
                        TVHeroButtonLabel(icon: "info.circle", text: "More Info")
                            .opacity(heroChromeOpacity)
                    }
                    .buttonStyle(TVCardButtonStyle())
                    .focusEffectDisabled()
                    .focused($focusedHeroButton, equals: .info)
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: 540, alignment: .leading)
            .id(item.id)
            .transition(.opacity)
            .animation(DT.Animation.motion(.easeInOut(duration: 0.3)), value: focusedItemID)
        } else {
            brandingBlock
        }
    }

    private var brandingBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Arcfin")
                .font(.system(size: 48, weight: .black))
                .foregroundStyle(DT.Color.accent)
            Text("Your Jellyfin media, beautifully.")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private func heroMetaRow(_ item: MediaItem) -> some View {
        HStack(spacing: 12) {
            if let year = item.productionYear {
                Text(String(year)).font(.system(size: 23)).foregroundStyle(.white.opacity(0.7))
            }
            if let rating = item.communityRating {
                Text("·").accessibilityHidden(true).foregroundStyle(.white.opacity(0.3)).font(.system(size: 23))
                HStack(spacing: 5) {
                    Image(systemName: "star.fill").font(.system(size: 16)).foregroundStyle(DT.Color.accent)
                    Text(String(format: "%.1f", rating))
                        .font(.system(size: 23, weight: .bold)).foregroundStyle(DT.Color.accent)
                }
            }
            Text("·").accessibilityHidden(true).foregroundStyle(.white.opacity(0.3)).font(.system(size: 23))
            Text(item.type == .series ? "Series" : "Movie")
                .font(.system(size: 23)).foregroundStyle(.white.opacity(0.7))
        }
    }

    private func progressBar(pct: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).fill(DT.Color.progressTrack).frame(height: 4)
                RoundedRectangle(cornerRadius: 2).fill(DT.Color.progressFill)
                    .frame(width: geo.size.width * min(pct, 1), height: 4)
            }
        }
        .frame(maxWidth: 280)
        .frame(height: 4)
    }

    // MARK: - Hero video backdrop

    /// Fetches (after a short pause, so quickly moving focus across several Continue
    /// Watching cards doesn't fire a burst of these) whether the currently-focused hero
    /// item has a local trailer indexed on the server, and if so resolves it to a real
    /// playable stream URL the same way the main player does. Unlike iOS's hero, tvOS's
    /// hero doesn't auto-rotate on a timer — focus only changes via explicit remote
    /// navigation — so the trailer plays to its end, then the still backdrop returns.
    private func loadHeroVideoBackdrop() {
        heroVideoBackdropTask?.cancel()
        heroVideoBackdropURL = nil
        heroVideoBackdropItemID = nil
        heroVideoRequestedItemID = nil
        heroVideoIsPlaying = false
        showHeroChrome()
        guard heroVideoBackdropsEnabled, heroVideoAllowed, let item = heroDisplayItem,
              case .authenticated(let credential) = authManager.state
        else { return }
        let itemID = item.id
        heroVideoRequestedItemID = itemID
        let authHeader = authManager.authClient.authHeader(token: credential.accessToken)
        heroVideoBackdropTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            guard let url = await HomeModel.heroTrailerURL(for: item, credential: credential, authHeader: authHeader)
            else { return }
            guard !Task.isCancelled, heroDisplayItem?.id == itemID else { return }
            withAnimation(DT.Animation.motion(.easeIn(duration: 0.6))) {
                heroVideoBackdropURL = url
                heroVideoBackdropItemID = itemID
            }
        }
    }

    private func endHeroVideoBackdrop(itemID: String) {
        guard heroVideoBackdropItemID == itemID else { return }
        heroVideoIsPlaying = false
        showHeroChrome()
        withAnimation(DT.Animation.motion(.easeOut(duration: 0.6))) {
            heroVideoBackdropURL = nil
            heroVideoBackdropItemID = nil
        }
    }

    /// Moving between a title's card and its Play/More Info buttons, or Continue Watching
    /// refreshing in the background, keeps the same title in the hero: its trailer carries
    /// on instead of starting over.
    private func reloadHeroVideoIfItemChanged() {
        guard heroDisplayItem?.id != heroVideoRequestedItemID else { return }
        loadHeroVideoBackdrop()
    }

    private func heroVideoDidStart(itemID: String) {
        guard heroVideoBackdropItemID == itemID else { return }
        heroVideoIsPlaying = true
        hideHeroChromeSoon()
    }

    /// Gives the trailer the screen after a few seconds, if focus is on the hero. Only what's
    /// drawn fades; the focused button or card stays in place and keeps focus.
    private func hideHeroChromeSoon() {
        heroChromeTask?.cancel()
        if modernHome {
            heroChromeTask = Task {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, heroVideoIsPlaying else { return }
                withAnimation(DT.Animation.motion(.easeInOut(duration: 0.6))) { modernRowsResting = true }
            }
            return
        }
        heroChromeTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, heroVideoIsPlaying, focusIsOnHero else { return }
            withAnimation(DT.Animation.motion(.easeInOut(duration: 0.6))) { heroChromeHidden = true }
        }
    }

    /// Any focus move brings the hero back. While the trailer keeps playing it fades again
    /// after the same few seconds.
    private func showHeroChrome() {
        heroChromeTask?.cancel()
        heroChromeTask = nil
        if heroChromeHidden {
            withAnimation(DT.Animation.motion(.easeInOut(duration: 0.4))) { heroChromeHidden = false }
        }
        if modernRowsResting {
            withAnimation(DT.Animation.motion(.easeInOut(duration: 0.4))) { modernRowsResting = false }
        }
        if heroVideoIsPlaying { hideHeroChromeSoon() }
    }

    // MARK: - Continue Watching shelf (inside hero)

    @ViewBuilder
    private var cwShelf: some View {
        let items = cwItems
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("Continue Watching")
                    .font(.system(size: 23, weight: .bold))
                    .foregroundStyle(DT.Color.textPrimary)
                    .padding(.horizontal, 80)
                    .opacity(heroChromeOpacity)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(items) { item in
                            Button {
                                if heroChromeHidden { showHeroChrome(); return }
                                model.detailItem = item
                            } label: {
                                PosterCard(
                                    title: itemTitle(item),
                                    subtitle: itemSubtitle(item),
                                    progress: item.userData?.playedPercentage.map { $0 / 100 },
                                    imageURL: mediaRepo.tvImageURL(for: item, fillWidth: 640)
                                )
                                .opacity(heroChromeOpacity)
                            }
                            .buttonStyle(TVCardButtonStyle())
                            .focusEffectDisabled()
                            .focused($focusedItemID, equals: item.id)
                            .contextMenu { cwContextMenu(item) }
                        }
                    }
                    .padding(.horizontal, 80)
                    .padding(.top, 20)
                    .focusSection()
                }
                .scrollClipDisabled()
            }
        }
    }

    // MARK: - Below fold

    /// The user's shelves from Settings › Appearance › Home Shelves, in their order.
    /// Continue Watching lives in the hero, so it's left out here.
    private var orderedShelves: [HomeShelf] {
        model.shelves(order: homeShelfOrderString, active: homeShelfActiveString, shuffled: shuffleHomeShelves)
            .filter { $0 != .continueWatching }
    }

    private var belowFoldSection: some View {
        VStack(spacing: 0) {
            ForEach(orderedShelves) { shelf in
                shelfView(for: shelf)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("shelf.\(shelf.rawValue)")
            }
        }
        .focusSection()
    }

    @ViewBuilder
    private func shelfView(for shelf: HomeShelf) -> some View {
        switch shelf {
        case .continueWatching:
            EmptyView()
        case .nextUp:
            if !mergeContinueWatchingAndUpNext, !mediaRepo.nextUp.isEmpty {
                mediaShelf(title: "Next Up", items: mediaRepo.nextUp)
            }
        case .recentlyAddedMovies:
            if !mediaRepo.recentlyAddedMovies.isEmpty {
                mediaShelf(title: "Recently Added Movies", badge: "NEW", items: mediaRepo.recentlyAddedMovies)
            }
        case .recentlyAddedShows:
            if !mediaRepo.recentlyAddedShows.isEmpty {
                mediaShelf(title: "Recently Added Shows", badge: "NEW", items: mediaRepo.recentlyAddedShows)
            }
        case .recentlyReleasedMovies:
            if !mediaRepo.recentlyReleasedMovies.isEmpty {
                mediaShelf(title: "Recently Released Movies", items: mediaRepo.recentlyReleasedMovies)
            }
        case .recentlyAiredEpisodes:
            if !mediaRepo.recentlyAiredEpisodes.isEmpty {
                mediaShelf(title: "Recently Aired Episodes", items: mediaRepo.recentlyAiredEpisodes)
            }
        case .watchAgain:
            if !mediaRepo.watchAgain.isEmpty {
                mediaShelf(title: "Watch Again", items: mediaRepo.watchAgain)
            }
        case .genreShelves:
            ForEach(mediaRepo.genreShelves, id: \.genre) { shelf in
                mediaShelf(title: "More \(shelf.genre)", items: shelf.items)
            }
        case .becauseYouWatched:
            if let recommendation = mediaRepo.becauseYouWatched {
                mediaShelf(title: "Because You Watched \(recommendation.source.name)", items: recommendation.items)
            }
        case .favorites:
            if !mediaRepo.favorites.isEmpty {
                mediaShelf(title: "Favorites", items: mediaRepo.favorites)
            }
        case .topRatedUnwatched:
            if !mediaRepo.topRatedUnwatched.isEmpty {
                mediaShelf(title: "Top Rated, Unwatched", items: mediaRepo.topRatedUnwatched)
            }
        case .suggested:
            if !mediaRepo.suggestions.isEmpty {
                mediaShelf(title: "Suggested for You", items: mediaRepo.suggestions)
            }
        case .recommendations:
            ForEach(mediaRepo.recommendations) { category in
                mediaShelf(title: HomeShelfLoader.recommendationTitle(category), items: category.items)
            }
        case .nowAvailable:
            if seerrRepo.isConfigured, !model.nowAvailable.isEmpty {
                mediaShelf(title: "Now Available", items: model.nowAvailable)
            }
        case .streamingServices:
            if seerrRepo.hasCatalog {
                ForEach(StreamingServicePrefs.decode(streamingServicesData)) { provider in
                    if let items = model.serviceRows[provider.id], !items.isEmpty {
                        seerrShelf(title: "Popular on \(provider.name)", items: items)
                    }
                }
            }
        case .seerrWatchlist:
            if seerrRepo.isConfigured, seerrDiscoverEnabled, !seerrRepo.watchlist.isEmpty {
                seerrShelf(title: "Watchlist", items: seerrRepo.watchlist)
            }
        case .seerrTrending:
            if seerrRepo.hasCatalog, seerrDiscoverEnabled, !seerrRepo.trending.isEmpty {
                seerrShelf(title: "Trending", items: seerrRepo.trending)
            }
        case .seerrPopularMovies:
            if seerrRepo.hasCatalog, seerrDiscoverEnabled, !seerrRepo.popularMovies.isEmpty {
                seerrShelf(title: "Popular Movies", items: seerrRepo.popularMovies)
            }
        case .seerrPopularSeries:
            if seerrRepo.hasCatalog, seerrDiscoverEnabled, !seerrRepo.popularTV.isEmpty {
                seerrShelf(title: "Popular Series", items: seerrRepo.popularTV)
            }
        }
    }

    private func mediaShelf(title: String, badge: String? = nil, items: [MediaItem]) -> some View {
        tvShelfRow(title: title, badge: badge) {
            ForEach(items) { item in
                NavigationLink(value: item) {
                    PosterCard(
                        title: item.name,
                        subtitle: item.productionYear.map { String($0) },
                        imageURL: mediaRepo.tvImageURL(for: item, fillWidth: 640)
                    )
                    .background { modernFocusProbe(row: title, subject: .media(item)) }
                }
                .buttonStyle(TVCardButtonStyle())
                .focusEffectDisabled()
                .focused($focusedItemID, equals: item.id)
                .contextMenu { cwContextMenu(item) }
            }
        }
    }

    private func tvShelfRow<Content: View>(
        title: String,
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
                    Color.clear.preference(key: ModernRowHeights.self, value: [.init(title: title, height: proxy.size.height)])
                }
            }
        }
    }

    private func seerrShelf(title: String, items: [SeerrItem]) -> some View {
        tvShelfRow(title: title) {
            ForEach(items) { item in
                Button { openSeerrShelfItem(item) } label: {
                    PosterCard(
                        title: item.title,
                        subtitle: [item.year, mediaRepo.hasInLibrary(item) ? "In Library" : nil]
                            .compactMap { $0 }.joined(separator: " · ").nilIfEmpty,
                        imageURL: item.backdropURL ?? item.posterURL
                    )
                    .background { modernFocusProbe(row: title, subject: .seerr(item)) }
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

    // MARK: - Modern Home


    /// The hero stays put and shows the focused title; the rows sit under it, the focused one
    /// on top with part of the next showing below. Moving down slides them up, and the row
    /// that leaves fades out under the hero's details.
    private var modernLayout: some View {
        GeometryReader { proxy in
            let sw = proxy.size.width
            let sh = proxy.size.height
            let rowsTop = sh * 0.5
            let focusedRowTop = modernRow.flatMap { modernRowTops[$0] } ?? 0
            // Resting drops the focused row until its cards almost reach the bottom edge.
            // Each row's height includes its 40 pt bottom padding.
            let focusedRowHeight = modernRowHeights[modernRow ?? "Continue Watching"] ?? 0
            let restingDrop = max(0, sh - 60 - rowsTop - (focusedRowHeight - 40))
            let rowsOffset = rowsTop - focusedRowTop + (modernRowsResting ? restingDrop : 0)

            ZStack(alignment: .topLeading) {
                modernBackdrop
                    .frame(width: sw, height: sh)
                    .clipped()

                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.2),
                        .init(color: DT.Color.backgroundPrimary.opacity(0.85), location: 0.5),
                        .init(color: DT.Color.backgroundPrimary, location: 0.8)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                LinearGradient(
                    colors: [DT.Color.backgroundPrimary.opacity(0.75), .clear],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: sw * 0.6)

                modernHeroInfo
                    .padding(.leading, 80)
                    .padding(.top, 150)
                    .opacity(modernRowsResting ? 0 : 1)

                modernRows
                    .offset(y: rowsOffset)
                    .animation(DT.Animation.motion(.easeInOut(duration: 0.35)), value: rowsOffset)
                    .frame(width: sw, height: sh, alignment: .top)
                    // Resting shows only a band around the focused row, which moves down with
                    // it. Masking rather than fading keeps the other rows focusable, so the next
                    // press can move to them while everything comes back.
                    .mask {
                        ZStack(alignment: .top) {
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: (rowsTop - 40) / sh),
                                    .init(color: .black, location: rowsTop / sh)
                                ],
                                startPoint: .top, endPoint: .bottom
                            )
                            .opacity(modernRowsResting ? 0 : 1)
                            VStack(spacing: 0) {
                                Color.clear.frame(height: max(0, rowsTop + (modernRowsResting ? restingDrop : 0) - 20))
                                Color.black.frame(height: focusedRowHeight + 20)
                                Color.clear
                            }
                            .opacity(modernRowsResting ? 1 : 0)
                        }
                    }
            }
        }
        // Measured edge to edge: inside the safe area the backdrop stopped short of the right
        // edge and the rows were cut off above the bottom.
        .ignoresSafeArea()
        // Any press brings the rows back from resting, including one that moves no focus.
        .onMoveCommand { _ in showHeroChrome() }
    }

    private var modernRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            modernContinueWatchingRow
            ForEach(orderedShelves) { shelf in
                shelfView(for: shelf)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("shelf.\(shelf.rawValue)")
            }
        }
        .focusSection()
        // Tops come from adding up row heights in order. Measuring positions picked up the
        // offset they were used for, so the rows chased their own position: the bounce.
        .onPreferenceChange(ModernRowHeights.self) { rows in
            var top: CGFloat = 0
            var tops: [String: CGFloat] = [:]
            var heights: [String: CGFloat] = [:]
            for row in rows {
                tops[row.title] = top
                heights[row.title] = row.height
                top += row.height
            }
            modernRowTops = tops
            modernRowHeights = heights
        }
    }

    @ViewBuilder
    private var modernContinueWatchingRow: some View {
        let items = cwItems
        if !items.isEmpty {
            let title = "Continue Watching"
            tvShelfRow(title: title) {
                ForEach(items) { item in
                    Button { model.detailItem = item } label: {
                        PosterCard(
                            title: itemTitle(item),
                            subtitle: itemSubtitle(item),
                            progress: item.userData?.playedPercentage.map { $0 / 100 },
                            imageURL: mediaRepo.tvImageURL(for: item, fillWidth: 640)
                        )
                        .background { modernFocusProbe(row: title, subject: .media(item)) }
                    }
                    .buttonStyle(TVCardButtonStyle())
                    .focusEffectDisabled()
                    .focused($focusedItemID, equals: item.id)
                    .contextMenu { cwContextMenu(item) }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("shelf.\(HomeShelf.continueWatching.rawValue)")
        }
    }

    private func modernFocusProbe(row: String, subject: ModernHeroSubject) -> some View {
        CardFocusProbe {
            guard modernHome else { return }
            modernRow = row
            modernHero = subject
        }
    }

    @ViewBuilder
    private var modernBackdrop: some View {
        if case .seerr(let item) = modernHero {
            LazyHeroImage(url: item.backdropURL) { heroFallbackGradient }
        } else {
            backdropLayer()
        }
    }

    @ViewBuilder
    private var modernHeroInfo: some View {
        Group {
            if case .seerr(let item) = modernHero {
                VStack(alignment: .leading, spacing: 16) {
                    Text(item.title)
                        .font(.system(size: 36, weight: .heavy))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.9), radius: 10)
                    HStack(spacing: 12) {
                        if let year = item.year {
                            Text(year).font(.system(size: 23)).foregroundStyle(.white.opacity(0.7))
                            Text("·").accessibilityHidden(true).foregroundStyle(.white.opacity(0.3)).font(.system(size: 23))
                        }
                        Text(item.mediaType == .tv ? "Series" : "Movie")
                            .font(.system(size: 23)).foregroundStyle(.white.opacity(0.7))
                    }
                    modernOverview(item.overview)
                }
            } else if let item = heroDisplayItem {
                VStack(alignment: .leading, spacing: 16) {
                    CachedAsyncImage(url: mediaRepo.logoURL(for: item)) { phase in
                        if case .success(let img) = phase {
                            img.resizable().scaledToFit()
                                .frame(maxWidth: 300, maxHeight: 90)
                                .shadow(color: .black.opacity(0.7), radius: 12)
                        } else {
                            Text(item.type == .episode ? (item.seriesName ?? item.name) : item.name)
                                .font(.system(size: 36, weight: .heavy))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.9), radius: 10)
                        }
                    }
                    if item.type == .episode {
                        Text(itemTitle(item))
                            .font(.system(size: 25, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                    } else {
                        heroMetaRow(item)
                    }
                    if let pct = item.userData?.playedPercentage, pct > 1 {
                        progressBar(pct: pct / 100)
                    }
                    modernOverview(item.overview)
                }
            } else {
                brandingBlock
            }
        }
        .frame(maxWidth: 760, alignment: .leading)
        .id(modernHero?.id)
        .transition(.opacity)
        .animation(DT.Animation.motion(.easeInOut(duration: 0.3)), value: modernHero?.id)
    }

    @ViewBuilder
    private func modernOverview(_ overview: String?) -> some View {
        if let overview = overview?.nilIfEmpty {
            Text(overview)
                .font(.system(size: 22))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(3)
                .shadow(color: .black.opacity(0.6), radius: 6)
        }
    }

    // MARK: - Context menu

    @ViewBuilder
    private func cwContextMenu(_ item: MediaItem) -> some View {
        if item.type == .movie || item.type == .episode {
            let ticks = item.userData?.played == true ? 0 : (item.userData?.playbackPositionTicks ?? 0)
            Button {
                focusedItemID = nil
                model.playbackRequest = PlaybackRequest(item: item, startTicks: ticks)
            } label: {
                Label(ticks > 0 ? "Resume" : "Play", systemImage: "play.fill")
            }
        }
        ItemQuickActions(item: item)
        Label(item.name, systemImage: item.type == .series ? "tv" : "film")
        if let year = item.productionYear { Label(String(year), systemImage: "calendar") }
        if let rating = item.communityRating {
            Label(String(format: "%.1f / 10", rating), systemImage: "star.fill")
        }
    }

    // MARK: - Helpers

    // "S1 · E4 · Episode Name" for episodes, show title for movies/series
    private func itemTitle(_ item: MediaItem) -> String {
        guard item.type == .episode else { return item.name }
        let s = item.parentIndexNumber.map { "S\($0)" }
        let e = item.indexNumber.map { "E\($0)" }
        let badge = [s, e].compactMap { $0 }.joined(separator: " · ")
        return badge.isEmpty ? item.name : "\(badge) · \(item.name)"
    }

    // Show name as subtitle for episodes, year for everything else
    private func itemSubtitle(_ item: MediaItem) -> String? {
        if item.type == .episode { return item.seriesName }
        return item.productionYear.map { String($0) }
    }

    // Changes when the shelf's items or their progress do, so it follows what was just watched.
    private var topShelfSignature: [String] {
        (mediaRepo.continueWatching.prefix(5) + mediaRepo.nextUp.prefix(3) + mediaRepo.recentlyAdded.prefix(3))
            .map { "\($0.id)-\(Int($0.userData?.playedPercentage ?? 0))" }
    }

    // Top Shelf title includes S/E so users see context without needing a subtitle row
    private func topShelfTitle(_ item: MediaItem) -> String {
        guard item.type == .episode else { return item.name }
        let show = item.seriesName ?? item.name
        guard let code = HomeText.episodeLabel(item) else { return show }
        return "\(show) · \(code)"
    }
}

/// Each Modern Home row's height, in the order the rows are stacked.
private struct ModernRowHeights: PreferenceKey {
    struct Row: Equatable {
        let title: String
        let height: CGFloat
    }

    static let defaultValue: [Row] = []

    static func reduce(value: inout [Row], nextValue: () -> [Row]) {
        value += nextValue()
    }
}

/// Tells Modern Home when a card takes focus: inside a button's label, `isFocused` is the
/// button's own focus.
private struct CardFocusProbe: View {
    let onFocus: () -> Void
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Color.clear
            .onChange(of: isFocused) { _, focused in
                if focused { onFocus() }
            }
    }
}

#Preview {
    HomeView()
        .environment(AuthManager())
        .environment(MediaRepository())
        .environment(SeerrRepository())
}
