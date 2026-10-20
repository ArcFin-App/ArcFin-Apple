// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import SwiftData
import Combine
import JellyfinAPI
import SeerrAPI
import AuthCore
import Persistence
import Telemetry
import os

// MARK: - Main tab container

struct MainTabView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(SeerrRepository.self) private var seerrRepo
    @Environment(MediaRepository.self) private var mediaRepo
    #if os(tvOS)
    @State private var searchQuery = ""
    #else
    @AppStorage(BottomNavPrefs.orderKey) private var orderString = ""
    @AppStorage(BottomNavPrefs.activeKey) private var activeString = ""
    @State private var selectedTab: BottomNavItem = .home
    #endif

    #if !os(tvOS)
    private var visibleTabs: [BottomNavItem] {
        let order = BottomNavPrefs.order(from: orderString)
        let active = BottomNavPrefs.active(from: activeString)
        return order.filter { tab in
            guard active.contains(tab) else { return false }
            if tab == .requests || tab == .watchlist { return seerrRepo.isConfigured }
            return true
        }
    }

    @ViewBuilder
    private func tabDestination(_ tab: BottomNavItem) -> some View {
        switch tab {
        case .home:      HomeView()
        case .browse:    LibraryView()
        case .stats:     StatsView()
        case .requests:  SeerrView()
        case .watchlist: NavigationStack { WatchlistView() }
        }
    }
    #endif

    var body: some View {
#if os(tvOS)
        if mediaRepo.connectionFailed && !mediaRepo.hasAnyContent {
            NoConnectionView()
                .preferredColorScheme(.dark)
        } else {
            TabView {
                Tab("Home", systemImage: "house") {
                    TVHomeView()
                }
                Tab("Library", systemImage: "square.grid.2x2") {
                    TVLibraryView()
                }
                // Declared right after Library so it renders right after Library — on-device
                // testing showed role: .search does NOT always pin to the far end of the bar
                // regardless of declaration order the way it was previously assumed to.
                Tab("Search", systemImage: "magnifyingglass", role: .search) {
                    NavigationStack {
                        SearchView(query: $searchQuery)
                            .searchable(text: $searchQuery, prompt: "Movies, shows, people…")
                            .background(DT.Color.backgroundPrimary)
                            .navigationDestination(for: MediaItem.self) { item in
                                TVMediaDetailView(item: item)
                            }
                    }
                }
                Tab("Requests", systemImage: "clock") {
                    TVSeerrView()
                }
                Tab("Settings", systemImage: seerrRepo.authFailed ? "person.crop.circle.badge.exclamationmark" : "person.circle") {
                    NavigationStack { SettingsView() }
                }
            }
            // Suppress the system white focus halo across all screens.
            // The focus ENGINE still works (remote nav, isFocused env); only
            // the system visual highlight is replaced by per-element custom styling.
            .focusEffectDisabled()
            .preferredColorScheme(.dark)
        }
#else
        if mediaRepo.connectionFailed && !mediaRepo.hasAnyContent {
            NoConnectionView()
                .preferredColorScheme(.dark)
        } else {
            TabView(selection: $selectedTab) {
                ForEach(visibleTabs) { tab in
                    Tab(tab.title, systemImage: tab.icon, value: tab) {
                        tabDestination(tab)
                    }
                }
            }
            .tabViewStyle(.sidebarAdaptable)
            .preferredColorScheme(.dark)
            // arcfin://downloads — from the download Live Activity's tap target.
            .onReceive(NotificationCenter.default.publisher(for: .arcfinShowDownloads)) { _ in
                selectedTab = .browse
            }
            #if os(macOS)
            // Cmd+, / Arcfin > Settings… — switches to Home so its own
            // arcfinShowSettings listener (below) can actually present it.
            .onReceive(NotificationCenter.default.publisher(for: .arcfinShowSettings)) { _ in
                selectedTab = .home
            }
            #endif
        }
#endif
    }
}

// MARK: - Home screen

struct HomeView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(MediaRepository.self) private var mediaRepo
    @Environment(SeerrRepository.self) private var seerrRepo
    @Environment(StreamystatsRepository.self) private var statsRepo
    @Environment(PlaybackPresenter.self) private var playbackPresenter
    @Environment(\.horizontalSizeClass) private var sizeClass

    @AppStorage("seerrDiscoverEnabled") private var seerrDiscoverEnabled = true
    @AppStorage("mergeContinueWatchingAndUpNext") private var mergeContinueWatchingAndUpNext = false
    @AppStorage(HomeShelfPrefs.orderKey) private var homeShelfOrderString = ""
    @AppStorage(HomeShelfPrefs.activeKey) private var homeShelfActiveString = ""
    #if os(iOS)
    @AppStorage("offlineModeEnabled") private var offlineModeEnabled = false
    @Query private var downloadedItems: [DownloadedItem]
    #endif

    @State private var heroIndex: Int = 0
    @State private var showSettings = false
    @State private var heroDetailItem: MediaItem?
    @State private var heroPlaybackRequest: HeroPlaybackRequest?
    @State private var seeAllShelf: SeeAllShelf?
    @State private var showOfflinePrompt = false
    // Keyed by heroItems index — only the current slide's trailer is ever fetched/played,
    // and only after a short delay once it's actually the one on screen (see
    // loadHeroVideoBackdrop), so swiping past several slides quickly doesn't fire off a
    // burst of trailer lookups + stream negotiations for slides nobody paused on.
    @State private var heroVideoBackdropIndex: Int?
    @State private var heroVideoBackdropURL: URL?
    @State private var heroVideoBackdropTask: Task<Void, Never>?
    @AppStorage("heroVideoBackdropsEnabled") private var heroVideoBackdropsEnabled = true

    struct HeroPlaybackRequest: Identifiable, Equatable {
        let id = UUID()
        let item: MediaItem
        let startTicks: Int64
    }

    struct SeeAllShelf: Identifiable, Hashable {
        let id = UUID()
        let title: String
        let items: [MediaItem]
        var isLandscape: Bool = false
    }
    @State private var seerrRequestItem: SeerrItem? = nil
    @State private var deepLinkItemID: String? = nil
    private let heroTimer = Timer.publish(every: 8, on: .main, in: .common).autoconnect()

    /// 2 Continue Watching + 2 Up Next + 6 Recently Added — deduped in case the same item
    /// shows up in more than one list. TabView's page style only instantiates the current
    /// page plus its immediate neighbors, so this doesn't mean 10 images loading at once —
    /// each poster/backdrop loads lazily as the user actually swipes to it.
    private var heroItems: [MediaItem] {
        var items: [MediaItem] = []
        items.append(contentsOf: mediaRepo.continueWatching.prefix(2))
        items.append(contentsOf: mediaRepo.nextUp.prefix(2))
        items.append(contentsOf: mediaRepo.recentlyAdded.prefix(6))
        var seen = Set<String>()
        return items.filter { seen.insert($0.id).inserted }
    }
    private var usePortraitHero: Bool { sizeClass == .compact }

    private var heroIsResumable: Bool {
        guard let ud = heroItems[safe: heroIndex]?.userData else { return false }
        return ud.playbackPositionTicks > 0 && !ud.played
    }

    private var heroEpisodeLabel: String? {
        guard let item = heroItems[safe: heroIndex], item.type == .episode else { return nil }
        let s = item.parentIndexNumber.map { "S\($0)" }
        let e = item.indexNumber.map { "E\($0)" }
        return [s, e].compactMap { $0 }.joined().nilIfEmpty
    }

    private var mergedContinueAndNextItems: [MediaItem] {
        var seen = Set<String>()
        return (mediaRepo.continueWatching + mediaRepo.nextUp).filter { seen.insert($0.id).inserted }
    }

    private var orderedVisibleShelves: [HomeShelf] {
        let active = HomeShelfPrefs.active(from: homeShelfActiveString)
        return HomeShelfPrefs.order(from: homeShelfOrderString).filter { active.contains($0) }
    }

    /// Sequencing/visibility is data-driven (order + on/off per HomeShelfSettingsView) —
    /// each case's own content/empty-state gating is unchanged from before this existed.
    @ViewBuilder
    private func shelfView(for shelf: HomeShelf) -> some View {
        switch shelf {
        case .continueWatching:
            if mergeContinueWatchingAndUpNext {
                if !mergedContinueAndNextItems.isEmpty {
                    ShelfRow(title: "Continue Watching", onSeeAll: {
                        seeAllShelf = SeeAllShelf(title: "Continue Watching", items: mergedContinueAndNextItems, isLandscape: true)
                    }) {
                        ForEach(mergedContinueAndNextItems) { item in
                            continueWatchingCard(item)
                        }
                    }
                }
            } else if !mediaRepo.continueWatching.isEmpty {
                ShelfRow(title: "Continue Watching", onSeeAll: {
                    seeAllShelf = SeeAllShelf(title: "Continue Watching", items: mediaRepo.continueWatching, isLandscape: true)
                }) {
                    ForEach(mediaRepo.continueWatching) { item in
                        continueWatchingCard(item)
                    }
                }
            }
        case .nextUp:
            if !mergeContinueWatchingAndUpNext, !mediaRepo.nextUp.isEmpty {
                ShelfRow(title: "Next Up", onSeeAll: {
                    seeAllShelf = SeeAllShelf(title: "Next Up", items: mediaRepo.nextUp, isLandscape: true)
                }) {
                    ForEach(mediaRepo.nextUp) { item in
                        continueWatchingCard(item)
                    }
                }
            }
        case .recentlyAddedMovies:
            if !mediaRepo.recentlyAddedMovies.isEmpty || !mediaRepo.connectionFailed {
                ShelfRow(title: "Recently Added Movies", badge: "NEW", onSeeAll: {
                    seeAllShelf = SeeAllShelf(title: "Recently Added Movies", items: mediaRepo.recentlyAddedMovies)
                }) {
                    mediaShelfContent(mediaRepo.recentlyAddedMovies)
                }
            }
        case .recentlyAddedShows:
            if !mediaRepo.recentlyAddedShows.isEmpty || !mediaRepo.connectionFailed {
                ShelfRow(title: "Recently Added Shows", badge: "NEW", onSeeAll: {
                    seeAllShelf = SeeAllShelf(title: "Recently Added Shows", items: mediaRepo.recentlyAddedShows)
                }) {
                    mediaShelfContent(mediaRepo.recentlyAddedShows)
                }
            }
        case .recentlyReleasedMovies:
            if !mediaRepo.recentlyReleasedMovies.isEmpty {
                ShelfRow(title: "Recently Released Movies", onSeeAll: {
                    seeAllShelf = SeeAllShelf(title: "Recently Released Movies", items: mediaRepo.recentlyReleasedMovies)
                }) {
                    mediaShelfContent(mediaRepo.recentlyReleasedMovies)
                }
            }
        case .recentlyAiredEpisodes:
            if !mediaRepo.recentlyAiredEpisodes.isEmpty {
                ShelfRow(title: "Recently Aired Episodes", onSeeAll: {
                    seeAllShelf = SeeAllShelf(title: "Recently Aired Episodes", items: mediaRepo.recentlyAiredEpisodes, isLandscape: true)
                }) {
                    ForEach(mediaRepo.recentlyAiredEpisodes) { item in
                        continueWatchingCard(item)
                    }
                }
            }
        case .watchAgain:
            if !mediaRepo.watchAgain.isEmpty {
                ShelfRow(title: "Watch Again", onSeeAll: {
                    seeAllShelf = SeeAllShelf(title: "Watch Again", items: mediaRepo.watchAgain)
                }) {
                    mediaShelfContent(mediaRepo.watchAgain)
                }
            }
        case .seerrWatchlist:
            if seerrRepo.isConfigured, seerrDiscoverEnabled, !seerrRepo.watchlist.isEmpty {
                seerrShelf(title: "Watchlist", items: seerrRepo.watchlist)
            }
        case .seerrTrending:
            if seerrRepo.isConfigured, seerrDiscoverEnabled, !seerrRepo.trending.isEmpty {
                seerrShelf(title: "Trending", items: seerrRepo.trending)
            }
        case .seerrPopularMovies:
            if seerrRepo.isConfigured, seerrDiscoverEnabled, !seerrRepo.popularMovies.isEmpty {
                seerrShelf(title: "Popular Movies", items: seerrRepo.popularMovies)
            }
        case .seerrPopularSeries:
            if seerrRepo.isConfigured, seerrDiscoverEnabled, !seerrRepo.popularTV.isEmpty {
                seerrShelf(title: "Popular Series", items: seerrRepo.popularTV)
            }
        }
    }

    @ViewBuilder
    private func continueWatchingCard(_ item: MediaItem) -> some View {
        NavigationLink(value: item) {
#if os(tvOS)
            PosterCard(
                title: itemDisplayTitle(item),
                subtitle: itemDisplaySubtitle(item),
                progress: item.userData?.playedPercentage.map { $0 / 100 },
                imageURL: shelfImageURL(for: item)
            )
#else
            PosterCard(
                title: itemDisplayTitle(item),
                subtitle: itemDisplaySubtitle(item),
                progress: item.userData?.playedPercentage.map { $0 / 100 },
                imageURL: landscapeShelfImageURL(for: item),
                width: 200, height: 113
            )
#endif
        }
#if os(tvOS)
        .buttonStyle(TVCardButtonStyle())
        .focusEffectDisabled()
        .contextMenu { quickLookMenu(item) }
#else
        .buttonStyle(PressableButtonStyle())
        // No custom preview: — a preview whose size doesn't match the tiny source card
        // confuses UIKit's context-menu interaction proxy about which cell was actually
        // touched in a tightly-packed horizontal shelf, causing taps to land on the
        // neighboring card instead of the one under your finger.
        .contextMenu { quickLookMenu(item) }
#endif
    }

    @ViewBuilder
    private var avatarView: some View {
        if let cred = authManager.state.credential, let tag = cred.userImageTag {
            AsyncImage(url: JellyfinMediaClient.userImageURL(baseURL: cred.baseURL, userID: cred.userID, tag: tag, token: cred.accessToken)) { phase in
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
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
    }

    /// Pulled out of the GeometryReader closure in body — inline ternary + if/else there
    /// pushed the surrounding ViewBuilder expression past the type-checker's time budget.
    private func heroDimensions(screenW: CGFloat, screenH: CGFloat) -> (imageH: CGFloat, heroH: CGFloat) {
#if os(tvOS)
        let imageH: CGFloat = screenH * 0.48
        let heroH: CGFloat = imageH + 180
        return (imageH, heroH)
#else
        let rawImageH: CGFloat = (usePortraitHero ? screenW * 1.45 : screenW * 9 / 16) * 0.8
        // On iPad/Mac (regular width — usePortraitHero is iPhone-only), the hero banner
        // was nearly filling the window before any shelves came into view. Capped there;
        // iPhone's portrait hero is already sized off its own aspect ratio and left alone.
        guard !usePortraitHero else { return (rawImageH, rawImageH) }
#if os(macOS)
        let capFraction: CGFloat = 0.6
#else
        let capFraction: CGFloat = 0.7
#endif
        let cap = screenH * capFraction
        let heroH = min(rawImageH + 220, cap)
        let imageH = max(0, heroH - 220)
        return (imageH, heroH)
#endif
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let screenW = proxy.size.width
                let screenH = proxy.size.height
                let dims = heroDimensions(screenW: screenW, screenH: screenH)
                let imageH = dims.imageH
                let heroH = dims.heroH

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Stretchy header — on pull-to-refresh overscroll, grows the hero
                        // image upward into the revealed space instead of showing a plain
                        // black bar above it.
                        GeometryReader { heroGeo in
                            let stretch = max(0, heroGeo.frame(in: .named("homeScroll")).minY)
                            heroBanner(imageH: imageH + stretch, screenW: screenW)
                                .offset(y: -stretch)
                        }
                        .frame(height: heroH)

                        VStack(spacing: 0) {
                            if mediaRepo.connectionFailed && !mediaRepo.isLoading {
                                connectionFailedBanner
                            }
                            ForEach(orderedVisibleShelves) { shelf in
                                shelfView(for: shelf)
                            }
                        }
                        .padding(.top, 12)
#if os(tvOS)
                        .focusSection()
#endif
                    }
                }
                .coordinateSpace(name: "homeScroll")
                .background(DT.Color.backgroundPrimary)
                .ignoresSafeArea(edges: .top)
                .navigationDestination(isPresented: $showSettings) {
                    SettingsView()
                }
                #if os(macOS)
                .onReceive(NotificationCenter.default.publisher(for: .arcfinShowSettings)) { _ in
                    showSettings = true
                }
                #endif
                .navigationDestination(for: MediaItem.self) { item in
                    MediaDetailView(item: item)
                }
                .navigationDestination(item: $heroDetailItem) { item in
                    MediaDetailView(item: item)
                }
                .navigationDestination(item: $seeAllShelf) { shelf in
                    ShelfSeeAllView(title: shelf.title, items: shelf.items, isLandscape: shelf.isLandscape)
                }
#if os(iOS)
                .fullScreenCover(item: $heroPlaybackRequest) { request in
                    PlayerView(item: request.item, startPositionTicks: request.startTicks) { next in
                        heroPlaybackRequest = HeroPlaybackRequest(item: next, startTicks: 0)
                    }
                }
#endif
                // macOS doesn't present from heroPlaybackRequest at all — see
                // PlaybackPresenter's doc comment. Its own onChange below forwards a set
                // request straight to the shared presenter instead, which ContentView
                // renders as a real full-window overlay (a .sheet can't fill or fullscreen
                // a window the way a plain modal panel is designed to stay small).
                #if os(macOS)
                .onChange(of: heroPlaybackRequest) { _, request in
                    guard let request else { return }
                    playbackPresenter.present(request.item, startTicks: request.startTicks)
                    heroPlaybackRequest = nil
                }
                #endif
            }
            .navigationTitle("")
#if os(iOS)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    // Was a decorative placeholder (empty action) for a notification center
                    // this app doesn't have — only local, in-the-moment alerts (download
                    // complete, Seerr request status) exist, with no server-side feed and
                    // nothing to show a history of. A bell implying one would be misleading.
                    Button { showSettings = true } label: {
                        avatarView
                            .frame(width: 34, height: 34)
                            .glassEffect(.regular.tint(DT.Color.accent), in: .circle)
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
#elseif os(macOS)
            // No pull-to-refresh gesture on a pointer-driven window — an explicit
            // toolbar action stands in for it. Settings has no other entry point from
            // Home on macOS (the avatar button that opens it on iOS lived only in the
            // iOS-only toolbar above).
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await loadHome(force: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showSettings = true } label: {
                        avatarView
                            .frame(width: 22, height: 22)
                    }
                    .help("Settings")
                }
            }
#endif
        }
        // .task(id:) rather than a bare .task { } — a bare .task only ever runs once, at
        // this view's first mount, reading whatever authManager.state happens to be at that
        // exact instant. That race was invisible on iOS's plain TabView (one tab root alive
        // at a time), but macOS's .tabViewStyle(.sidebarAdaptable) renders via
        // NavigationSplitView under the hood, mounting differently — the first .task run
        // could see a not-yet-settled auth state and silently no-op, leaving Home blank
        // until something else (the manual refresh button) triggered a reload. Keying to
        // the credential's own id (not the whole AuthState) re-runs this whenever it
        // actually changes — sign-in, profile switch — without also re-firing on incidental
        // field updates to the same credential (e.g. the avatar-tag backfill in
        // checkStoredAuth). Also makes the separate onChange(of: authManager.state) that
        // used to be right below this redundant, since it did the same thing less reliably.
        //
        // A bare `await loadHome()` here would be cancelled right along with the .task
        // itself whenever SwiftUI reruns it — on macOS this reliably killed every retry
        // attempt mid-flight during the exact NavigationSplitView remount churn this
        // modifier exists to work around, logging "cancelled" (NSURLErrorCancelled) for
        // every attempt even though the server was actually reachable. The Retry button
        // below never hit this because it fires a plain Task of its own, untied to this
        // view's task lifecycle — detaching into one here the same way lets the load
        // survive that cancellation instead of losing the race every cold launch.
        .task(id: authManager.state.credential?.id) { Task { await loadHome() } }
        .refreshable { await loadHome(force: true) }
        #if os(iOS)
        .onChange(of: mediaRepo.connectionFailed) { wasFailed, isFailed in
            if isFailed && !wasFailed { showOfflinePrompt = true }
        }
        .confirmationDialog(
            "Can't reach your server", isPresented: $showOfflinePrompt, titleVisibility: .visible
        ) {
            Button("Retry") {
                guard case .authenticated(let cred) = authManager.state else { return }
                Task { await mediaRepo.load(credential: cred, authClient: authManager.authClient) }
            }
            if !downloadedItems.isEmpty {
                Button("Watch Downloads Instead") { offlineModeEnabled = true }
            }
            Button("Dismiss", role: .cancel) {}
        } message: {
            Text("Check your connection or Server Settings, then retry.")
        }
        #endif
        .onReceive(heroTimer) { _ in
            guard heroItems.count > 1 else { return }
            // A trailer is actively showing for this slide — let loadHeroVideoBackdrop's own
            // 15s timeout advance instead of jumping away mid-playback just because the
            // regular rotation interval happened to land first.
            guard heroVideoBackdropIndex != heroIndex else { return }
            withAnimation(DT.Animation.slow) { heroIndex = (heroIndex + 1) % heroItems.count }
        }
        .onChange(of: heroIndex) { _, _ in loadHeroVideoBackdrop() }
        // heroItems is computed live from continueWatching/nextUp/recentlyAdded — a data
        // refresh can shrink it while heroIndex (persistent @State) still points past the new
        // end. TabView(selection:) doesn't clamp that itself, so it asked its internal
        // UICollectionView to scroll to an index that no longer existed — a hard crash
        // (_validateScrollingTargetIndexPath), confirmed from a real TestFlight crash log.
        .onChange(of: heroItems.count) { _, newCount in
            guard heroIndex >= newCount else { return }
            // max(0, ...) covers shrinking all the way to zero too, not just "smaller but
            // still non-empty" — 0 is an inert, always-valid value to sit at either way.
            heroIndex = max(0, newCount - 1)
        }
        .onAppear { loadHeroVideoBackdrop() }
        .onReceive(NotificationCenter.default.publisher(for: .arcfinPlayItem)) { note in
            if let id = note.userInfo?["itemID"] as? String {
                UserDefaults.standard.removeObject(forKey: "arcfin.pendingPlayID")
                deepLinkItemID = id
                heroDetailItem = mediaRepo.continueWatching.first { $0.id == id }
                    ?? mediaRepo.recentlyAdded.first { $0.id == id }
            }
        }
        .sheet(item: $seerrRequestItem) { item in
            SeerrRequestConfirmSheet(item: item, requestingItem: $seerrRequestItem)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
    }

    // MARK: - Home data load

    private func loadHome(force: Bool = false) async {
        guard case .authenticated(let cred) = authManager.state else { return }
        await mediaRepo.load(credential: cred, authClient: authManager.authClient, force: force)
        mediaRepo.prefetchQuickLookAssets(for: mediaRepo.continueWatching + mediaRepo.recentlyAdded)
        TopShelfBridge.save(
            continueWatching: mediaRepo.continueWatching.prefix(5).map { item in
                TopShelfMediaItem(
                    id: item.id, title: item.name,
                    subtitle: itemDisplaySubtitle(item),
                    imageURL: mediaRepo.tvImageURL(for: item, fillWidth: 640),
                    progress: item.userData?.playedPercentage.map { $0 / 100 } ?? 0
                )
            },
            recentlyAdded: mediaRepo.recentlyAdded.prefix(3).map { item in
                TopShelfMediaItem(
                    id: item.id, title: item.name, subtitle: nil,
                    imageURL: mediaRepo.tvImageURL(for: item, fillWidth: 640),
                    progress: 0
                )
            }
        )
        // Resolve deep link — prefer in-memory ID (warm launch), fall back to
        // UserDefaults buffer written by onOpenURL before this view appeared (cold launch).
        let pendingID = deepLinkItemID
            ?? UserDefaults.standard.string(forKey: "arcfin.pendingPlayID")
        if let id = pendingID {
            UserDefaults.standard.removeObject(forKey: "arcfin.pendingPlayID")
            deepLinkItemID = nil
            heroDetailItem = mediaRepo.continueWatching.first { $0.id == id }
                ?? mediaRepo.recentlyAdded.first { $0.id == id }
        }
        if seerrRepo.isConfigured && seerrDiscoverEnabled {
            await seerrRepo.loadDiscover()
            await seerrRepo.loadWatchlist()
            let seerrQuickLookURLs = (seerrRepo.trending + seerrRepo.popularMovies + seerrRepo.popularTV + seerrRepo.watchlist).flatMap { item in
                [item.backdropURL, item.posterURL].compactMap { $0 }
            }
            mediaRepo.prefetch(urls: seerrQuickLookURLs)
        }
    }

    // MARK: - Connection failed banner

    private var connectionFailedBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 18))
                    .foregroundStyle(Color(hex: "f59e0b"))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Can't reach your server")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DT.Color.textPrimary)
                    Text("Check your connection or Server Settings, then retry.")
                        .font(.system(size: 12))
                        .foregroundStyle(DT.Color.textSecondary)
                }
                Spacer()
                Button("Retry") {
                    guard case .authenticated(let cred) = authManager.state else { return }
                    Task { await mediaRepo.load(credential: cred, authClient: authManager.authClient) }
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DT.Color.accent)
            }
            #if os(iOS)
            if !downloadedItems.isEmpty {
                Button {
                    offlineModeEnabled = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("Watch Downloads Instead")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DT.Color.accent)
                }
            }
            #endif
        }
        .padding(12)
        .background(Color(hex: "f59e0b").opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: DT.Radius.lg).stroke(Color(hex: "f59e0b").opacity(0.25), lineWidth: 1))
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.bottom, DT.Spacing.md)
    }

    // MARK: - Seerr shelf

    @ViewBuilder
    private func seerrShelf(title: String, items: [SeerrItem]) -> some View {
        ShelfRow(title: title, onSeeAll: nil) {
            ForEach(items) { item in
                Button {
                    seerrRequestItem = item
                } label: {
                    PosterCard(
                        title: item.title,
                        subtitle: item.year,
                        imageURL: seerrShelfImageURL(for: item)
                    )
                }
#if os(tvOS)
                .buttonStyle(TVCardButtonStyle())
                .focusEffectDisabled()
#else
                .buttonStyle(PressableButtonStyle())
                .contextMenu { seerrQuickLookMenu(item) }
#endif
            }
        }
    }

    private func seerrShelfImageURL(for item: SeerrItem) -> URL? {
#if os(tvOS)
        item.backdropURL ?? item.posterURL
#else
        item.posterURL
#endif
    }

    // MARK: - Hero banner

    private func heroBanner(imageH: CGFloat, screenW: CGFloat) -> some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                heroBackground(imageH: imageH, screenW: screenW)
                    .overlay(heroImageFade.allowsHitTesting(false))
                    .animation(DT.Animation.slow, value: heroIndex)
                    .contentShape(Rectangle())
                    // simultaneousGesture, not .onTapGesture directly — a plain tap gesture
                    // stacked on top of the page-style TabView below was winning gesture
                    // priority and blocking swipe-to-change-page entirely.
                    .simultaneousGesture(
                        TapGesture().onEnded {
                            if let item = heroItems[safe: heroIndex] { heroDetailItem = item }
                        }
                    )
                if !usePortraitHero { Spacer(minLength: 0) }
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

            heroContent.padding(.bottom, usePortraitHero ? 32 : 24)
        }
        .background(DT.Color.backgroundPrimary)
    }

    private var heroImageFade: some View {
        LinearGradient(
            stops: usePortraitHero
                ? [.init(color: .clear, location: 0.3),
                   .init(color: DT.Color.backgroundPrimary.opacity(0.5), location: 0.75),
                   .init(color: DT.Color.backgroundPrimary, location: 1)]
                : [.init(color: .clear, location: 0.4),
                   .init(color: DT.Color.backgroundPrimary.opacity(0.55), location: 0.78),
                   .init(color: DT.Color.backgroundPrimary, location: 1)],
            startPoint: .top, endPoint: .bottom
        )
    }

    @ViewBuilder
    private func heroBackground(imageH: CGFloat, screenW: CGFloat) -> some View {
#if !os(iOS)
        let imageType: JellyfinImageType = usePortraitHero ? .primary : .backdrop
        let fillW = usePortraitHero ? 600 : 900
        ZStack {
            if let item = heroItems[safe: heroIndex],
               let url = mediaRepo.imageURL(for: item, type: imageType, fillWidth: fillW) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    default: heroGradient(for: heroIndex)
                    }
                }
            } else {
                heroGradient(for: heroIndex)
            }

            // Same reasoning as heroImage's overlay below — layered on top of the still
            // image rather than replacing it.
            if let videoURL = heroVideoBackdropURL, heroVideoBackdropIndex == heroIndex {
                HeroVideoBackdropView(url: videoURL)
                    .transition(.opacity)
            }
        }
        .frame(width: screenW, height: imageH)
        .clipped()
#else
        // Page-style TabView, not a single crossfading image — lets the user swipe
        // between hero items, and only ever instantiates the current page plus its
        // immediate neighbors (SwiftUI's own page-style lazy-loading), so this never
        // fires off requests for all heroItems' images at once.
        TabView(selection: $heroIndex) {
            ForEach(Array(heroItems.enumerated()), id: \.offset) { index, item in
                heroImage(item: item, index: index, imageH: imageH, screenW: screenW)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(width: screenW, height: imageH)
#endif
    }

#if os(iOS)
    private func heroImage(item: MediaItem, index: Int, imageH: CGFloat, screenW: CGFloat) -> some View {
        let imageType: JellyfinImageType = usePortraitHero ? .primary : .backdrop
        let fillW = usePortraitHero ? 600 : 900
        return ZStack {
            Group {
                if let url = mediaRepo.imageURL(for: item, type: imageType, fillWidth: fillW) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().scaledToFill()
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        default: heroGradient(for: index)
                        }
                    }
                } else {
                    heroGradient(for: index)
                }
            }

            // Layered on top of the still image rather than replacing it — the image is
            // already loading/visible instantly, so the video only ever enhances it once
            // its own fetch+negotiation finishes, instead of the slide going blank first.
            if heroVideoBackdropIndex == index, let videoURL = heroVideoBackdropURL {
                HeroVideoBackdropView(url: videoURL)
                    .transition(.opacity)
            }
        }
        .frame(width: screenW, height: imageH)
        .clipped()
    }
#endif

    private func heroGradient(for index: Int) -> some View {
        let p: [[Color]] = [
            [Color(hex: "1a0a2e"), Color(hex: "0a1628")],
            [Color(hex: "1c0e00"), Color(hex: "0e0a00")],
            [Color(hex: "0a0a1c"), Color(hex: "060610")],
        ]
        return LinearGradient(colors: p[index % p.count] + [DT.Color.backgroundPrimary],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: - Hero content

    private var heroContent: some View {
        VStack(spacing: 0) {
            if let item = heroItems[safe: heroIndex] {
                AsyncImage(url: mediaRepo.logoURL(for: item)) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFit()
                            .frame(maxWidth: 240 * DT.Scale.font, maxHeight: 76 * DT.Scale.font)
                            .shadow(color: .black.opacity(0.7), radius: 12)
                    } else {
                        Text(item.name)
                            .font(.system(size: 28 * DT.Scale.font, weight: .heavy))
                            .foregroundStyle(.white)
                            .tracking(-0.8)
                            .multilineTextAlignment(.center)
                            .shadow(color: .black.opacity(0.9), radius: 10)
                            .padding(.horizontal, 32)
                    }
                }
                .id(heroIndex)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.3), value: heroIndex)

                HStack(spacing: 8) {
                    if let rating = item.communityRating, rating > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill").font(.system(size: 10 * DT.Scale.font))
                            Text(String(format: "%.1f", rating)).font(.system(size: 12 * DT.Scale.font, weight: .semibold))
                        }
                        .foregroundStyle(Color(hex: "f59e0b"))
                    }
                    Text(heroMeta(item))
                        .font(.system(size: 12 * DT.Scale.font))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.top, 7)
                .animation(nil, value: heroIndex)

                if let pct = item.userData?.playedPercentage, pct > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.25)).frame(height: 3)
                            Capsule().fill(DT.Color.accent).frame(width: geo.size.width * CGFloat(min(pct / 100, 1)), height: 3)
                        }
                    }
                    .frame(width: 120, height: 3)
                    .padding(.top, 8)
                    .animation(nil, value: heroIndex)
                }
            }

#if os(tvOS)
            HStack(spacing: 12 * DT.Scale.font) {
                Button {} label: {
                    TVHeroButtonLabel(icon: "play.fill", text: heroIsResumable ? "Resume" : "Play", isPrimary: true)
                }
                .buttonStyle(TVCardButtonStyle())
                .focusEffectDisabled()

                Button {
                    if let item = heroItems[safe: heroIndex] { heroDetailItem = item }
                } label: {
                    TVHeroButtonLabel(icon: "info.circle", text: "More Info")
                }
                .buttonStyle(TVCardButtonStyle())
                .focusEffectDisabled()
            }
            .padding(.top, 16)
#else
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    Button {
                        guard let item = heroItems[safe: heroIndex] else { return }
                        let resumable = (item.userData?.playbackPositionTicks ?? 0) > 0 && !(item.userData?.played ?? false)
                        heroPlaybackRequest = HeroPlaybackRequest(
                            item: item,
                            startTicks: resumable ? (item.userData?.playbackPositionTicks ?? 0) : 0
                        )
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill").font(.system(size: 12 * DT.Scale.font))
                            Text(heroIsResumable ? "Resume" : "Play").font(.system(size: 14 * DT.Scale.font, weight: .bold))
                            if let episodeLabel = heroEpisodeLabel {
                                Text(episodeLabel)
                                    .font(.system(size: 11 * DT.Scale.font, weight: .semibold))
                                    .opacity(0.85)
                            }
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 28).padding(.vertical, 11)
                    }
                    .glassEffect(.regular.tint(DT.Color.accent).interactive(), in: .rect(cornerRadius: 10))

                    Button {
                        if let item = heroItems[safe: heroIndex] { heroDetailItem = item }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle").font(.system(size: 12 * DT.Scale.font))
                            Text("More Info").font(.system(size: 13 * DT.Scale.font, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20).padding(.vertical, 11)
                    }
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 10))
                }
            }
            .padding(.top, 16)
#endif

            if heroItems.count > 1 {
                HStack(spacing: 6) {
                    ForEach(0..<heroItems.count, id: \.self) { i in
                        Capsule()
                            .fill(i == heroIndex ? .white : Color.white.opacity(0.3))
                            .frame(width: i == heroIndex ? 18 : 6, height: 5)
                            .onTapGesture { withAnimation(DT.Animation.standard) { heroIndex = i } }
                            .animation(DT.Animation.fast, value: heroIndex)
                    }
                }
                .padding(.top, 14)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func heroMeta(_ item: MediaItem) -> String {
        var parts: [String] = []
        if let year = item.productionYear { parts.append(String(year)) }
        switch item.type {
        case .series:  parts.append("Series")
        case .episode: parts.append(itemDisplaySubtitle(item) ?? "Episode")
        default:       parts.append("Movie")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Hero video backdrop

    /// Fetches (after a short pause, so quickly swiping past several slides doesn't fire a
    /// burst of these) whether the current hero slide has a local trailer indexed on the
    /// server, and if so resolves it to a real playable stream URL the same way the main
    /// player does — reusing getPlaybackInfo rather than hand-building a stream URL, since
    /// it already handles direct-play vs transcode negotiation correctly.
    private func loadHeroVideoBackdrop() {
        let log = Telemetry.logger(category: "HeroVideoBackdrop")
        heroVideoBackdropTask?.cancel()
        heroVideoBackdropURL = nil
        heroVideoBackdropIndex = nil
        guard heroVideoBackdropsEnabled, let item = heroItems[safe: heroIndex],
              case .authenticated(let credential) = authManager.state
        else { return }
        let index = heroIndex
        let authHeader = authManager.authClient.authHeader(token: credential.accessToken)
        heroVideoBackdropTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            let client = JellyfinMediaClient()
            let trailer: MediaItem?
            do {
                trailer = try await client.getTrailers(credential: credential, authHeader: authHeader, itemId: item.id, limit: 1).first
            } catch {
                log.error("getTrailers failed for \(item.id, privacy: .public): \(error, privacy: .public)")
                return
            }
            guard let trailer, !Task.isCancelled else {
                log.debug("no local trailer indexed for \(item.id, privacy: .public)")
                return
            }
            let info: JellyfinPlaybackInfo
            do {
                info = try await client.getPlaybackInfo(credential: credential, authHeader: authHeader, itemId: trailer.id)
            } catch {
                log.error("getPlaybackInfo failed for trailer \(trailer.id, privacy: .public): \(error, privacy: .public)")
                return
            }
            guard !Task.isCancelled, heroIndex == index else { return }
            withAnimation(.easeIn(duration: 0.6)) {
                heroVideoBackdropURL = info.playURL
                heroVideoBackdropIndex = index
            }
            // Loops indefinitely otherwise — auto-reverts to the still backdrop after a
            // short preview instead, same idea as tvOS's own featured-app hero rotators.
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled, heroIndex == index else { return }
            withAnimation(.easeOut(duration: 0.6)) {
                heroVideoBackdropURL = nil
                heroVideoBackdropIndex = nil
            }
            // The regular rotation timer skips advancing while this slide's trailer is
            // playing (see its onReceive guard) — advance here instead, right as the
            // trailer ends, rather than leaving the still image sitting until the timer's
            // next regular tick.
            if heroItems.count > 1 {
                withAnimation(DT.Animation.slow) { heroIndex = (index + 1) % heroItems.count }
            }
        }
    }

    @ViewBuilder
    func quickLookMenu(_ item: MediaItem) -> some View {
        if statsRepo.isConfigured {
            Button {
                Task { try? await statsRepo.addToWatchlist(itemId: item.id) }
            } label: {
                Label("Add to Watchlist", systemImage: "bookmark")
            }
        }
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

    @ViewBuilder
    private func seerrQuickLookMenu(_ item: SeerrItem) -> some View {
        Label(item.title, systemImage: item.mediaType == .tv ? "tv" : "film")
        if let year = item.year {
            Label(year, systemImage: "calendar")
        }
        if item.availabilityStatus != .available {
            Button {
                Task { try? await seerrRepo.createRequest(mediaType: item.mediaType, mediaId: item.id) }
            } label: {
                Label("Request via Seerr", systemImage: "plus.circle")
            }
        }
    }


    @ViewBuilder
    private func mediaShelfContent(_ items: [MediaItem], placeholderCount: Int = 6) -> some View {
        if items.isEmpty {
            ForEach(0..<placeholderCount, id: \.self) { _ in
                PosterCard(title: "Loading Title")
            }
            .redacted(reason: .placeholder)
        } else {
            ForEach(items) { item in
                NavigationLink(value: item) {
                    PosterCard(
                        title: itemDisplayTitle(item),
                        subtitle: itemDisplaySubtitle(item),
                        imageURL: shelfImageURL(for: item)
                    )
                }
#if os(tvOS)
                .buttonStyle(TVCardButtonStyle())
                .focusEffectDisabled()
                .contextMenu { quickLookMenu(item) }
#else
                .buttonStyle(PressableButtonStyle())
                .contextMenu { quickLookMenu(item) }
#endif
            }
        }
    }

    private func shelfImageURL(for item: MediaItem) -> URL? {
#if os(tvOS)
        mediaRepo.tvImageURL(for: item, fillWidth: 640)
#else
        mediaRepo.imageURL(for: item)
#endif
    }

    /// Continue Watching / Up Next use landscape cards for everything (movies included),
    /// matching the convention most streaming apps use for "resume this" rows — a movie's
    /// thumb/backdrop, or an episode's own screenshot.
    private func landscapeShelfImageURL(for item: MediaItem) -> URL? {
        if item.type == .episode {
            return mediaRepo.imageURL(for: item, type: .primary, fillWidth: 400)
        }
        return mediaRepo.imageURL(for: item, type: .thumb, fillWidth: 400)
            ?? mediaRepo.imageURL(for: item, type: .backdrop, fillWidth: 400)
    }

    // MARK: - Helpers

    private func itemDisplayTitle(_ item: MediaItem) -> String {
        if item.type == .episode {
            return item.seriesName?.nilIfEmpty ?? item.name.nilIfEmpty ?? "Unknown"
        }
        return item.name.nilIfEmpty ?? "Unknown"
    }

    private func itemDisplaySubtitle(_ item: MediaItem) -> String? {
        if item.type == .episode {
            let s = item.parentIndexNumber.map { "S\($0)" }
            let e = item.indexNumber.map { "E\($0)" }
            let code = [s, e].compactMap { $0 }.joined()
            let episodeName = item.name.nilIfEmpty
            return [code.nilIfEmpty, episodeName].compactMap { $0 }.joined(separator: " · ").nilIfEmpty
        }
        return item.productionYear.map { "\($0)" }
    }
}

// MARK: - AuthState helpers

private extension AuthState {
    var displayInitials: String {
        guard case .authenticated(let cred) = self else { return "?" }
        return cred.displayName.split(separator: " ")
            .prefix(2).compactMap { $0.first }.map { String($0).uppercased() }.joined()
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#Preview {
    MainTabView()
        .environment(AuthManager())
        .environment(MediaRepository())
        .environment(SeerrRepository())
}
