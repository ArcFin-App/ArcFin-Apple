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
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isBehindLock) private var isBehindLock

    @AppStorage("seerrDiscoverEnabled") private var seerrDiscoverEnabled = true
    @AppStorage("mergeContinueWatchingAndUpNext") private var mergeContinueWatchingAndUpNext = false
    @AppStorage(HomeShelfPrefs.orderKey) private var homeShelfOrderString = ""
    @AppStorage(HomeShelfPrefs.activeKey) private var homeShelfActiveString = ""
    @AppStorage(HomeShelfPrefs.shuffleKey) private var shuffleHomeShelves = false
    @AppStorage(StreamingServicePrefs.key) private var streamingServicesData = Data()
    @AppStorage(SeerrRepository.regionOverrideKey) private var seerrRegionOverride = ""
    @State private var model = HomeModel()

    /// Only for putting focus on the first Continue Watching card and letting it go before the
    /// player opens. What's focused comes from `focus`, which the cards report into, so this
    /// body doesn't depend on focus (#655).
    @FocusState private var focusedCard: CardFocus?
    @State private var focus = TVHomeFocus()
    @State private var heroVideoBackdropItemID: String?
    @State private var heroVideoBackdropURL: URL?
    @State private var heroVideoBackdropTask: Task<Void, Never>?
    @AppStorage("heroVideoBackdropsEnabled") private var heroVideoBackdropsEnabled = true
    @AppStorage("heroTrailerSound") private var heroTrailerSound = false
    @AppStorage("topShelfTrailers") private var topShelfTrailers = true
    @State private var isHomeShowing = false
    @State private var homePath = NavigationPath()
    @State private var isHeroScrolledAway = false
    @State private var heroVideoRequestedItemID: String?
    @State private var heroVideoIsPlaying = false
    @State private var heroChromeHidden = false
    @State private var heroChromeTask: Task<Void, Never>?
    @FocusState private var focusedHeroButton: HeroButton?
    @AppStorage("modernHome") private var modernHome = false
    // Modern Home: where each row starts. The focused row and the hero's title are in `focus`.
    @State private var modernRowTops: [String: CGFloat] = [:]
    @State private var modernRowHeights: [String: CGFloat] = [:]
    /// Modern Home while the trailer plays: the focused row sits a little lower, and the hero's
    /// details and every other row fade, until the next press.
    @State private var modernRowsResting = false

    private enum HeroButton { case play, info }

    private struct CardFocus: Hashable {
        let row: String
        let itemID: String
    }

    private static let continueWatchingRow = TVHomeText.continueWatchingRow

    private var heroChromeOpacity: Double { heroChromeHidden ? 0 : 1 }

    private var cwItems: [MediaItem] {
        mergeContinueWatchingAndUpNext ? HomeModel.continueAndNext(in: mediaRepo) : mediaRepo.continueWatching
    }

    /// Focus on the hero's buttons or its Continue Watching row, the only places the hero
    /// hides from.
    private var focusIsOnHero: Bool {
        focusedHeroButton != nil || focus.row == Self.continueWatchingRow
    }

    private var focusedItem: MediaItem? {
        guard let id = focus.itemID else { return nil }
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
            && !PlayerActivity.shared.isPlayerOpen && !isBehindLock
    }

    private var heroDisplayItem: MediaItem? {
        if modernHome {
            switch focus.modernHero {
            case .media(let item): return item
            case .seerr: return nil
            case nil: return cwItems.first ?? mediaRepo.featuredItems.first ?? mediaRepo.recentlyAdded.first
            }
        }
        return focusedItem ?? mediaRepo.continueWatching.first ?? mediaRepo.featuredItems.first ?? mediaRepo.recentlyAdded.first
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
                if item.type == .boxSet {
                    CollectionDetailView(collection: item)
                } else {
                    MediaDetailView(item: item)
                }
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
            if HomeShelf.hasLiveTV(in: mediaRepo) {
                await model.liveTV.load(.liveFavoriteChannels, authManager: authManager)
            }
            model.saveTopShelf(mediaRepo: mediaRepo, title: topShelfTitle, subtitle: TVHomeText.subtitle)
            await TopShelfArtwork.refresh(trailer: topShelfTrailer)
        }
        // The hero already shows the first Continue Watching item until something's focused.
        // Assigning focus to it here pulled the page down to that row once Home loaded.
        .onChange(of: mediaRepo.continueWatching) { _, _ in
            if focusedCard == nil { reloadHeroVideoIfItemChanged() }
        }
        .onChange(of: focus.moves) { _, _ in
            showHeroChrome()
            reloadHeroVideoIfItemChanged()
        }
        .onChange(of: focusedHeroButton) { _, _ in
            showHeroChrome()
        }
        .onChange(of: heroVideoAllowed) { _, _ in loadHeroVideoBackdrop() }
        .onChange(of: focus.modernHero?.id) { _, _ in
            if modernHome { reloadHeroVideoIfItemChanged() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .arcfinPlayItem)) { note in
            if let id = note.userInfo?["itemID"] as? String {
                UserDefaults.standard.removeObject(forKey: "arcfin.pendingPlayID")
                model.openDeepLinkItem(id: id, authManager: authManager, mediaRepo: mediaRepo)
            }
        }
        // Kept under the lock, a SharePlay title waits in the buffer until it opens.
        .onReceive(NotificationCenter.default.publisher(for: WatchRoute.notification)) { _ in
            if !isBehindLock { model.playPendingWatch(authManager: authManager) }
        }
        .onChange(of: isBehindLock) { _, behind in
            if !behind { model.playPendingWatch(authManager: authManager) }
        }
        .task(id: "\(StreamingServicePrefs.decode(streamingServicesData).map(\.id))-\(seerrRepo.hasCatalog)-\(seerrRegionOverride)") {
            await model.loadServiceRows(seerrRepo: seerrRepo)
        }
        .task(id: HomeShelfLoader.recentlyAvailable(seerrRepo.requests).map(\.id)) {
            await model.loadNowAvailable(HomeShelfLoader.recentlyAvailable(seerrRepo.requests), authManager: authManager)
        }
        .onDisappear { if shuffleHomeShelves { model.reshuffleShelves() } }
        // Apple TV has no pull to refresh: Home catches up when the app comes back to the
        // front (at most once a minute, as MediaRepository's load allows).
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { _ = await model.loadShelves(force: false, shelves: orderedShelves, authManager: authManager, mediaRepo: mediaRepo) }
        }
    }

    // MARK: - Load

    private func load() async {
        guard await model.loadShelves(force: false, shelves: orderedShelves, authManager: authManager, mediaRepo: mediaRepo) else { return }
        // The first hero backdrops + logos go into the decoded cache so the opening
        // transitions are instant; the rest only to disk, two at a time. Decoding all of them
        // (about 8 MB each at 1920 px) at once crowded out the posters on screen.
        let heroURLs = (mediaRepo.continueWatching + mediaRepo.recentlyAdded).flatMap { item -> [URL] in
            [mediaRepo.imageURL(for: item, type: .backdrop, fillWidth: 1920),
             heroLogoURL(item)].compactMap { $0 }
        }
        ImageCache.preheat(urls: Array(heroURLs.prefix(8)))
        ImageCache.prefetch(urls: Array(heroURLs.dropFirst(8)))
        model.openPendingDeepLink(authManager: authManager, mediaRepo: mediaRepo)
        model.playPendingWatch(authManager: authManager)
        await model.loadDiscover(enabled: seerrDiscoverEnabled, mediaRepo: mediaRepo, seerrRepo: seerrRepo)
        // Modern Home starts on its first row by itself; the same title can also be in a row
        // further down, where this could put focus instead.
        if focusedCard == nil, !modernHome, let first = mediaRepo.continueWatching.first {
            focusedCard = CardFocus(row: Self.continueWatchingRow, itemID: first.id)
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
                CachedAsyncImage(url: heroLogoURL(item)) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFit()
                            .frame(maxWidth: 300, maxHeight: 90)
                            .shadow(color: .black.opacity(0.7), radius: 12)
                    } else {
                        Text(item.type == .episode ? (item.seriesName ?? item.name) : item.name)
                            .font(.system(size: 36, weight: .heavy))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .shadow(color: .black.opacity(0.9), radius: 10)
                    }
                }
                .id(item.id)
                .transition(.opacity)
                .animation(DT.Animation.motion(.easeInOut(duration: 0.3)), value: focus.itemID)
                .opacity(heroChromeOpacity)

                Group {
                    if item.type == .episode {
                        Text(TVHomeText.title(item))
                            .font(.system(size: 25, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
                    } else {
                        heroMetaRow(item)
                    }
                }
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
                        focusedCard = nil
                        if item.type == .boxSet {
                            model.detailItem = item
                        } else if item.type == .series {
                            Task { model.playbackRequest = await HomeModel.seriesPlayback(item, authManager: authManager) }
                        } else {
                            model.playbackRequest = PlaybackRequest(item: item, startTicks: item.userData?.playbackPositionTicks ?? 0)
                        }
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
            .animation(DT.Animation.motion(.easeInOut(duration: 0.3)), value: focus.itemID)
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
                    Text(rating.ratingText)
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
                                    title: TVHomeText.title(item),
                                    subtitle: TVHomeText.subtitle(item),
                                    progress: item.userData?.playedPercentage.map { $0 / 100 },
                                    imageURL: HomeArtwork.tvURL(for: item, in: mediaRepo)
                                )
                                .opacity(heroChromeOpacity)
                                .background {
                                    CardFocusProbe { [focus] in
                                        focus.cardFocused(row: Self.continueWatchingRow, item: .media(item))
                                    }
                                }
                            }
                            .buttonStyle(TVCardButtonStyle())
                            .focusEffectDisabled()
                            .focused($focusedCard, equals: CardFocus(row: Self.continueWatchingRow, itemID: item.id))
                            .contextMenu {
                                TVHomeItemMenu(item: item) { request in
                                    focusedCard = nil
                                    model.playbackRequest = request
                                }
                            }
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
        TVHomeShelves(shelves: orderedShelves, modernHome: false, model: model, focus: focus)
            .equatable()
            .focusSection()
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
            let focusedRowTop = focus.modernRow.flatMap { modernRowTops[$0] } ?? 0
            // Resting drops the focused row towards the bottom edge: half as far again as keeping
            // the next row's cards on screen would allow, but never with the focused row's own
            // cards (its height includes 40 pt of bottom padding) below the edge. The next row
            // can end up off screen, so the first press only brings the rows back.
            let focusedRowHeight = modernRowHeights[focus.modernRow ?? Self.continueWatchingRow] ?? 0
            let rowOnScreen = sh - 30 - rowsTop - (focusedRowHeight - 40)
            let nextRowOnScreen = sh - 10 - rowsTop - focusedRowHeight - 60
            let restingDrop = max(0, min(rowOnScreen, nextRowOnScreen * 1.5))
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
        TVHomeShelves(shelves: orderedShelves, modernHome: true, model: model, focus: focus)
            .equatable()
            .focusSection()
        // Tops come from adding up row heights in order. Measuring positions picked up the
        // offset they were used for, so the rows chased their own position: the bounce.
        .onPreferenceChange(ModernRowHeights.self) { rows in
            var top: CGFloat = 0
            var tops: [String: CGFloat] = [:]
            var heights: [String: CGFloat] = [:]
            for row in rows {
                tops[row.id] = top
                heights[row.id] = row.height
                top += row.height
            }
            modernRowTops = tops
            modernRowHeights = heights
        }
    }

    @ViewBuilder
    private var modernBackdrop: some View {
        if case .seerr(let item) = focus.modernHero {
            LazyHeroImage(url: item.backdropURL) { heroFallbackGradient }
        } else {
            backdropLayer()
        }
    }

    @ViewBuilder
    private var modernHeroInfo: some View {
        Group {
            if case .seerr(let item) = focus.modernHero {
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
                    CachedAsyncImage(url: heroLogoURL(item)) { phase in
                        if case .success(let img) = phase {
                            img.resizable().scaledToFit()
                                .frame(maxWidth: 300, maxHeight: 90)
                                .shadow(color: .black.opacity(0.7), radius: 12)
                        } else {
                            Text(item.type == .episode ? (item.seriesName ?? item.name) : item.name)
                                .font(.system(size: 36, weight: .heavy))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                                .shadow(color: .black.opacity(0.9), radius: 10)
                        }
                    }
                    if item.type == .episode {
                        Text(TVHomeText.title(item))
                            .font(.system(size: 25, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .lineLimit(1)
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
        .id(focus.modernHero?.id)
        .transition(.opacity)
        .animation(DT.Animation.motion(.easeInOut(duration: 0.3)), value: focus.modernHero?.id)
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

    // MARK: - Helpers

    /// Episodes have no logo of their own; their show's stands in.
    private func heroLogoURL(_ item: MediaItem) -> URL? {
        mediaRepo.logoURL(itemID: item.type == .episode ? (item.seriesId ?? item.id) : item.id)
    }

    // Changes when the shelf's items or their progress do, so it follows what was just watched.
    private var topShelfSignature: [String] {
        let items = (mediaRepo.continueWatching.prefix(5) + mediaRepo.nextUp.prefix(3) + mediaRepo.recentlyAdded.prefix(3))
            .map { "\($0.id)-\(Int($0.userData?.playedPercentage ?? 0))" }
        return items.isEmpty ? [] : items + ["trailers-\(topShelfTrailers)"]
    }

    private var topShelfTrailer: ((String) async -> URL?)? {
        guard topShelfTrailers, case .authenticated(let credential) = authManager.state else { return nil }
        let authHeader = authManager.authClient.authHeader(token: credential.accessToken)
        return { await HomeModel.trailerURL(itemID: $0, credential: credential, authHeader: authHeader) }
    }

    // Top Shelf title includes S/E so users see context without needing a subtitle row
    private func topShelfTitle(_ item: MediaItem) -> String {
        guard item.type == .episode else { return item.name }
        let show = item.seriesName ?? item.name
        guard let code = HomeText.episodeLabel(item) else { return show }
        return "\(show) · \(code)"
    }
}

#Preview {
    HomeView()
        .environment(AuthManager())
        .environment(MediaRepository())
        .environment(SeerrRepository())
}
