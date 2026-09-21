#if os(tvOS)
import SwiftUI
import JellyfinAPI
import SeerrAPI
import AuthCore
import ImageCache
import Telemetry

struct TVHomeView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(MediaRepository.self) private var mediaRepo
    @Environment(SeerrRepository.self) private var seerrRepo

    @AppStorage("seerrDiscoverEnabled") private var seerrDiscoverEnabled = true

    @FocusState private var focusedItemID: String?
    @State private var heroDetailItem: MediaItem?
    @State private var deepLinkItemID: String? = nil
    @State private var seerrRequestItem: SeerrItem? = nil
    @State private var seerrRequestPending = false
    @State private var playbackRequest: PlaybackRequest?
    @State private var heroVideoBackdropItemID: String?
    @State private var heroVideoBackdropURL: URL?
    @State private var heroVideoBackdropTask: Task<Void, Never>?
    @AppStorage("heroVideoBackdropsEnabled") private var heroVideoBackdropsEnabled = true

    private var focusedItem: MediaItem? {
        guard let id = focusedItemID else { return nil }
        return mediaRepo.continueWatching.first { $0.id == id }
    }

    private var heroDisplayItem: MediaItem? {
        focusedItem ?? mediaRepo.continueWatching.first ?? mediaRepo.recentlyAdded.first
    }

    var body: some View {
        NavigationStack {
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
                .ignoresSafeArea()
            }
            .background(DT.Color.backgroundPrimary)
            .navigationDestination(item: $heroDetailItem) { item in
                TVMediaDetailView(item: item)
            }
            .navigationDestination(for: MediaItem.self) { item in
                TVMediaDetailView(item: item)
            }
        }
        .fullScreenCover(item: $playbackRequest) { request in
            PlayerView(item: request.item, startPositionTicks: request.startTicks) { next in
                playbackRequest = PlaybackRequest(item: next, startTicks: 0)
            }
        }
        .task { await load() }
        .onChange(of: mediaRepo.continueWatching) { _, items in
            if focusedItemID == nil {
                focusedItemID = items.first?.id
            }
        }
        .onChange(of: focusedItemID) { _, _ in loadHeroVideoBackdrop() }
        .onAppear { loadHeroVideoBackdrop() }
        .onReceive(NotificationCenter.default.publisher(for: .arcfinPlayItem)) { note in
            if let id = note.userInfo?["itemID"] as? String {
                UserDefaults.standard.removeObject(forKey: "arcfin.pendingPlayID")
                deepLinkItemID = id
                heroDetailItem = (mediaRepo.continueWatching + mediaRepo.recentlyAdded).first { $0.id == id }
            }
        }
        .alert(
            seerrRequestItem.map { "Request \($0.title)" } ?? "Request",
            isPresented: $seerrRequestPending,
            presenting: seerrRequestItem
        ) { item in
            Button("Request via Seerr") {
                Task { try? await seerrRepo.createRequest(mediaType: item.mediaType, mediaId: item.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { item in
            Text(item.year.map { "(\($0))" } ?? "")
        }
    }

    // MARK: - Load

    private func load() async {
        guard case .authenticated(let cred) = authManager.state else { return }
        await mediaRepo.load(credential: cred, authClient: authManager.authClient)
        mediaRepo.prefetchQuickLookAssets(for: mediaRepo.continueWatching + mediaRepo.recentlyAdded)
        // Preheat full-res hero backdrops + logos into the Nuke decoded cache so
        // backdrop transitions are instant with no load jump.
        let heroURLs = (mediaRepo.continueWatching + mediaRepo.recentlyAdded).flatMap { item -> [URL] in            [mediaRepo.imageURL(for: item, type: .backdrop, fillWidth: 1920),
             mediaRepo.logoURL(for: item)].compactMap { $0 }
        }
        ImageCache.preheat(urls: heroURLs)
        TopShelfBridge.save(
            continueWatching: mediaRepo.continueWatching.prefix(5).map { item in
                TopShelfMediaItem(
                    id: item.id,
                    title: topShelfTitle(item),
                    subtitle: itemSubtitle(item),
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
        let pendingID = deepLinkItemID ?? UserDefaults.standard.string(forKey: "arcfin.pendingPlayID")
        if let id = pendingID {
            UserDefaults.standard.removeObject(forKey: "arcfin.pendingPlayID")
            deepLinkItemID = nil
            heroDetailItem = (mediaRepo.continueWatching + mediaRepo.recentlyAdded).first { $0.id == id }
        }
        if seerrRepo.isConfigured && seerrDiscoverEnabled {
            await seerrRepo.loadDiscover()
            let seerrURLs = (seerrRepo.trending + seerrRepo.popularMovies + seerrRepo.popularTV)
                .flatMap { [$0.backdropURL, $0.posterURL].compactMap { $0 } }
            mediaRepo.prefetch(urls: seerrURLs)
        }
        if focusedItemID == nil {
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

            VStack(alignment: .leading, spacing: 0) {
                Spacer()
                heroInfoBlock
                    .padding(.horizontal, 80)
                    .padding(.bottom, 48)
                cwShelf
                    .padding(.bottom, 60)
            }
        }
        .focusSection()
    }

    @ViewBuilder
    private func backdropLayer() -> some View {
        let url = heroDisplayItem.flatMap {
            mediaRepo.imageURL(for: $0, type: .backdrop, fillWidth: 1920)
        }
        ZStack {
            LazyHeroImage(url: url) { heroFallbackGradient }
                .clipped()

            if let videoURL = heroVideoBackdropURL, heroVideoBackdropItemID == heroDisplayItem?.id {
                HeroVideoBackdropView(url: videoURL)
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
                AsyncImage(url: mediaRepo.logoURL(for: item)) { phase in
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
                .animation(.easeInOut(duration: 0.3), value: focusedItemID)

                heroMetaRow(item)

                if let pct = item.userData?.playedPercentage, pct > 1 {
                    progressBar(pct: pct / 100)
                }

                HStack(spacing: 20) {
                    Button {
                        playbackRequest = PlaybackRequest(item: item, startTicks: item.userData?.playbackPositionTicks ?? 0)
                    } label: {
                        TVHeroButtonLabel(icon: "play.fill", text: "Play", isPrimary: true)
                    }
                    .buttonStyle(TVCardButtonStyle())
                    .focusEffectDisabled()

                    Button { heroDetailItem = item } label: {
                        TVHeroButtonLabel(icon: "info.circle", text: "More Info")
                    }
                    .buttonStyle(TVCardButtonStyle())
                    .focusEffectDisabled()
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: 540, alignment: .leading)
            .id(item.id)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.3), value: focusedItemID)
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
                Text(String(year)).font(.system(size: 22)).foregroundStyle(.white.opacity(0.7))
            }
            if let rating = item.communityRating {
                Text("·").foregroundStyle(.white.opacity(0.3)).font(.system(size: 22))
                HStack(spacing: 5) {
                    Image(systemName: "star.fill").font(.system(size: 16)).foregroundStyle(DT.Color.accent)
                    Text(String(format: "%.1f", rating))
                        .font(.system(size: 22, weight: .bold)).foregroundStyle(DT.Color.accent)
                }
            }
            Text("·").foregroundStyle(.white.opacity(0.3)).font(.system(size: 22))
            Text(item.type == .series ? "Series" : "Movie")
                .font(.system(size: 22)).foregroundStyle(.white.opacity(0.7))
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
    /// navigation — so there's no rotation timer to skip past a playing trailer, and no
    /// slide to auto-advance to once the trailer's 15s preview ends.
    private func loadHeroVideoBackdrop() {
        let log = Telemetry.logger(category: "HeroVideoBackdrop")
        heroVideoBackdropTask?.cancel()
        heroVideoBackdropURL = nil
        heroVideoBackdropItemID = nil
        guard heroVideoBackdropsEnabled, let item = heroDisplayItem,
              case .authenticated(let credential) = authManager.state
        else { return }
        let itemID = item.id
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
            guard !Task.isCancelled, heroDisplayItem?.id == itemID else { return }
            withAnimation(.easeIn(duration: 0.6)) {
                heroVideoBackdropURL = info.playURL
                heroVideoBackdropItemID = itemID
            }
            // Loops indefinitely otherwise — auto-reverts to the still backdrop after a
            // short preview instead, same idea as tvOS's own featured-app hero rotators.
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled, heroDisplayItem?.id == itemID else { return }
            withAnimation(.easeOut(duration: 0.6)) {
                heroVideoBackdropURL = nil
                heroVideoBackdropItemID = nil
            }
        }
    }

    // MARK: - Continue Watching shelf (inside hero)

    @ViewBuilder
    private var cwShelf: some View {
        if !mediaRepo.continueWatching.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("Continue Watching")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(DT.Color.textPrimary)
                    .padding(.horizontal, 80)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(mediaRepo.continueWatching) { item in
                            NavigationLink(value: item) {
                                PosterCard(
                                    title: itemTitle(item),
                                    subtitle: itemSubtitle(item),
                                    progress: item.userData?.playedPercentage.map { $0 / 100 },
                                    imageURL: mediaRepo.tvImageURL(for: item, fillWidth: 640)
                                )
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

    private var belowFoldSection: some View {
        VStack(spacing: 0) {
            if !mediaRepo.recentlyAdded.isEmpty {
                tvShelfRow(title: "Recently Added", badge: "NEW") {
                    ForEach(mediaRepo.recentlyAdded) { item in
                        NavigationLink(value: item) {
                            PosterCard(
                                title: item.name,
                                subtitle: item.productionYear.map { String($0) },
                                imageURL: mediaRepo.tvImageURL(for: item, fillWidth: 640)
                            )
                        }
                        .buttonStyle(TVCardButtonStyle())
                        .focusEffectDisabled()
                        .contextMenu { cwContextMenu(item) }
                    }
                }
            }
            if seerrRepo.isConfigured && seerrDiscoverEnabled {
                if !seerrRepo.trending.isEmpty { seerrShelf(title: "Trending", items: seerrRepo.trending) }
                if !seerrRepo.popularMovies.isEmpty { seerrShelf(title: "Popular Movies", items: seerrRepo.popularMovies) }
                if !seerrRepo.popularTV.isEmpty { seerrShelf(title: "Popular Series", items: seerrRepo.popularTV) }
            }
        }
        .focusSection()
    }

    private func tvShelfRow<Content: View>(
        title: String,
        badge: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(DT.Color.textPrimary)
                if let badge {
                    Text(badge)
                        .font(.system(size: 14, weight: .bold))
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
    }

    private func seerrShelf(title: String, items: [SeerrItem]) -> some View {
        tvShelfRow(title: title) {
            ForEach(items) { item in
                Button {
                    seerrRequestItem = item
                    seerrRequestPending = true
                } label: {
                    PosterCard(
                        title: item.title,
                        subtitle: item.year,
                        imageURL: item.backdropURL ?? item.posterURL
                    )
                }
                .buttonStyle(TVCardButtonStyle())
                .focusEffectDisabled()
            }
        }
    }

    // MARK: - Context menu

    @ViewBuilder
    private func cwContextMenu(_ item: MediaItem) -> some View {
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

    // Top Shelf title includes S/E so users see context without needing a subtitle row
    private func topShelfTitle(_ item: MediaItem) -> String {
        guard item.type == .episode else { return item.name }
        let show = item.seriesName ?? item.name
        guard let sub = itemSubtitle(item) else { return show }
        return "\(show) – \(sub)"
    }
}

#Preview {
    TVHomeView()
        .environment(AuthManager())
        .environment(MediaRepository())
        .environment(SeerrRepository())
}
#endif
