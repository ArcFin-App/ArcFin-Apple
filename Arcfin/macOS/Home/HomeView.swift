// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import SwiftData
import Combine
import JellyfinAPI
import SeerrAPI
import AuthCore
import Persistence

struct HomeView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(MediaRepository.self) private var mediaRepo
    @Environment(SeerrRepository.self) private var seerrRepo
    @Environment(PlaybackPresenter.self) private var playbackPresenter
    @Environment(\.horizontalSizeClass) private var sizeClass

    @AppStorage("seerrDiscoverEnabled") private var seerrDiscoverEnabled = true
    @AppStorage("mergeContinueWatchingAndUpNext") private var mergeContinueWatchingAndUpNext = false
    @AppStorage(HomeShelfPrefs.orderKey) private var homeShelfOrderString = ""
    @AppStorage(HomeShelfPrefs.activeKey) private var homeShelfActiveString = ""
    @AppStorage(HomeShelfPrefs.shuffleKey) private var shuffleHomeShelves = false
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("offlineModeEnabled") private var offlineModeEnabled = false
    @Query private var downloadedItems: [DownloadedItem]

    @State private var model = HomeModel()
    @State private var hero = HomeHeroCarousel()
    @State private var showSettings = false
    @Environment(\.openSettings) private var openSettings
    @AppStorage(StreamingServicePrefs.key) private var streamingServicesData = Data()
    @AppStorage(SeerrRepository.regionOverrideKey) private var seerrRegionOverride = ""
    @State private var trailerLaunchItem: MediaItem?
    @Namespace private var zoomNamespace
    @State private var seeAllShelf: SeeAllShelf?
    @State private var showOfflinePrompt = false
    @AppStorage("heroVideoBackdropsEnabled") private var heroVideoBackdropsEnabled = true
    private let heroTimer = Timer.publish(every: 8, on: .main, in: .common).autoconnect()

    private var heroItems: [MediaItem] { HomeHeroCarousel.items(in: mediaRepo) }
    private var usePortraitHero: Bool { sizeClass == .compact }

    private var orderedVisibleShelves: [HomeShelf] {
        model.shelves(order: homeShelfOrderString, active: homeShelfActiveString, shuffled: shuffleHomeShelves)
    }

    private var recentlyAvailableRequests: [SeerrRequestItem] {
        HomeShelfLoader.recentlyAvailable(seerrRepo.requests)
    }

    /// Pulled out of the GeometryReader closure in body — inline ternary + if/else there
    /// pushed the surrounding ViewBuilder expression past the type-checker's time budget.
    private func heroDimensions(screenW: CGFloat, screenH: CGFloat) -> (imageH: CGFloat, heroH: CGFloat) {
        let rawImageH: CGFloat = (usePortraitHero ? screenW * 1.45 : screenW * 9 / 16) * 0.8
        // On iPad/Mac (regular width — usePortraitHero is iPhone-only), the hero banner
        // was nearly filling the window before any shelves came into view. Capped there;
        // iPhone's portrait hero is already sized off its own aspect ratio and left alone.
        guard !usePortraitHero else { return (rawImageH, rawImageH) }
        let capFraction: CGFloat = 0.6
        let cap = screenH * capFraction
        let heroH = min(rawImageH + 220, cap)
        let imageH = max(0, heroH - 220)
        return (imageH, heroH)
    }

    // The modifier chain below is split across three properties: as one expression it grew
    // past what the type checker can solve in reasonable time.
    private var homeNavigation: some View {
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
                            if (mediaRepo.connectionFailed && !mediaRepo.isLoading) || model.isSlowFirstLoad {
                                HomeConnectionBanner(hasDownloads: !downloadedItems.isEmpty)
                            }
                            ForEach(orderedVisibleShelves) { shelf in
                                if HomeModel.showsShelfSkeleton(shuffled: shuffleHomeShelves, mediaRepo: mediaRepo),
                                   !HomeShelfPrefs.pinned.contains(shelf), !shelf.isSeerr {
                                    ShelfRow(title: shelf.title) { HomePosterCards(items: [], card: posterCard) }
                                } else {
                                    shelfView(for: shelf)
                                        .accessibilityElement(children: .contain)
                                        .accessibilityIdentifier("shelf.\(shelf.rawValue)")
                                }
                            }
                        }
                        .padding(.top, 12)
                    }
                }
                .coordinateSpace(name: "homeScroll")
                .screenBackground()
                .ignoresSafeArea(edges: .top)
                .navigationDestination(isPresented: $showSettings) {
                    SettingsView()
                }
                .onReceive(NotificationCenter.default.publisher(for: .arcfinRefresh)) { _ in
                    Task { await loadHome(force: true) }
                }
                .navigationDestination(for: MediaItem.self) { item in
                    MediaDetailView(item: item, zoomNamespace: zoomNamespace)
                        .zoomNavigationTransition(id: item.id, in: zoomNamespace)
                }
                .navigationDestination(item: $model.detailItem) { item in
                    MediaDetailView(item: item)
                }
                .navigationDestination(item: $seeAllShelf) { shelf in
                    ShelfSeeAllView(title: shelf.title, items: shelf.items, isLandscape: shelf.isLandscape)
                }
                // macOS doesn't present from the hero's playback request at all — see
                // PlaybackPresenter's doc comment. Its own onChange below forwards a set
                // request straight to the shared presenter instead, which ContentView
                // renders as a real full-window overlay (a .sheet can't fill or fullscreen
                // a window the way a plain modal panel is designed to stay small).
                .onChange(of: hero.playbackRequest) { _, request in
                    guard let request else { return }
                    playbackPresenter.present(request.item, startTicks: request.startTicks)
                    hero.playbackRequest = nil
                }
            }
            .navigationTitle("")
            // No pull-to-refresh gesture on a pointer-driven window — an explicit
            // toolbar action stands in for it. Settings has no other entry point from
            // Home on macOS (the avatar button that opens it on iOS lives only in the
            // iOS toolbar).
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await loadHome(force: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh")
                    .help("Refresh")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { openSettings() } label: {
                        HomeAvatar()
                            .frame(width: 22, height: 22)
                    }
                    .accessibilityLabel("Settings")
                    .help("Settings")
                }
            }
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
        .refreshable {
            if shuffleHomeShelves { model.reshuffleShelves() }
            await loadHome(force: true)
        }
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
        .onReceive(heroTimer) { _ in
            hero.advance(itemCount: heroItems.count, isActive: scenePhase == .active)
        }
        .onChange(of: hero.index) { _, _ in loadHeroVideoBackdrop() }
        .onChange(of: heroItems.count) { _, newCount in
            hero.clamp(toCount: newCount)
        }
    }

    private var homeObservers: some View {
        homeNavigation
        .onAppear {
            hero.isHomeVisible = true
            loadHeroVideoBackdrop()
        }
        .onDisappear { hero.isHomeVisible = false }
        // The order only ever changes while Home is off-screen (tab switch, app backgrounded)
        // or when the user pulls to refresh, so what's on screen never rearranges itself.
        .onReceive(NotificationCenter.default.publisher(for: .arcfinHomeTabLeft)) { _ in
            if shuffleHomeShelves { model.reshuffleShelves() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background, shuffleHomeShelves { model.reshuffleShelves() }
        }
        .onChange(of: shuffleHomeShelves) { _, isOn in
            if isOn { model.reshuffleShelves() }
        }
        .task(id: mediaRepo.isLoading) {
            await model.watchFirstLoad(mediaRepo: mediaRepo)
        }
        .task(id: "\(StreamingServicePrefs.decode(streamingServicesData).map(\.id))-\(seerrRepo.hasCatalog)-\(seerrRegionOverride)") {
            await model.loadServiceRows(seerrRepo: seerrRepo)
        }
        .task(id: recentlyAvailableRequests.map(\.id)) {
            await model.loadNowAvailable(recentlyAvailableRequests, authManager: authManager)
        }
    }

    var body: some View {
        homeObservers
        .onChange(of: (mediaRepo.continueWatching + mediaRepo.nextUp + mediaRepo.recentlyAdded).map(\.id), initial: true) { _, _ in
            let items = HomeModel.continueAndNext(in: mediaRepo)
            Task {
                await WidgetSnapshotUpdater.update(
                    items: items,
                    recentlyAdded: mediaRepo.recentlyAdded,
                    artworkURL: { item in
                        if item.type == .episode { return mediaRepo.imageURL(for: item, type: .primary, fillWidth: 600) }
                        return mediaRepo.imageURL(for: item, type: .thumb, fillWidth: 600)
                            ?? mediaRepo.imageURL(for: item, type: .backdrop, fillWidth: 600)
                            ?? mediaRepo.imageURL(for: item, type: .primary, fillWidth: 600)
                    },
                    posterURL: { mediaRepo.imageURL(for: $0, type: .primary, fillWidth: 300) })
            }
        }
        .onContinueUserActivity(ArcfinActivity.viewTitle) { activity in
            if let id = activity.userInfo?["itemID"] as? String {
                ArcfinRouting.openItem(id: id)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .arcfinPlayItem)) { note in
            if let id = note.userInfo?["itemID"] as? String {
                UserDefaults.standard.removeObject(forKey: "arcfin.pendingPlayID")
                model.openDeepLinkItem(id: id, authManager: authManager, mediaRepo: mediaRepo)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .arcfinResume)) { _ in
            model.resumeLatest(mediaRepo: mediaRepo)
        }
        .onReceive(NotificationCenter.default.publisher(for: WatchRoute.notification)) { _ in
            model.playPendingWatch(authManager: authManager)
        }
        .quickPlayback($model.playbackRequest, trailer: $trailerLaunchItem) { Task { await loadHome(force: true) } }
        .onReceive(NotificationCenter.default.publisher(for: .arcfinOpenSeerrTitle)) { note in
            if let id = note.userInfo?["id"] as? String { openSeerrDeepLink(id: id) }
        }
        .onAppear {
            if let id = UserDefaults.standard.string(forKey: "arcfin.pendingSeerrTitle") { openSeerrDeepLink(id: id) }
        }
        .sheet(item: $model.seerrDetailItem) { item in
            NavigationStack { SeerrItemDetailView(item: item) }
        }
        .sheet(item: $model.seerrRequestItem) { item in
            SeerrRequestConfirmSheet(item: item, requestingItem: $model.seerrRequestItem)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
    }

    // MARK: - Home data load

    private func loadHome(force: Bool = false) async {
        guard await model.loadShelves(force: force, authManager: authManager, mediaRepo: mediaRepo) else { return }
        // Everything the shelves already hold: titles in progress or queued up, favorites,
        // recent additions and what was watched lately, so search covers more than "latest".
        let indexable = mediaRepo.continueWatching + mediaRepo.nextUp + mediaRepo.favorites
            + mediaRepo.recentlyAdded + mediaRepo.recentlyAddedMovies + mediaRepo.recentlyAddedShows
            + mediaRepo.watchAgain
        Task { await SpotlightIndexer.index(indexable) }
        let splashPicks = mediaRepo.recentlyAddedMovies + mediaRepo.recentlyAddedShows + mediaRepo.recentlyAdded
        Task {
            await SplashMosaicStore.save(splashPicks) { mediaRepo.imageURL(for: $0, type: .primary, fillWidth: 180) }
        }
        model.saveTopShelf(mediaRepo: mediaRepo, title: { $0.name }, subtitle: HomeText.subtitle)
        model.openPendingDeepLink(authManager: authManager, mediaRepo: mediaRepo)
        if UserDefaults.standard.bool(forKey: "arcfin.pendingResume") { model.resumeLatest(mediaRepo: mediaRepo) }
        model.playPendingWatch(authManager: authManager)
        await model.loadDiscover(enabled: seerrDiscoverEnabled, mediaRepo: mediaRepo, seerrRepo: seerrRepo)
    }

    private func loadHeroVideoBackdrop() {
        hero.loadVideoBackdrop(enabled: heroVideoBackdropsEnabled, authManager: authManager, mediaRepo: mediaRepo)
    }

    private func openSeerrDeepLink(id: String) {
        UserDefaults.standard.removeObject(forKey: "arcfin.pendingSeerrTitle")
        if let entry = SeerrSpotlightStore.entry(id: id), let item = entry.seerrItem { model.seerrDetailItem = item }
    }

    // MARK: - Hero banner

    private func heroBanner(imageH: CGFloat, screenW: CGFloat) -> some View {
        HomeHeroBanner(isPortrait: usePortraitHero, items: heroItems, carousel: hero, openItem: { model.detailItem = $0 }) {
            heroBackground(imageH: imageH, screenW: screenW)
        }
    }

    private func heroBackground(imageH: CGFloat, screenW: CGFloat) -> some View {
        let imageType: JellyfinImageType = usePortraitHero ? .primary : .backdrop
        let fillW = usePortraitHero ? 600 : 900
        return ZStack {
            if let item = heroItems[safe: hero.index],
               let url = mediaRepo.imageURL(for: item, type: imageType, fillWidth: fillW) {
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    default: HomeHeroPlaceholder(index: hero.index)
                    }
                }
            } else {
                HomeHeroPlaceholder(index: hero.index)
            }

            // Layered on top of the still image rather than replacing it — the image is
            // already loading/visible instantly, so the video only ever enhances it once
            // its own fetch+negotiation finishes, instead of the slide going blank first.
            if let videoURL = hero.videoBackdropURL, hero.videoBackdropIndex == hero.index {
                HeroVideoBackdropView(url: videoURL)
                    .transition(.opacity)
            }
        }
        .frame(width: screenW, height: imageH)
        .clipped()
    }

    // MARK: - Shelves

    private func shelfView(for shelf: HomeShelf) -> some View {
        HomeShelfView(
            shelf: shelf,
            model: model,
            mergeContinueWatchingAndUpNext: mergeContinueWatchingAndUpNext,
            seerrDiscoverEnabled: seerrDiscoverEnabled,
            streamingServicesData: streamingServicesData,
            seeAll: { seeAllShelf = $0 },
            openSeerrItem: { model.openSeerrShelfItem($0, authManager: authManager, seerrRepo: seerrRepo) }
        ) { item, isLandscape in
            if isLandscape {
                continueWatchingCard(item)
            } else {
                posterCard(item)
            }
        }
    }

    private func continueWatchingCard(_ item: MediaItem) -> some View {
        NavigationLink(value: item) {
            PosterCard(
                title: HomeText.title(item),
                subtitle: HomeText.subtitle(item),
                progress: item.userData?.playedPercentage.map { $0 / 100 },
                imageURL: HomeArtwork.landscapeURL(for: item, in: mediaRepo),
                width: DT.Size.wideCard.width, height: DT.Size.wideCard.height
            )
        }
        .buttonStyle(PressableButtonStyle())
        // No custom preview: — a preview whose size doesn't match the tiny source card
        // confuses UIKit's context-menu interaction proxy about which cell was actually
        // touched in a tightly-packed horizontal shelf, causing taps to land on the
        // neighboring card instead of the one under your finger.
        .contextMenu { longPressMenu(item) }
        .zoomTransitionSource(id: item.id, in: zoomNamespace)
    }

    private func posterCard(_ item: MediaItem) -> some View {
        NavigationLink(value: item) {
            PosterCard(
                title: HomeText.title(item),
                subtitle: HomeText.subtitle(item),
                imageURL: mediaRepo.imageURL(for: item)
            )
        }
        .buttonStyle(PressableButtonStyle())
        .contextMenu { longPressMenu(item) }
        .zoomTransitionSource(id: item.id, in: zoomNamespace)
    }

    /// The poster long-press menu: the usual quick actions, with Play and Play Trailer on top.
    @ViewBuilder
    private func longPressMenu(_ item: MediaItem) -> some View {
        if item.type == .movie || item.type == .episode {
            let ticks = (item.userData?.played == true) ? 0 : (item.userData?.playbackPositionTicks ?? 0)
            Button { model.playbackRequest = PlaybackRequest(item: item, startTicks: ticks) } label: {
                Label(ticks > 0 ? "Resume" : "Play", systemImage: "play.fill")
            }
        }
        Button { trailerLaunchItem = item } label: {
            Label("Play Trailer", systemImage: "play.rectangle")
        }
        HomeQuickLookMenu(item: item)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
