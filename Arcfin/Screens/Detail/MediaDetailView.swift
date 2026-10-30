// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI
#if !os(tvOS)
import AppIntents
#endif
import SeerrAPI
import AuthCore
#if !os(tvOS)
import SwiftData
import Persistence
#endif

struct MediaDetailView: View {
    let item: MediaItem
    #if !os(tvOS)
    /// Passed down from whichever screen pushed this view (Home/Library/PersonDetail each
    /// own their own @Namespace) so the Similar/Recommended rows below can zoom into a
    /// further MediaDetailView the same way the original poster tap did. nil when reached
    /// from a source that doesn't do the zoom transition (e.g. the Home hero banner).
    var zoomNamespace: Namespace.ID? = nil
    #endif

    @Environment(MediaRepository.self) private var mediaRepo
    @Environment(SeerrRepository.self) private var seerrRepo
    @Environment(AuthManager.self) private var authManager
    @Environment(DownloadManager.self) private var downloadManager
    #if !os(tvOS)
    @Environment(\.modelContext) private var modelContext
    #endif
    #if os(macOS)
    @Environment(PlaybackPresenter.self) private var playbackPresenter
    #endif

    @State private var detail: MediaItemDetail?
    @State private var awards: [WikidataAward] = []
    @State private var isFavorite = false
    @State private var likes: Bool?
    @State private var showSubtitleSearch = false
    /// Upcoming episodes of this show kept downloaded automatically; 0 when off.
    @State private var keptEpisodeCount = 0
    @State private var heroTint: Color?
    @State private var similarItems: [MediaItem] = []
    @State private var seerrRelatedItems: [SeerrItem] = []
    /// Jellyfin-native fallback for the "Recommended" row when Seerr isn't configured —
    /// Movies/Recommendations is server-wide, not per-item, so this is filtered down to
    /// whichever returned category (if any) names this movie as its baseline.
    @State private var jellyfinRecommended: MovieRecommendationCategory?
    @State private var seriesItem: MediaItem?
    /// Collections and playlists this title (or an episode's show) is in.
    @State private var containingCollections: [MediaItem] = []
    @State private var containingPlaylists: [MediaItem] = []
    @State private var openedCollection: MediaItem?
    @State private var openedPlaylist: MediaItem?
    /// The episode a series-level Play/Resume button actually starts — a series itself
    /// isn't playable, so this is what getNextEpisode() resolves to.
    @State private var nextEpisode: MediaItem?
    @State private var seasons: [MediaItem] = []
    @State private var selectedSeason: MediaItem?
    @State private var episodes: [MediaItem] = []
    @State private var selectedEpisode: MediaItem?
    /// The title the player ended up on after handing over to a suggestion or next episode.
    @State private var lastPlayedItem: MediaItem?
    @State private var selectedPerson: MediaPerson?
    @State private var loadedSeasonId: String?
    @State private var trailers: [MediaItem] = []
    @State private var remoteTrailer: RemoteTrailer?
    @State private var youTubeTrailer: RemoteTrailer?
    @AppStorage("trailersEnabled") private var trailersEnabled = true
    @AppStorage("spoilerProtection") private var spoilerProtection = false
    @AppStorage("youtubeTrailersEnabled") private var youtubeTrailersEnabled = true
    @State private var showTrailerPicker = false
    @State private var isLoading = true
    @State private var requestingSeerrItem: SeerrItem?
    @State private var openedSeerrItem: SeerrItem?
    @State private var playbackRequest: PlaybackRequest?
    #if !os(tvOS)
    @State private var seasonDownloadPreview: DownloadManager.DownloadPreview?
    @State private var isLoadingSeasonPreview = false
    /// Set when the target is already downloaded — offers a choice instead of always
    /// streaming, since previously Play/Resume ignored a local copy entirely.
    @State private var pendingPlaybackChoice: PlaybackChoice?
    @State private var offlinePlaybackTarget: DownloadedItem?
    @State private var offlineStartOverride: Int64?
    /// Surfaces a season download failure that would otherwise only show up as a raw
    /// NSURLError buried in per-episode state nobody's looking at during a bulk download.
    @State private var seasonDownloadErrorMessage: String?

    private struct PlaybackChoice: Identifiable {
        let id = UUID()
        let item: MediaItem
        let startTicks: Int64
        let isExplicitStartOver: Bool
    }
    #endif

    struct PlaybackRequest: Identifiable, Equatable {
        // One constant identity, so handing over to the next title updates the open player
        // cover in place instead of dismissing and re-presenting it (which dropped the
        // rotation and flashed the detail screen in between).
        var id: String { "player" }
        let item: MediaItem
        let startTicks: Int64
    }

    private let client = JellyfinMediaClient()

    private var credential: ServerCredential? { authManager.state.credential }

    private var shelfZoomNamespace: Namespace.ID? {
        #if os(tvOS)
        nil
        #else
        zoomNamespace
        #endif
    }

    /// Jellyfin web client's details page for this item — the same link the web UI's own
    /// "copy link" produces, so anyone with access to the server can open it.
    private var shareURL: URL? {
        guard let base = credential?.baseURL,
              var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)
        else { return nil }
        let basePath = comps.path.hasSuffix("/") ? String(comps.path.dropLast()) : comps.path
        comps.path = basePath + "/web/"
        comps.fragment = "/details?id=\(item.id)"
        return comps.url
    }

    private var authHeader: String? {
        credential.map { authManager.authClient.authHeader(token: $0.accessToken) }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                MediaDetailHero(item: item)
                MediaDetailTitleBlock(item: item, detail: detail, awards: awards)
                if isLoading { loadingContent }
                else { detailContent }
                Spacer().frame(height: DT.Size.tabBarHeight + 24)
            }
            // The page can be laid out while the player still holds the screen in landscape;
            // pinned to the visible width, it re-fits when the device turns back to portrait
            // instead of keeping the landscape width and running past both edges.
            .containerRelativeFrame(.horizontal)
#if os(tvOS)
            .focusSection()
#endif
        }
        .background {
            ZStack {
                DT.Color.backgroundPrimary
                if let heroTint {
                    LinearGradient(colors: [heroTint.opacity(0.4), .clear], startPoint: .top, endPoint: .bottom)
                }
            }
            .ignoresSafeArea()
            .animation(DT.Animation.motion(.easeInOut(duration: 0.4)), value: heroTint)
        }
        .ignoresSafeArea(edges: .top)
        .task(id: item.id) {
            if let seriesId = seasonSeriesId {
                keptEpisodeCount = DownloadManager.keptShows[seriesId]?.episodeCount ?? 0
            }
            guard let url = mediaRepo.imageURL(for: item, type: .backdrop, fillWidth: 120) else { return }
            heroTint = await AverageColor.load(from: url)
        }
        #if os(iOS)
        // Pull down to pick up changes made elsewhere (another device, the web UI): watched
        // state, resume position, the next episode and the season's progress.
        .refreshable { await refreshAfterPlayback(waitForReport: false) }
        #endif
        #if !os(tvOS)
        // Handoff to another device, Spotlight, and on-screen awareness: Siri and Apple
        // Intelligence can resolve "this movie" to the MediaEntity for what's on screen.
        .userActivity(ArcfinActivity.viewTitle) { activity in
            activity.title = item.name
            activity.isEligibleForHandoff = true
            activity.isEligibleForSearch = true
            activity.userInfo = ["itemID": item.id]
            activity.webpageURL = shareURL
            activity.appEntityIdentifier = EntityIdentifier(for: MediaEntity.self, identifier: item.id)
        }
        #endif
        .navigationTitle("")
        #if os(iOS)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { ratingMenu }
            ToolbarItem(placement: .topBarTrailing) {
                Button { toggleFavorite() } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .foregroundStyle(isFavorite ? DT.Color.palette("EF4444") : DT.Color.textPrimary)
                }
                .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
            }
            if item.type == .movie || item.type == .episode {
                ToolbarItem(placement: .topBarTrailing) {
                    DownloadButton(item: item)
                }
            }
            if let shareURL {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: shareURL, subject: Text(item.name), message: Text(item.name)) {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(DT.Color.textPrimary)
                    }
                    .accessibilityLabel("Share")
                }
            }
            ToolbarItem(placement: .topBarTrailing) { moreMenu }
        }
        .sheet(isPresented: $showSubtitleSearch) {
            NavigationStack {
                SubtitleSearchView(itemId: item.id)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Done") { showSubtitleSearch = false } }
                    }
            }
            .presentationDetents([.medium, .large])
        }
        #elseif os(macOS)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await refreshAfterPlayback(waitForReport: false) } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Refresh")
                .help("Refresh")
            }
            ToolbarItem(placement: .primaryAction) { ratingMenu.help("Rate") }
            ToolbarItem(placement: .primaryAction) {
                Button { toggleFavorite() } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .foregroundStyle(isFavorite ? DT.Color.palette("EF4444") : DT.Color.textPrimary)
                }
                .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
                .help(isFavorite ? "Remove from Favorites" : "Add to Favorites")
            }
            if item.type == .movie || item.type == .episode {
                ToolbarItem(placement: .primaryAction) {
                    DownloadButton(item: item).help("Download")
                }
            }
            if let shareURL {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: shareURL, subject: Text(item.name), message: Text(item.name)) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share")
                    .help("Share")
                }
            }
            ToolbarItem(placement: .primaryAction) { moreMenu.help("More") }
        }
        .sheet(isPresented: $showSubtitleSearch) {
            NavigationStack {
                SubtitleSearchView(itemId: item.id)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Done") { showSubtitleSearch = false } }
                    }
            }
            .frame(minWidth: 480, minHeight: 520)
        }
        #endif
        .navigationDestination(item: $openedCollection) { collection in
#if os(tvOS)
            TVCollectionDetailView(item: collection)
#else
            CollectionDetailView(collection: collection)
#endif
        }
        .navigationDestination(item: $openedPlaylist) { LibraryDetailView(playlistItem: $0) }
        .navigationDestination(item: $selectedEpisode) { ep in
#if os(tvOS)
            MediaDetailView(item: ep)
#else
            MediaDetailView(item: ep, zoomNamespace: shelfZoomNamespace)
#endif
        }
        .navigationDestination(item: $selectedPerson) { person in
            PersonDetailView(person: person)
        }
        .navigationDestination(item: $openedSeerrItem) { item in
#if os(tvOS)
            TVSeerrItemDetailView(item: item)
#else
            SeerrItemDetailView(item: item)
#endif
        }
        .sheet(item: $requestingSeerrItem) { item in
            SeerrRequestConfirmSheet(item: item, requestingItem: $requestingSeerrItem)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        #if !os(tvOS)
        .sheet(item: $seasonDownloadPreview) { preview in
            DownloadConfirmSheet(item: selectedSeason ?? item, preview: preview) { bitrateCap in
                downloadSeason(bitrateCap: bitrateCap)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            "This is downloaded — play the offline copy or stream from the server?",
            isPresented: Binding(get: { pendingPlaybackChoice != nil }, set: { if !$0 { pendingPlaybackChoice = nil } }),
            titleVisibility: .visible
        ) {
            Button("Play Downloaded") {
                if let choice = pendingPlaybackChoice, let downloaded = fetchDownloadedItem(itemId: choice.item.id) {
                    offlineStartOverride = choice.isExplicitStartOver ? 0 : nil
                    offlinePlaybackTarget = downloaded
                }
                pendingPlaybackChoice = nil
            }
            Button("Stream Online") {
                if let choice = pendingPlaybackChoice {
                    playbackRequest = PlaybackRequest(item: choice.item, startTicks: choice.startTicks)
                }
                pendingPlaybackChoice = nil
            }
            Button("Cancel", role: .cancel) { pendingPlaybackChoice = nil }
        }
        #if os(iOS)
        .fullScreenCover(item: $offlinePlaybackTarget, onDismiss: { Task { await refreshAfterPlayback() } }) { downloaded in
            OfflinePlayerView(downloadedItem: downloaded, startPositionOverride: offlineStartOverride)
        }
        #else
        // fullScreenCover is unavailable on macOS; the offline player sizes itself in a sheet,
        // as on the downloaded titles' own pages.
        .sheet(item: $offlinePlaybackTarget, onDismiss: { Task { await refreshAfterPlayback() } }) { downloaded in
            OfflinePlayerView(downloadedItem: downloaded, startPositionOverride: offlineStartOverride)
        }
        #endif
        .alert("Download Failed", isPresented: Binding(
            get: { seasonDownloadErrorMessage != nil }, set: { if !$0 { seasonDownloadErrorMessage = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(seasonDownloadErrorMessage ?? "")
        }
        .onChange(of: downloadManager.errors) { _, newErrors in
            guard seasonDownloadErrorMessage == nil else { return }
            for episode in episodes {
                if let raw = newErrors[episode.id] {
                    seasonDownloadErrorMessage = friendlyDownloadError(raw)
                    downloadManager.errors[episode.id] = nil
                    break
                }
            }
        }
        #endif
        // The fixed wait after the player closes can beat the stop report to the server.
        .onReceive(NotificationCenter.default.publisher(for: .arcfinPlaybackReported)) { _ in
            Task { await refreshAfterPlayback(waitForReport: false) }
        }
#if os(iOS)
        .fullScreenCover(item: $playbackRequest, onDismiss: playerDismissed) { request in
            PlayerView(item: request.item, startPositionTicks: request.startTicks) { next in
                PlayerView.keepOrientationOnNextDisappear = true
                lastPlayedItem = next
                playbackRequest = PlaybackRequest(item: next, startTicks: 0)
            }
            .id(request.item.id)
        }
        .fullScreenCover(item: $youTubeTrailer) { trailer in
            if let videoID = trailer.youTubeVideoID {
                YouTubeTrailerPlayerView(videoID: videoID, title: trailer.name ?? item.name)
            }
        }
#elseif os(macOS)
        // A .sheet on macOS can't fill/fullscreen a window — PlayerView is rendered as a
        // full-window overlay by ContentView instead, driven by the shared PlaybackPresenter.
        .onChange(of: playbackRequest) { _, request in
            guard let request else { return }
            playbackPresenter.present(request.item, startTicks: request.startTicks) { lastPlayedItem = $0 }
            playbackRequest = nil
        }
        .onChange(of: playbackPresenter.request == nil) { _, closed in
            if closed { playerDismissed() }
        }
        .sheet(item: $youTubeTrailer) { trailer in
            if let videoID = trailer.youTubeVideoID {
                YouTubeTrailerPlayerView(videoID: videoID, title: trailer.name ?? item.name)
                    .frame(minWidth: 800, minHeight: 450)
            }
        }
#endif
        .task { await load() }
        // Apart from load(): the first lookup reads every collection and playlist.
        .task(id: item.id) { await loadContainingSets() }
        .task(id: item.tmdbId) {
            guard let tmdbId = item.tmdbId else { return }
            awards = await WikidataAwardsClient.shared.awards(
                tmdbId: tmdbId, mediaType: item.type == .series ? .tv : .movie
            )
        }
        .onChange(of: selectedSeason) { _, season in
            guard let season, season.id != loadedSeasonId,
                  let seriesId = seasonSeriesId,
                  let cred = credential, let header = authHeader else { return }
            Task {
                loadedSeasonId = season.id
                episodes = (try? await client.getEpisodes(credential: cred, authHeader: header,
                                                          seriesId: seriesId, seasonId: season.id)) ?? []
            }
        }
    }

    // MARK: - Load

    #if !os(tvOS)
    /// Every episode in the current season already downloaded — the "Download Season"
    /// button should be inert then, not just silently no-op every episode it loops over.
    private var isSeasonFullyDownloaded: Bool {
        !episodes.isEmpty && seasonEpisodesToDownload.isEmpty
    }

    /// Settings › Downloads › Season Downloads can leave out episodes already watched.
    private var seasonEpisodesToDownload: [MediaItem] {
        let unwatchedOnly = UserDefaults.standard.bool(forKey: "seasonDownloadUnwatchedOnly")
        return episodes.filter { !$0.isVirtual && !downloadManager.isDownloaded($0.id) && !(unwatchedOnly && $0.userData?.played == true) }
    }

    /// Fetches one representative preview (from the first not-yet-downloaded episode) to
    /// show real quality/size info in the confirm sheet, instead of the bare "Download all
    /// N episodes?" text alert that gave no size/quality info at all.
    private func loadSeasonPreview() {
        guard case .authenticated(let credential) = authManager.state else { return }
        let pending = seasonEpisodesToDownload
        guard let firstPending = pending.first else { return }
        let authHeader = authManager.authClient.authHeader(token: credential.accessToken)
        isLoadingSeasonPreview = true
        Task {
            let single = await downloadManager.preview(for: firstPending, credential: credential, authHeader: authHeader)
            isLoadingSeasonPreview = false
            let count = Int64(pending.count)
            // Scaled from one representative episode to the whole season's pending count —
            // an honest total rather than one episode's numbers presented for the whole
            // season, without needing a HEAD/playback-info round trip per episode.
            seasonDownloadPreview = DownloadManager.DownloadPreview(
                subtitleLanguages: single?.subtitleLanguages ?? [],
                audioLanguages: single?.audioLanguages ?? [],
                estimatedSizeBytes: single?.estimatedSizeBytes.map { $0 * count },
                estimatedSizeIsApproximate: true,
                willRemux: single?.willRemux ?? false,
                sourceBitrate: single?.sourceBitrate,
                runtimeTicks: single?.runtimeTicks.map { $0 * count },
                container: single?.container,
                videoCodec: single?.videoCodec,
                videoWidth: single?.videoWidth,
                videoHeight: single?.videoHeight,
                videoRange: single?.videoRange
            )
        }
    }

    private func downloadSeason(bitrateCap: Int?) {
        guard case .authenticated(let credential) = authManager.state else { return }
        let authHeader = authManager.authClient.authHeader(token: credential.accessToken)
        for episode in seasonEpisodesToDownload {
            Task { await downloadManager.startDownload(item: episode, credential: credential, authHeader: authHeader, bitrateCap: bitrateCap) }
        }
    }

    // MARK: - Play downloaded vs. stream

    private func requestPlayback(startTicks: Int64, isExplicitStartOver: Bool = false) {
        let target = playTargetItem
        if downloadManager.isDownloaded(target.id) {
            pendingPlaybackChoice = PlaybackChoice(item: target, startTicks: startTicks, isExplicitStartOver: isExplicitStartOver)
        } else {
            playbackRequest = PlaybackRequest(item: target, startTicks: startTicks)
        }
    }

    private func fetchDownloadedItem(itemId: String) -> DownloadedItem? {
        let descriptor = FetchDescriptor<DownloadedItem>(predicate: #Predicate { $0.itemId == itemId })
        return try? modelContext.fetch(descriptor).first
    }

    /// The raw error DownloadManager surfaces per-item is a real but unhelpful string
    /// (e.g. "Download failed: The operation couldn't be completed. (NSURLErrorDomain
    /// error -1017.)") — translated into something a user can actually act on.
    private func friendlyDownloadError(_ raw: String) -> String {
        if raw.contains("-1017") {
            return "One of the episodes couldn't be downloaded because of a network hiccup mid-transfer. Try downloading it again — if it keeps happening, check your connection and available storage."
        }
        if raw.localizedCaseInsensitiveContains("permission") {
            return "One of the episodes couldn't be downloaded — this account doesn't have permission to download media. Ask your Jellyfin admin to enable it."
        }
        return "One of the episodes in this season failed to download: \(raw)"
    }
    #endif

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        guard let cred = credential, let header = authHeader else { return }

        async let detailTask = client.getItemDetail(credential: cred, authHeader: header, itemId: item.id)
        trailers = []
        
        // Without a connection, a downloaded title still has its full page from when it was saved.
        let fetchedDetail = (try? await detailTask) ?? downloadManager.savedDetail(itemId: item.id)
        detail = fetchedDetail
        isFavorite = fetchedDetail?.item.userData?.isFavorite ?? item.userData?.isFavorite ?? false
        likes = fetchedDetail?.item.userData?.likes ?? item.userData?.likes

        if let fetchedDetail, let mediaType = seerrMediaType(for: fetchedDetail.item),
           let tmdbId = fetchedDetail.item.tmdbId {
            seerrRelatedItems = await seerrRepo.relatedMedia(mediaType: mediaType, mediaId: tmdbId)
        }
        if seerrRelatedItems.isEmpty {
            similarItems = (try? await client.getSimilarItems(credential: cred, authHeader: header, itemId: item.id)) ?? []
        } else {
            similarItems = []
        }

        jellyfinRecommended = nil
        if seerrRelatedItems.isEmpty, item.type == .movie {
            let categories = (try? await client.getMovieRecommendations(credential: cred, authHeader: header)) ?? []
            let shown = Set(similarItems.map(\.id))
            // "Because you watched <this title>" is built from the same similarity data as
            // More Like This above, so only what that row doesn't already show is kept.
            if let match = categories.first(where: {
                $0.baselineItemName?.caseInsensitiveCompare(item.name) == .orderedSame
            }) {
                let fresh = match.items.filter { !shown.contains($0.id) && $0.id != item.id }
                if fresh.count >= 3 {
                    jellyfinRecommended = MovieRecommendationCategory(
                        id: match.id, recommendationType: match.recommendationType,
                        baselineItemName: match.baselineItemName, items: fresh)
                }
            }
        }

        remoteTrailer = nil
        if trailersEnabled {
            Task {
                let fetchedTrailers = (try? await client.getTrailers(
                    credential: cred,
                    authHeader: header,
                    itemId: item.id,
                    limit: 6
                )) ?? []
                await MainActor.run {
                    trailers = fetchedTrailers
                    // Only fall back to a remote (YouTube) trailer once we know there's
                    // genuinely no local one — a local file always streams better than an
                    // embedded web player.
                    if fetchedTrailers.isEmpty, youtubeTrailersEnabled {
                        remoteTrailer = fetchedDetail?.remoteTrailers.first { $0.youTubeVideoID != nil }
                    }
                }
            }
        }

        if let seriesId = seasonSeriesId {
            seasons = (try? await client.getSeasons(credential: cred, authHeader: header, seriesId: seriesId)) ?? []
            if let first = seasons.first {
                var target = selectedSeasonForCurrentItem(from: seasons) ?? first
                // For a series entry point, ask the server which episode is next
                if item.type == .series,
                   let nextEp = try? await client.getNextEpisode(credential: cred, authHeader: header, seriesId: seriesId) {
                    nextEpisode = nextEp
                    if let seasonNum = nextEp.parentIndexNumber,
                       let matched = seasons.first(where: { $0.indexNumber == seasonNum }) {
                        target = matched
                    }
                }
                selectedSeason = target
                loadedSeasonId = target.id
                episodes = (try? await client.getEpisodes(credential: cred, authHeader: header,
                                                          seriesId: seriesId, seasonId: target.id)) ?? []
            }
        }

        if item.type == .episode, let seriesId = item.seriesId {
            seriesItem = (try? await client.getItemDetail(credential: cred, authHeader: header, itemId: seriesId))?.item
        }
    }

    /// Re-reads the playback position after the player closes, so Play becomes Resume (and the
    /// episode list's progress updates) without leaving and re-entering this screen. A full
    /// `load()` would flash the loading state, so only the progress-bearing data is refetched.
    /// Closing the player lands on whatever it was last playing: a suggestion opens its own
    /// detail screen, while later episodes of this series just refresh this one.
    private func playerDismissed() {
        let last = lastPlayedItem
        lastPlayedItem = nil
        Task { await refreshAfterPlayback() }
        downloadManager.refreshSmartDownloads()
        guard let last, last.id != item.id else { return }
        let sameSeries = last.type == .episode && last.seriesId != nil && last.seriesId == seasonSeriesId
        if !sameSeries { selectedEpisode = last }
    }

    private func refreshAfterPlayback(waitForReport: Bool = true) async {
        guard let cred = credential, let header = authHeader else { return }
        // The player reports its final position as it closes; give that request a moment to land.
        if waitForReport { try? await Task.sleep(for: .milliseconds(700)) }
        if let fresh = try? await client.getItemDetail(credential: cred, authHeader: header, itemId: item.id) {
            detail = fresh
        }
        guard let seriesId = seasonSeriesId else { return }
        if item.type == .series,
           let nextEp = try? await client.getNextEpisode(credential: cred, authHeader: header, seriesId: seriesId) {
            nextEpisode = nextEp
        }
        if let seasonId = loadedSeasonId,
           let fresh = try? await client.getEpisodes(credential: cred, authHeader: header, seriesId: seriesId, seasonId: seasonId) {
            episodes = fresh
        }
    }

    /// When playback started right now would finish, counting from the resume point if there
    /// is one — only meaningful for a single playable item, not a series or season.
    private var endTime: Date? {
        guard item.type == .movie || item.type == .episode,
              let total = detail?.runTimeTicks, total > 0
        else { return nil }
        let watched = isResumable ? (resumeUserData?.playbackPositionTicks ?? 0) : 0
        let remainingSeconds = Double(max(total - watched, 0)) / 10_000_000
        return Date().addingTimeInterval(remainingSeconds)
    }

    // MARK: - Play button

    /// A series itself isn't playable — Play/Resume on a series page actually starts
    /// whichever episode getNextEpisode() resolved to.
    private var playTargetItem: MediaItem {
        item.type == .series ? (nextEpisode ?? item) : (detail?.item ?? item)
    }

    private var resumeUserData: UserData? {
        playTargetItem.userData
    }

    private var isResumable: Bool {
        guard let ud = resumeUserData else { return false }
        return ud.playbackPositionTicks > 0 && !ud.played
    }

    /// "S2E5" for whichever episode Play/Resume is about to start — nil for a movie.
    private var playEpisodeLabel: String? {
        let target = playTargetItem
        guard target.type == .episode else { return nil }
        let s = target.parentIndexNumber.map { "S\($0)" }
        let e = target.indexNumber.map { "E\($0)" }
        return [s, e].compactMap { $0 }.joined().nilIfEmpty
    }

    private var resumeTimeLabel: String? {
        guard let ud = resumeUserData, ud.playbackPositionTicks > 0,
              let runTimeTicks = detail?.runTimeTicks, runTimeTicks > ud.playbackPositionTicks
        else { return nil }
        let remainingMinutes = Int(Double(runTimeTicks - ud.playbackPositionTicks) / 10_000_000 / 60)
        if remainingMinutes >= 60 { return "\(remainingMinutes / 60)h \(remainingMinutes % 60)m left" }
        return "\(remainingMinutes)m left"
    }

    /// Resume only: "19m left • Ends 9:42 PM" on its own line (too long to share the title
    /// line). A fresh Play shows its end time inline on the title line instead. The bullet
    /// is a heavier, larger glyph than a middle dot so it reads as a separator against the
    /// gradient.
    private var playDetailLine: Text? {
        guard isResumable else { return nil }
        let ends = endTime.map { Text("Ends \($0.formatted(date: .omitted, time: .shortened))") }
        let left = resumeTimeLabel.map { Text($0) }
        switch (left, ends) {
        case let (left?, ends?):
            let separator = Text("  •  ").font(.system(.footnote, weight: .heavy))
            return Text("\(left)\(separator)\(ends)")
        case let (left?, nil): return left
        case let (nil, ends?): return ends
        case (nil, nil): return nil
        }
    }

    /// "Airs 30 Oct" for an episode listed before it's out; "Not on Your Server" for one missing.
    static func unavailableText(_ item: MediaItem) -> String {
        if let premiere = item.premiereDate, premiere > Date() {
            return "Airs \(premiere.formatted(.dateTime.day().month(.abbreviated)))"
        }
        return "Not on Your Server"
    }

    @ViewBuilder
    private var playButton: some View {
#if os(tvOS)
        Button {} label: { TVPlayButtonLabel() }
            .buttonStyle(TVCardButtonStyle())
            .focusEffectDisabled()
            .padding(.horizontal, DT.Spacing.pagePad)
            .padding(.bottom, DT.Spacing.md)
#else
        if playTargetItem.isVirtual {
            Label(Self.unavailableText(playTargetItem), systemImage: "calendar")
                .font(.system(.callout, design: .default, weight: .bold))
                .foregroundStyle(DT.Color.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(DT.Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: DT.Radius.lg))
                .padding(.horizontal, DT.Spacing.pagePad)
                .padding(.bottom, DT.Spacing.md)
        } else {
        HStack(spacing: 10) {
            Button {
                requestPlayback(startTicks: isResumable ? (resumeUserData?.playbackPositionTicks ?? 0) : 0)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill").font(.system(.subheadline))
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 5) {
                            Text(isResumable ? "Resume" : "Play")
                                .font(.system(.callout, design: .default, weight: .bold))
                            if let playEpisodeLabel {
                                Text(playEpisodeLabel)
                                    .font(.system(.callout, design: .default, weight: .semibold))
                                    .opacity(0.85)
                            }
                            if !isResumable, let endsAt = endTime {
                                Text("•")
                                    .font(.system(.callout, design: .default, weight: .heavy))
                                    .opacity(0.9)
                                Text("Ends \(endsAt.formatted(date: .omitted, time: .shortened))")
                                    .font(.system(.callout, design: .default, weight: .semibold))
                                    .opacity(0.85)
                            }
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        if let playDetailLine {
                            playDetailLine
                                .font(.system(.caption2, design: .default, weight: .semibold))
                                .opacity(0.85)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                    }
                }
                .foregroundStyle(DT.Color.onAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, playDetailLine == nil ? 14 : 10)
                .background(LinearGradient(
                    colors: [DT.Color.accentDeep, DT.Color.accent],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                .clipShape(RoundedRectangle(cornerRadius: DT.Radius.lg))
                .shadow(color: DT.Color.accent.opacity(0.35), radius: 12)
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityIdentifier("detail.play")

            if isResumable {
                Button {
                    requestPlayback(startTicks: 0, isExplicitStartOver: true)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(DT.Color.textPrimary)
                        .frame(width: 48, height: 48)
                        .background(DT.Color.backgroundSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.lg))
                        .overlay(RoundedRectangle(cornerRadius: DT.Radius.lg).stroke(DT.Color.textPrimary.opacity(0.08), lineWidth: 1))
                }
                .accessibilityLabel("Start over")
                .buttonStyle(.plain)
                .accessibilityLabel("Start Over")
            }
        }
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.bottom, DT.Spacing.md)
        }
#endif
    }

    private var hasPlayableTrailer: Bool {
        guard trailersEnabled else { return false }
        return !trailers.isEmpty || (youtubeTrailersEnabled && remoteTrailer != nil)
    }

    @ViewBuilder
    private var trailerButton: some View {
#if !os(tvOS)
        if hasPlayableTrailer {
            Button {
                if trailers.count > 1 {
                    showTrailerPicker = true
                } else if let single = trailers.first {
                    playbackRequest = PlaybackRequest(item: single, startTicks: 0)
                } else if let remoteTrailer {
                    youTubeTrailer = remoteTrailer
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "film").font(.system(.subheadline))
                    Text("Play Trailer").font(.system(.subheadline, design: .default, weight: .semibold))
                }
                .foregroundStyle(DT.Color.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(DT.Color.backgroundSecondary)
                .clipShape(RoundedRectangle(cornerRadius: DT.Radius.lg))
                .overlay(RoundedRectangle(cornerRadius: DT.Radius.lg).stroke(DT.Color.textPrimary.opacity(0.08), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, DT.Spacing.pagePad)
            .padding(.bottom, DT.Spacing.md)
            .confirmationDialog("Play Trailer", isPresented: $showTrailerPicker, titleVisibility: .visible) {
                ForEach(trailers) { trailer in
                    Button(trailer.name) { playbackRequest = PlaybackRequest(item: trailer, startTicks: 0) }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
#endif
    }

    // MARK: - Loading skeleton

    private var loadingContent: some View {
        DetailOverviewSection(text: "Loading overview text that fills a few lines of placeholder content.")
            .padding(.top, DT.Spacing.md)
            .redacted(reason: .placeholder)
    }

    // MARK: - Detail content

    @ViewBuilder
    private var detailContent: some View {
        playButton
        trailerButton

        if let d = detail, !d.genres.isEmpty {
            DetailGenreChips(genres: d.genres)
        }

        // Overview
        if let overview = detail?.item.overview ?? item.overview, !overview.isEmpty {
            DetailOverviewSection(text: overview)
        }

        // Cast
        // Review scores sit with the description, ahead of the cast.
        TitleInsights(tmdbId: insightsTmdbId, mediaType: seerrMediaType(for: item), part: .ratings)
            .padding(.horizontal, DT.Spacing.pagePad)

        if let d = detail, !d.cast.isEmpty { DetailCastSection(cast: d.cast) { selectedPerson = $0 } }

        // Crew
        if let d = detail, (!d.directors.isEmpty || !d.writers.isEmpty) {
            DetailCrewSection(directors: d.directors, writers: d.writers)
        }

        if let seriesItem, item.type == .episode {
            DetailSeriesLink(series: seriesItem) { selectedEpisode = $0 }
        }

        // Series: seasons + episodes
        if !seasons.isEmpty { seriesSection }

        // Trailers

        // Similar / recommended
        if !seerrRelatedItems.isEmpty {
            DetailSeerrShelf(items: seerrRelatedItems, subtitle: seerrRelatedSubtitle, onSelect: openSeerrRelated)
        } else if !similarItems.isEmpty {
            DetailTitleShelf(title: "More Like This", items: similarItems, zoomNamespace: shelfZoomNamespace) { selectedEpisode = $0 }
        }
        if let jellyfinRecommended, !jellyfinRecommended.items.isEmpty {
            DetailTitleShelf(title: jellyfinRecommended.title, items: jellyfinRecommended.items, zoomNamespace: shelfZoomNamespace) { selectedEpisode = $0 }
        }
        if !containingCollections.isEmpty {
            DetailSetShelf(title: containingCollections.count == 1 ? "Collection" : "Collections", sets: containingCollections) { openedCollection = $0 }
        }
        if !containingPlaylists.isEmpty {
            DetailSetShelf(title: "In Your Playlists", sets: containingPlaylists) { openedPlaylist = $0 }
        }

        // Scores, where else it's streaming, and the details list. An episode's TMDB id is
        // the episode's, which Seerr's title lookups don't take, so episodes show the
        // server's details only.
        TitleInsights(tmdbId: insightsTmdbId, mediaType: seerrMediaType(for: item), detail: detail, part: .details)
            .padding(.horizontal, DT.Spacing.pagePad)
            .padding(.top, DT.Spacing.md)
    }

    // MARK: - Series seasons + episodes

    private var seriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Menu {
                    ForEach(seasons) { season in
                        Button(season.name) { selectedSeason = season }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(selectedSeason?.name ?? "Season")
                            .font(.system(.callout, design: .default, weight: .bold))
                            .foregroundStyle(DT.Color.textPrimary)
                        Image(systemName: "chevron.down")
                            .font(.system(.caption2, weight: .semibold))
                            .foregroundStyle(DT.Color.textSecondary)
                    }
                }
#if os(tvOS)
                .buttonStyle(TVCardButtonStyle())
                .focusEffectDisabled()
                .tvFocusRing(cornerRadius: DT.Radius.pill)
#else
                .buttonStyle(.plain)
                .fixedSize()
#endif

                Menu {
                    Button { markScopeWatched(.season, watched: true) } label: {
                        Label("Mark Season Watched", systemImage: "checkmark.circle")
                    }
                    Button { markScopeWatched(.season, watched: false) } label: {
                        Label("Mark Season Unwatched", systemImage: "circle")
                    }
                    Divider()
                    Button { markScopeWatched(.series, watched: true) } label: {
                        Label("Mark Series Watched", systemImage: "checkmark.circle.fill")
                    }
                    Button { markScopeWatched(.series, watched: false) } label: {
                        Label("Mark Series Unwatched", systemImage: "circle.slash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(DT.Color.textSecondary)
                }
                .accessibilityLabel("Mark watched options")
#if os(tvOS)
                .buttonStyle(TVCardButtonStyle())
                .focusEffectDisabled()
                .tvFocusRing(cornerRadius: DT.Radius.pill)
#else
                .buttonStyle(.plain)
#endif

                Spacer()

                #if !os(tvOS)
                Button {
                    if isLoadingSeasonPreview { return }
                    loadSeasonPreview()
                } label: {
                    HStack(spacing: 5) {
                        if isLoadingSeasonPreview {
                            ProgressView().scaleEffect(0.7).tint(DT.Color.accent)
                        } else {
                            Image(systemName: isSeasonFullyDownloaded ? "checkmark.circle.fill" : "arrow.down.circle")
                        }
                        Text(isSeasonFullyDownloaded ? "Season Downloaded" : "Download Season")
                    }
                    .font(.system(.caption, design: .default, weight: .semibold))
                    // A hardcoded accent color didn't dim when disabled (episodes still
                    // loading, or the whole season already downloaded) — tapping it then
                    // did nothing with zero visual feedback, which read as "no confirm
                    // popup ever shows up". Tapping an already-fully-downloaded season's
                    // button was also what produced the -1017 "Download Failed" error.
                    .foregroundStyle(episodes.isEmpty || isSeasonFullyDownloaded ? DT.Color.accent.opacity(0.35) : DT.Color.accent)
                }
                .buttonStyle(.plain)
                .disabled(episodes.isEmpty || isSeasonFullyDownloaded)
                .shown(ProfileRules.shared.canDownload)
                #else
                Text("Episodes")
                    .font(.system(.footnote, design: .default, weight: .medium))
                    .foregroundStyle(DT.Color.textSecondary)
                #endif
            }
            .padding(.horizontal, DT.Spacing.pagePad)

            VStack(spacing: 8) {
                ForEach(episodes) { ep in
                    EpisodeRow(
                        episode: ep,
                        badge: episodeBadge(ep),
                        spoilerProtection: spoilerProtection,
                        onSelect: { selectedEpisode = ep },
                        onToggleWatched: { markEpisodeWatched(ep, watched: ep.userData?.played != true) }
                    )
                }
            }
            .padding(.horizontal, DT.Spacing.pagePad)
        }
        .padding(.bottom, DT.Spacing.md)
#if os(tvOS)
        .focusSection()
#endif
    }

    /// "NEW" for an unwatched episode that premiered in the last two weeks; "FINALE" for the
    /// last episode of the season being shown.
    private func episodeBadge(_ ep: MediaItem) -> String? {
        if ep.isVirtual { return Self.unavailableText(ep).uppercased() }
        if ep.userData?.played != true, let premiere = ep.premiereDate,
           premiere <= Date(), Date().timeIntervalSince(premiere) < 14 * 86_400 {
            return "NEW"
        }
        if episodes.count > 1, ep.id == episodes.last?.id { return "FINALE" }
        return nil
    }

    private var moreMenu: some View {
        Menu {
            Button { PlaylistStore.shared.addingItem = item } label: {
                Label("Add to Playlist…", systemImage: "text.badge.plus")
            }
            if (item.type == .movie || item.type == .episode) && ProfileRules.shared.canManageSubtitles {
                Button { showSubtitleSearch = true } label: {
                    Label("Search for Subtitles…", systemImage: "captions.bubble")
                }
            }
            if let seriesId = seasonSeriesId, ProfileRules.shared.canDownload {
                Picker(selection: Binding(
                    get: { keptEpisodeCount },
                    set: { count in
                        keptEpisodeCount = count
                        downloadManager.setKeptShow(seriesId: seriesId, name: item.seriesName ?? item.name,
                                                    episodeCount: count == 0 ? nil : count)
                    }
                )) {
                    Text("Off").tag(0)
                    ForEach([1, 2, 3, 5], id: \.self) { count in
                        Text(count == 1 ? "Next Episode" : "Next \(count) Episodes").tag(count)
                    }
                } label: {
                    Label("Keep Downloaded", systemImage: "arrow.down.circle.dotted")
                }
                .pickerStyle(.menu)
            }
        } label: {
            Image(systemName: "ellipsis")
                .foregroundStyle(DT.Color.textPrimary)
        }
        .accessibilityLabel("More")
    }

    private var ratingMenu: some View {
        Menu {
            Button { setRating(true) } label: {
                Label(likes == true ? "Remove Like" : "Like", systemImage: likes == true ? "hand.thumbsup.fill" : "hand.thumbsup")
            }
            Button { setRating(false) } label: {
                Label(likes == false ? "Remove Dislike" : "Dislike", systemImage: likes == false ? "hand.thumbsdown.fill" : "hand.thumbsdown")
            }
        } label: {
            Image(systemName: likes == true ? "hand.thumbsup.fill" : likes == false ? "hand.thumbsdown.fill" : "hand.thumbsup")
                .foregroundStyle(DT.Color.textPrimary)
        }
        .accessibilityLabel("Rate")
        .accessibilityValue(likes == true ? "Liked" : likes == false ? "Disliked" : "Not rated")
    }

    /// Tapping the current rating again clears it.
    private func setRating(_ value: Bool) {
        guard let cred = credential, let header = authHeader else { return }
        let newValue: Bool? = likes == value ? nil : value
        likes = newValue
        HapticManager.impact(.light)
        Task {
            try? await client.setRating(credential: cred, authHeader: header, itemId: item.id, likes: newValue)
        }
    }

    private func toggleFavorite() {
        guard let cred = credential, let header = authHeader else { return }
        let newValue = !isFavorite
        isFavorite = newValue
        HapticManager.impact(.light)
        Task {
            try? await client.markFavorite(credential: cred, authHeader: header, itemId: item.id, favorite: newValue)
        }
    }

    private func markEpisodeWatched(_ ep: MediaItem, watched: Bool) {
        guard let cred = credential, let header = authHeader else { return }
        Task {
            try? await client.markWatched(credential: cred, authHeader: header, itemId: ep.id, watched: watched)
            if let idx = episodes.firstIndex(where: { $0.id == ep.id }) {
                episodes[idx] = withWatchedUserData(episodes[idx], watched: watched)
            }
        }
    }

    private func withWatchedUserData(_ item: MediaItem, watched: Bool) -> MediaItem {
        var updated = item
        let old = updated.userData ?? UserData()
        updated.userData = UserData(
            playbackPositionTicks: watched ? 0 : old.playbackPositionTicks,
            playCount: watched ? old.playCount + 1 : max(0, old.playCount - 1),
            isFavorite: old.isFavorite,
            played: watched,
            playedPercentage: watched ? nil : old.playedPercentage,
            likes: old.likes
        )
        return updated
    }

    // MARK: - Batch watched/unwatched

    private enum WatchScope { case season, series }

    /// Marks a whole season or series watched/unwatched by looping markWatched over the
    /// episode ids already available (current season) or fetched per-season (whole series).
    /// The visible `episodes` array is updated optimistically so watched indicators refresh
    /// without a manual pull-to-refresh, matching markEpisodeWatched's single-item approach.
    private func markScopeWatched(_ scope: WatchScope, watched: Bool) {
        guard let cred = credential, let header = authHeader, let seriesId = seasonSeriesId else { return }
        HapticManager.impact(.light)
        episodes = episodes.map { withWatchedUserData($0, watched: watched) }
        Task {
            switch scope {
            case .season:
                for ep in episodes {
                    try? await client.markWatched(credential: cred, authHeader: header, itemId: ep.id, watched: watched)
                }
            case .series:
                for season in seasons {
                    let seasonEpisodes = (try? await client.getEpisodes(
                        credential: cred, authHeader: header, seriesId: seriesId, seasonId: season.id
                    )) ?? []
                    for ep in seasonEpisodes {
                        try? await client.markWatched(credential: cred, authHeader: header, itemId: ep.id, watched: watched)
                    }
                }
            }
        }
    }

    private func loadContainingSets() async {
        guard let cred = credential, let header = authHeader else { return }
        let found = await ContainingSets.shared.sets(containing: [item.id, item.seriesId].compactMap { $0 },
                                                     credential: cred, authHeader: header)
        containingCollections = found.collections
        containingPlaylists = found.playlists
    }

    private func seerrRelatedSubtitle(_ item: SeerrItem) -> String? {
        let status: String? = mediaRepo.hasInLibrary(item) ? String(localized: "In Library")
            : seerrRepo.isRequested(item) ? String(localized: "Requested") : nil
        return [item.year, status].compactMap { $0 }.joined(separator: " · ").nilIfEmpty
    }

    /// The library's copy when the server has it, the title's Seerr page when it's already
    /// requested, and only otherwise the request sheet.
    private func openSeerrRelated(_ item: SeerrItem) {
        Task {
            if let cred = credential, let header = authHeader,
               let local = try? await client.findItem(
                   credential: cred, authHeader: header, tmdbId: item.id, isSeries: item.mediaType == .tv,
                   title: item.title, year: item.year.flatMap { Int($0.prefix(4)) }) {
                selectedEpisode = local
            } else if seerrRepo.isRequested(item) {
                openedSeerrItem = item
            } else {
                requestingSeerrItem = item
            }
        }
    }

    // MARK: - Helpers

    private var insightsTmdbId: Int? {
        item.type == .episode ? nil : (detail?.item.tmdbId ?? item.tmdbId)
    }

    private func seerrMediaType(for item: MediaItem) -> RequestMediaType? {
        switch item.type {
        case .movie: .movie
        case .series, .season, .episode: .tv
        default: nil
        }
    }

    private var seasonSeriesId: String? {
        switch item.type {
        case .series: item.id
        case .season, .episode: item.seriesId
        default: nil
        }
    }

    private func selectedSeasonForCurrentItem(from seasons: [MediaItem]) -> MediaItem? {
        if item.type == .episode, let seasonNumber = item.parentIndexNumber {
            return seasons.first(where: { $0.indexNumber == seasonNumber })
        }
        if item.type == .season {
            return seasons.first(where: { $0.id == item.id }) ?? seasons.first
        }
        // .series: in-progress season first, then next after last fully-watched, then first
        if let inProgress = seasons.first(where: {
            ($0.userData?.playedPercentage ?? 0) > 0 && $0.userData?.played != true
        }) {
            return inProgress
        }
        if let lastPlayedIdx = seasons.lastIndex(where: { $0.userData?.played == true }),
           lastPlayedIdx + 1 < seasons.count {
            return seasons[lastPlayedIdx + 1]
        }
        return seasons.first
    }
}

// MARK: - Cast card

struct CastPersonCard<Placeholder: View>: View {
    let imageURL: URL?
    let name: String
    let role: String?
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var hovered = false

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if let imageURL {
                    RetryingAsyncImage(
                        url: imageURL,
                        logCategory: "CastPersonCard",
                        logContext: "name=\(name)",
                        content: { img in img.resizable().scaledToFill() },
                        placeholder: { placeholder() }
                    )
                } else {
                    placeholder()
                }
            }
            .frame(width: 60, height: 60)
            .clipShape(Circle())
            .overlay(Circle().stroke(hovered ? DT.Color.accent.opacity(0.6) : DT.Color.textPrimary.opacity(0.1), lineWidth: hovered ? 2 : 1))
            .scaleEffect(hovered ? 1.06 : 1)

            Text(name)
                .font(.system(.caption2, design: .default, weight: .semibold))
                .foregroundStyle(DT.Color.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            if let role, !role.isEmpty {
                Text(role)
                    .font(.system(.caption2, design: .default))
                    .foregroundStyle(DT.Color.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 70, alignment: .top)
        .animation(DT.Animation.fast, value: hovered)
        #if !os(tvOS)
        .onHover { hovered = $0 }
        #endif
    }
}

// MARK: - tvOS play button label
// Separate struct so @Environment(\.isFocused) reads the button's focus state,
// not the outer container. Ring/glow are drawn inside the button bounds only —
// no bleed into the surrounding layout padding.

#if os(tvOS)
private struct TVPlayButtonLabel: View {
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "play.fill")
                .scaledFont(size: 14)
            Text("Play")
                .scaledFont(size: 16, weight: .bold)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14 * DT.Scale.font)
        .background(LinearGradient(
            colors: [DT.Color.accentDeep, DT.Color.accent],
            startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DT.Radius.lg)
                .stroke(isFocused ? Color.white.opacity(0.6) : Color.clear, lineWidth: 3)
        )
        .shadow(
            color: isFocused ? DT.Color.accent.opacity(0.55) : DT.Color.accent.opacity(0.15),
            radius: isFocused ? 18 : 6
        )
        .scaleEffect(isFocused ? 1.02 : 1.0)
        .animation(DT.Animation.motion(.spring(response: 0.2, dampingFraction: 0.75)), value: isFocused)
    }
}
#endif

#Preview {
    NavigationStack {
        MediaDetailView(item: MediaItem(
            id: "1", name: "Dune: Part Two", type: .movie,
            backdropImageTags: [], productionYear: 2024, communityRating: 8.3
        ))
        .environment(MediaRepository())
        .environment(AuthManager())
    }
}
