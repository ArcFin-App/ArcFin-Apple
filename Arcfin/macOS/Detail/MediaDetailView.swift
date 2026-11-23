// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI
import AppIntents
import SeerrAPI
import SwiftData
import Persistence

struct MediaDetailView: View {
    let item: MediaItem
    /// Passed down from whichever screen pushed this view (Home/Library/PersonDetail each
    /// own their own @Namespace) so the Similar/Recommended rows below can zoom into a
    /// further MediaDetailView the same way the original poster tap did. nil when reached
    /// from a source that doesn't do the zoom transition (e.g. the Home hero banner).
    var zoomNamespace: Namespace.ID? = nil

    @Environment(MediaRepository.self) private var mediaRepo
    @Environment(SeerrRepository.self) private var seerrRepo
    @Environment(AuthManager.self) private var authManager
    @Environment(DownloadManager.self) private var downloadManager
    @Environment(PlaybackPresenter.self) private var playbackPresenter

    @State private var model: MediaDetailModel
    @State private var showSubtitleSearch = false
    @State private var openedCollection: MediaItem?
    @State private var openedPlaylist: MediaItem?
    @State private var selectedEpisode: MediaItem?
    @State private var selectedPerson: MediaPerson?
    @State private var youTubeTrailer: RemoteTrailer?
    @AppStorage("trailersEnabled") private var trailersEnabled = true
    @AppStorage("spoilerProtection") private var spoilerProtection = false
    @AppStorage("youtubeTrailersEnabled") private var youtubeTrailersEnabled = true
    @State private var requestingSeerrItem: SeerrItem?
    @State private var openedSeerrItem: SeerrItem?

    // A Mac window is far wider than a phone: a 260 pt strip of backdrop and a 90 pt
    // poster left the top of the page looking like a banner ad.
    private let headerMetrics = DetailHeaderMetrics(
        heroHeight: 420, posterSize: CGSize(width: 170, height: 250), titleStyle: .largeTitle,
        backdropFillWidth: 1800, posterFillWidth: 400
    )

    init(item: MediaItem, zoomNamespace: Namespace.ID? = nil) {
        self.item = item
        self.zoomNamespace = zoomNamespace
        _model = State(initialValue: MediaDetailModel(item: item))
    }

    var body: some View {
        let shareURL = model.shareURL(authManager: authManager)
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                MediaDetailHero(item: item, metrics: headerMetrics)
                MediaDetailTitleBlock(item: item, detail: model.detail, awards: model.awards, metrics: headerMetrics)
                if model.isLoading { loadingContent }
                else { detailContent }
                Spacer().frame(height: DT.Size.tabBarHeight + 24)
            }
        }
        .background {
            ZStack {
                DT.Color.backgroundPrimary
                if let heroTint = model.heroTint {
                    LinearGradient(colors: [heroTint.opacity(0.4), .clear], startPoint: .top, endPoint: .bottom)
                }
            }
            .ignoresSafeArea()
            .animation(DT.Animation.motion(.easeInOut(duration: 0.4)), value: model.heroTint)
        }
        .ignoresSafeArea(edges: .top)
        .task(id: item.id) {
            model.readKeptEpisodeCount()
            await model.loadHeroTint(mediaRepo: mediaRepo)
        }
        // Handoff to another device, Spotlight, and on-screen awareness: Siri and Apple
        // Intelligence can resolve "this movie" to the MediaEntity for what's on screen.
        .userActivity(ArcfinActivity.viewTitle) { activity in
            activity.title = item.name
            activity.isEligibleForHandoff = true
            // Kept out of Spotlight for a profile with an app-lock PIN, as its titles are.
            activity.isEligibleForSearch = IntentSession.credential() != nil
            activity.userInfo = ["itemID": item.id]
            activity.webpageURL = shareURL
            activity.appEntityIdentifier = EntityIdentifier(for: MediaEntity.self, identifier: item.id)
        }
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await model.refreshAfterPlayback(waitForReport: false, authManager: authManager) } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Refresh")
                .help("Refresh")
            }
            ToolbarItem(placement: .primaryAction) { DetailRatingMenu(model: model).help("Rate") }
            ToolbarItem(placement: .primaryAction) {
                Button { model.toggleFavorite(authManager: authManager) } label: {
                    Image(systemName: model.isFavorite ? "heart.fill" : "heart")
                        .foregroundStyle(model.isFavorite ? DT.Color.palette("F43F5E") : DT.Color.textPrimary)
                }
                .accessibilityLabel(model.isFavorite ? "Remove from favorites" : "Add to favorites")
                .help(model.isFavorite ? "Remove from Favorites" : "Add to Favorites")
            }
            if item.type == .movie || item.type == .episode {
                ToolbarItem(placement: .primaryAction) {
                    DownloadButton(item: item, hitSize: 24).help("Download")
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
            ToolbarItem(placement: .primaryAction) { DetailMoreMenu(model: model) { showSubtitleSearch = true }.help("More") }
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
        .navigationDestination(item: $openedCollection) { collection in
            CollectionDetailView(collection: collection)
        }
        .navigationDestination(item: $openedPlaylist) { LibraryDetailView(playlistItem: $0) }
        .navigationDestination(item: $selectedEpisode) { ep in
            MediaDetailView(item: ep, zoomNamespace: zoomNamespace)
        }
        .navigationDestination(item: $selectedPerson) { person in
            PersonDetailView(person: person)
        }
        .navigationDestination(item: $openedSeerrItem) { item in
            SeerrItemDetailView(item: item)
        }
        .sheet(item: $requestingSeerrItem) { item in
            SeerrRequestConfirmSheet(item: item, requestingItem: $requestingSeerrItem)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $model.isSeasonDownloadSheetShown) {
            DownloadConfirmSheet(item: model.selectedSeason ?? item) {
                await model.seasonPreview(authManager: authManager, downloadManager: downloadManager)
            } onConfirm: { choice in
                model.downloadSeason(choice, authManager: authManager, downloadManager: downloadManager)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .alert(
            "This is downloaded — play the offline copy or stream from the server?",
            isPresented: Binding(get: { model.pendingPlaybackChoice != nil }, set: { if !$0 { model.pendingPlaybackChoice = nil } })
        ) {
            Button("Play Downloaded") { model.playDownloadedCopy(downloadManager: downloadManager) }
            Button("Stream Online") { model.streamInstead() }
            Button("Cancel", role: .cancel) { model.pendingPlaybackChoice = nil }
        }
        // fullScreenCover is unavailable on macOS; a download plays in a sheet, as on the
        // downloaded titles' own pages.
        .sheet(item: $model.offlinePlaybackTarget, onDismiss: { Task { await model.refreshAfterPlayback(authManager: authManager) } }) { downloaded in
            PlayerView(download: downloaded, startPositionOverride: model.offlineStartOverride) { model.playDownloaded($0) }
                .id(downloaded.itemId)
                .frame(minWidth: 900, minHeight: 560)
        }
        .alert("Download Failed", isPresented: Binding(
            get: { model.seasonDownloadErrorMessage != nil }, set: { if !$0 { model.seasonDownloadErrorMessage = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(model.seasonDownloadErrorMessage ?? "")
        }
        .onChange(of: downloadManager.errors) { _, newErrors in
            model.noteSeasonDownloadErrors(newErrors, downloadManager: downloadManager)
        }
        // The fixed wait after the player closes can beat the stop report to the server.
        .onReceive(NotificationCenter.default.publisher(for: .arcfinPlaybackReported)) { _ in
            Task { await model.refreshAfterPlayback(waitForReport: false, authManager: authManager) }
        }
        // A .sheet on macOS can't fill/fullscreen a window — PlayerView is rendered as a
        // full-window overlay by ContentView instead, driven by the shared PlaybackPresenter.
        .onChange(of: model.playbackRequest) { _, request in
            guard let request else { return }
            playbackPresenter.present(request.item, startTicks: request.startTicks) { model.lastPlayedItem = $0 }
            model.playbackRequest = nil
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
        // A page handed another title (a link opened while one is showing) keeps its state, so
        // it would show the new title's name over the old one's details: start it over.
        .task(id: item.id) {
            if model.item.id != item.id { model = MediaDetailModel(item: item) }
            await loadPage()
        }
        // Apart from load(): the first lookup reads every collection and playlist.
        .task(id: item.id) { await model.loadContainingSets(authManager: authManager) }
        .task(id: item.tmdbId) { await model.loadAwards() }
        .onChange(of: model.selectedSeason) { _, season in
            model.showSeason(season, authManager: authManager)
        }
    }

    private func loadPage() async {
        await model.load(authManager: authManager, seerrRepo: seerrRepo, downloadManager: downloadManager,
                         trailers: trailersEnabled ? .alongside(youTubeFallback: youtubeTrailersEnabled) : .skipped,
                         seriesOpensOnSeasonInProgress: true)
    }

    private func playerDismissed() {
        if let next = model.playerDismissed(authManager: authManager, downloadManager: downloadManager) {
            selectedEpisode = next
        }
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
        DetailPlayButton(model: model)
        if model.detailFailed {
            DetailLoadFailedRow { Task { await loadPage() } }
        }
        if model.hasPlayableTrailer(trailersEnabled: trailersEnabled, youTubeTrailersEnabled: youtubeTrailersEnabled) {
            DetailTrailerButton(model: model) { youTubeTrailer = $0 }
        }

        if let d = model.detail, !d.genres.isEmpty {
            DetailGenreChips(genres: d.genres)
        }

        // Overview
        if let overview = model.detail?.item.overview ?? item.overview, !overview.isEmpty {
            DetailOverviewSection(text: overview)
        }

        // Cast
        // Review scores sit with the description, ahead of the cast.
        TitleInsights(tmdbId: model.insightsTmdbId, mediaType: MediaDetailModel.seerrMediaType(for: item), part: .ratings)
            .padding(.horizontal, DT.Spacing.pagePad)

        if let d = model.detail, !d.cast.isEmpty { DetailCastSection(cast: d.cast) { selectedPerson = $0 } }

        // Crew
        if let d = model.detail, (!d.directors.isEmpty || !d.writers.isEmpty) {
            DetailCrewSection(directors: d.directors, writers: d.writers)
        }

        if let seriesItem = model.seriesItem, item.type == .episode {
            DetailSeriesLink(series: seriesItem) { label in
                Button { selectedEpisode = seriesItem } label: { label }
            }
        }

        // Series: seasons + episodes
        if !model.seasons.isEmpty {
            DetailSeriesSection(model: model, spoilerProtection: spoilerProtection) { selectedEpisode = $0 }
        }

        // Similar / recommended
        if !model.seerrRelatedItems.isEmpty {
            DetailSeerrShelf(items: model.seerrRelatedItems, subtitle: {
                model.seerrRelatedSubtitle($0, mediaRepo: mediaRepo, seerrRepo: seerrRepo)
            }, onSelect: openSeerrRelated)
        } else if !model.similarItems.isEmpty {
            DetailTitleShelf(title: Text("More Like This"), items: model.similarItems) { rec, poster in titleLink(rec, poster) }
        }
        if let jellyfinRecommended = model.jellyfinRecommended, !jellyfinRecommended.items.isEmpty {
            DetailTitleShelf(title: Text(verbatim: jellyfinRecommended.title), items: jellyfinRecommended.items) { rec, poster in titleLink(rec, poster) }
        }
        if !model.containingCollections.isEmpty {
            DetailSetShelf(title: model.containingCollections.count == 1 ? "Collection" : "Collections", sets: model.containingCollections) { openedCollection = $0 }
        }
        if !model.containingPlaylists.isEmpty {
            DetailSetShelf(title: "In Your Playlists", sets: model.containingPlaylists) { openedPlaylist = $0 }
        }

        // Scores, where else it's streaming, and the details list. An episode's TMDB id is
        // the episode's, which Seerr's title lookups don't take, so episodes show the
        // server's details only.
        TitleInsights(tmdbId: model.insightsTmdbId, mediaType: MediaDetailModel.seerrMediaType(for: item), detail: model.detail, part: .details)
            .padding(.horizontal, DT.Spacing.pagePad)
            .padding(.top, DT.Spacing.md)
    }

    /// A NavigationLink(value:) can't always find the stack's destination on the Mac, so a
    /// title opens through the page's own destination instead.
    private func titleLink(_ rec: MediaItem, _ poster: PosterCard) -> some View {
        Button { selectedEpisode = rec } label: { poster }
            .buttonStyle(.plain)
            .zoomTransitionSource(id: rec.id, in: zoomNamespace)
    }

    private func openSeerrRelated(_ related: SeerrItem) {
        Task {
            switch await model.destination(forRelated: related, authManager: authManager, seerrRepo: seerrRepo) {
            case .library(let local): selectedEpisode = local
            case .seerrPage(let item): openedSeerrItem = item
            case .request(let item): requestingSeerrItem = item
            }
        }
    }
}

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
