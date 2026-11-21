// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import SwiftData
import JellyfinAPI
import SeerrAPI
import AuthCore
import Persistence

/// A title page's data and what it asks of the server, shared by every platform's `MediaDetailView`.
@MainActor @Observable
final class MediaDetailModel {
    let item: MediaItem

    private(set) var detail: MediaItemDetail?
    private(set) var awards: [WikidataAward] = []
    private(set) var isLoading = true
    private(set) var isFavorite = false
    private(set) var likes: Bool?
    private(set) var isWatched = false
    private(set) var heroTint: Color?
    /// Upcoming episodes of this show kept downloaded automatically; 0 when off.
    private(set) var keptEpisodeCount = 0
    private(set) var similarItems: [MediaItem] = []
    private(set) var seerrRelatedItems: [SeerrItem] = []
    /// Jellyfin-native fallback for the "Recommended" row when Seerr isn't configured —
    /// Movies/Recommendations is server-wide, not per-item, so this is filtered down to
    /// whichever returned category (if any) names this movie as its baseline.
    private(set) var jellyfinRecommended: MovieRecommendationCategory?
    private(set) var seriesItem: MediaItem?
    /// Collections and playlists this title (or an episode's show) is in.
    private(set) var containingCollections: [MediaItem] = []
    private(set) var containingPlaylists: [MediaItem] = []
    /// The episode a series-level Play/Resume button actually starts — a series itself
    /// isn't playable, so this is what getNextEpisode() resolves to.
    private(set) var nextEpisode: MediaItem?
    private(set) var seasons: [MediaItem] = []
    var selectedSeason: MediaItem?
    private(set) var episodes: [MediaItem] = []
    /// The episode a horizontal episode row scrolls to once the season loads.
    var initialEpisodeID: String?
    private(set) var trailers: [MediaItem] = []
    private(set) var remoteTrailer: RemoteTrailer?
    private var loadedSeasonId: String?
    private var seasonTask: Task<Void, Never>?
    /// The picked season's episodes couldn't be fetched; the list offers to try again.
    private(set) var episodesLoadFailed = false

    var playbackRequest: MediaDetailView.PlaybackRequest?
    /// The title the player ended up on after handing over to a suggestion or next episode.
    var lastPlayedItem: MediaItem?
    /// Set when the target is already downloaded — offers a choice instead of always
    /// streaming, since previously Play/Resume ignored a local copy entirely.
    var pendingPlaybackChoice: PlaybackChoice?
    var offlinePlaybackTarget: DownloadedItem?
    private(set) var offlineStartOverride: Int64?

    var isSeasonDownloadSheetShown = false
    /// Surfaces a season download failure that would otherwise only show up as a raw
    /// NSURLError buried in per-episode state nobody's looking at during a bulk download.
    var seasonDownloadErrorMessage: String?

    private let client = JellyfinMediaClient()

    struct PlaybackChoice: Identifiable {
        let id = UUID()
        let item: MediaItem
        let startTicks: Int64
        let isExplicitStartOver: Bool
    }

    /// How a page gets its trailers: alongside the rest without holding the page up, or as part
    /// of the load, for a layout where a trailer row popping in late would move what's below it.
    enum TrailerLoading {
        case skipped
        case alongside(youTubeFallback: Bool)
        case withPage
    }

    /// How the episode list shows a change in watched state: updated in place straight away, or
    /// re-read from the server once the change is saved.
    enum WatchedUpdate { case inPlace, reload }

    enum WatchScope { case season, series }

    /// Where a Seerr recommendation opens.
    enum RelatedDestination {
        case library(MediaItem)
        case seerrPage(SeerrItem)
        case request(SeerrItem)
    }

    init(item: MediaItem) {
        self.item = item
    }

    private func session(_ authManager: AuthManager) -> (credential: ServerCredential, authHeader: String)? {
        guard let credential = authManager.state.credential else { return nil }
        return (credential, authManager.authClient.authHeader(token: credential.accessToken))
    }

    // MARK: - Load

    func load(authManager: AuthManager, seerrRepo: SeerrRepository, downloadManager: DownloadManager?,
              trailers trailerLoading: TrailerLoading, seriesOpensOnSeasonInProgress: Bool) async {
        isLoading = true
        defer { isLoading = false }
        guard case let (cred, header)? = session(authManager) else { return }

        async let detailTask = client.getItemDetail(credential: cred, authHeader: header, itemId: item.id)
        if case .withPage = trailerLoading {} else { trailers = [] }

        // Without a connection, a downloaded title still has its full page from when it was saved.
        let fetchedDetail = (try? await detailTask) ?? downloadManager?.savedDetail(itemId: item.id)
        detail = fetchedDetail
        isFavorite = fetchedDetail?.item.userData?.isFavorite ?? item.userData?.isFavorite ?? false
        likes = fetchedDetail?.item.userData?.likes ?? item.userData?.likes
        isWatched = fetchedDetail?.item.userData?.played ?? item.userData?.played ?? false
        if item.type == .episode, let seriesId = item.seriesId {
            seriesItem = (try? await client.getItemDetail(credential: cred, authHeader: header, itemId: seriesId))?.item
        }

        if let fetchedDetail, let mediaType = Self.seerrMediaType(for: fetchedDetail.item),
           let tmdbId = fetchedDetail.item.tmdbId {
            seerrRelatedItems = await seerrRepo.relatedMedia(mediaType: mediaType, mediaId: tmdbId)
        }
        if seerrRelatedItems.isEmpty {
            similarItems = (try? await client.getSimilarItems(credential: cred, authHeader: header, itemId: item.id)) ?? []
        } else {
            similarItems = []
        }

        var recommended: MovieRecommendationCategory?
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
                    recommended = MovieRecommendationCategory(
                        id: match.id, recommendationType: match.recommendationType,
                        baselineItemName: match.baselineItemName, items: fresh)
                }
            }
        }
        jellyfinRecommended = recommended

        remoteTrailer = nil
        switch trailerLoading {
        case .skipped:
            break
        case .alongside(let youTubeFallback):
            Task {
                let fetchedTrailers = (try? await client.getTrailers(
                    credential: cred,
                    authHeader: header,
                    itemId: item.id,
                    limit: 6
                )) ?? []
                trailers = fetchedTrailers
                // Only fall back to a remote (YouTube) trailer once we know there's
                // genuinely no local one — a local file always streams better than an
                // embedded web player.
                if fetchedTrailers.isEmpty, youTubeFallback {
                    remoteTrailer = fetchedDetail?.remoteTrailers.first { $0.youTubeVideoID != nil }
                }
            }
        case .withPage:
            // Awaited like every other section's fetch above — a detached Task here let the
            // page finish loading and render (isLoading already false) before trailers arrived,
            // so trailersSection popped in late and shoved Cast/Recommended down into an
            // already-settled, already-focused layout, reading as an unexplained gap.
            trailers = (try? await client.getTrailers(
                credential: cred, authHeader: header, itemId: item.id, limit: 6)) ?? []
        }

        guard let seriesId = seasonSeriesId else { return }
        seasons = (try? await client.getSeasons(credential: cred, authHeader: header, seriesId: seriesId)) ?? []
        guard let first = seasons.first else { return }
        var target = season(for: item, in: seasons, preferringProgress: seriesOpensOnSeasonInProgress) ?? first
        if item.type == .series,
           let nextEp = try? await client.getNextEpisode(credential: cred, authHeader: header, seriesId: seriesId) {
            // Ask the server which episode is next — use its season and scroll to it.
            nextEpisode = nextEp
            if let seasonNum = nextEp.parentIndexNumber,
               let matched = seasons.first(where: { $0.indexNumber == seasonNum }) {
                target = matched
            }
            initialEpisodeID = nextEp.id
        } else if item.type == .episode {
            initialEpisodeID = item.id
        }
        selectedSeason = target
        loadedSeasonId = target.id
        let fetched = try? await client.getEpisodes(credential: cred, authHeader: header,
                                                    seriesId: seriesId, seasonId: target.id)
        guard loadedSeasonId == target.id else { return }
        episodes = fetched ?? []
        episodesLoadFailed = fetched == nil
    }

    private func season(for item: MediaItem, in seasons: [MediaItem], preferringProgress: Bool) -> MediaItem? {
        if item.type == .episode, let seasonNumber = item.parentIndexNumber {
            return seasons.first(where: { $0.indexNumber == seasonNumber })
        }
        if item.type == .season {
            return seasons.first(where: { $0.id == item.id }) ?? seasons.first
        }
        guard preferringProgress else { return seasons.first }
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

    /// Loads the episodes of a season picked from the season menu.
    func showSeason(_ season: MediaItem?, authManager: AuthManager) {
        guard let season, season.id != loadedSeasonId else { return }
        loadEpisodes(seasonId: season.id, authManager: authManager)
    }

    func retryEpisodes(authManager: AuthManager) {
        guard let seasonId = selectedSeason?.id else { return }
        loadEpisodes(seasonId: seasonId, authManager: authManager)
    }

    /// Only the newest pick lands: an earlier season's response arriving late would otherwise
    /// fill the list under the later season's name.
    private func loadEpisodes(seasonId: String, authManager: AuthManager) {
        guard let seriesId = seasonSeriesId, case let (cred, header)? = session(authManager) else { return }
        seasonTask?.cancel()
        loadedSeasonId = seasonId
        episodesLoadFailed = false
        seasonTask = Task {
            let fetched = try? await client.getEpisodes(credential: cred, authHeader: header,
                                                        seriesId: seriesId, seasonId: seasonId)
            guard !Task.isCancelled, loadedSeasonId == seasonId else { return }
            episodes = fetched ?? []
            episodesLoadFailed = fetched == nil
        }
    }

    /// Re-reads the playback position after the player closes, so Play becomes Resume (and the
    /// episode list's progress updates) without leaving and re-entering this screen. A full
    /// `load()` would flash the loading state, so only the progress-bearing data is refetched.
    func refreshAfterPlayback(waitForReport: Bool = true, authManager: AuthManager) async {
        guard case let (cred, header)? = session(authManager) else { return }
        // The player reports its final position as it closes; give that request a moment to land.
        if waitForReport { try? await Task.sleep(for: .milliseconds(700)) }
        if let fresh = try? await client.getItemDetail(credential: cred, authHeader: header, itemId: item.id) {
            detail = fresh
            isWatched = fresh.item.userData?.played ?? false
        }
        guard let seriesId = seasonSeriesId else { return }
        if item.type == .series,
           let nextEp = try? await client.getNextEpisode(credential: cred, authHeader: header, seriesId: seriesId) {
            nextEpisode = nextEp
        }
        if let seasonId = loadedSeasonId,
           let fresh = try? await client.getEpisodes(credential: cred, authHeader: header, seriesId: seriesId, seasonId: seasonId),
           loadedSeasonId == seasonId {
            episodes = fresh
        }
    }

    func loadContainingSets(authManager: AuthManager) async {
        guard case let (cred, header)? = session(authManager) else { return }
        let found = await ContainingSets.shared.sets(containing: [item.id, item.seriesId].compactMap { $0 },
                                                     credential: cred, authHeader: header)
        containingCollections = found.collections
        containingPlaylists = found.playlists
    }

    func loadAwards() async {
        guard let tmdbId = item.tmdbId else { return }
        awards = await WikidataAwardsClient.shared.awards(
            tmdbId: tmdbId, mediaType: item.type == .series ? .tv : .movie
        )
    }

    /// What Ignore in Smart Downloads applies to here: the movie, or the whole show.
    var smartDownloadsTarget: (id: String, name: String)? {
        if item.type == .movie { return (item.id, item.name) }
        return seasonSeriesId.map { ($0, item.seriesName ?? item.name) }
    }

    func readKeptEpisodeCount() {
        if let seriesId = seasonSeriesId {
            keptEpisodeCount = DownloadManager.keptShows[seriesId]?.episodeCount ?? 0
        }
    }

    func loadHeroTint(mediaRepo: MediaRepository) async {
        guard let url = mediaRepo.imageURL(for: item, type: .backdrop, fillWidth: 120) else { return }
        heroTint = await AverageColor.load(from: url)
    }

    // MARK: - Play

    /// A series itself isn't playable — Play/Resume on a series page actually starts
    /// whichever episode getNextEpisode() resolved to.
    var playTarget: MediaItem {
        item.type == .series ? (nextEpisode ?? item) : (detail?.item ?? item)
    }

    var isResumable: Bool {
        guard let ud = playTarget.userData else { return false }
        return ud.playbackPositionTicks > 0 && !ud.played
    }

    /// When playback started right now would finish, counting from the resume point if there
    /// is one — only meaningful for a single playable item, not a series or season.
    var endTime: Date? {
        guard item.type == .movie || item.type == .episode,
              let total = detail?.runTimeTicks, total > 0
        else { return nil }
        let watched = isResumable ? (playTarget.userData?.playbackPositionTicks ?? 0) : 0
        let remainingSeconds = Double(max(total - watched, 0)) / 10_000_000
        return Date().addingTimeInterval(remainingSeconds)
    }

    func requestPlayback(startTicks: Int64, isExplicitStartOver: Bool = false, downloadManager: DownloadManager) {
        let target = playTarget
        if downloadManager.isDownloaded(target.id) {
            pendingPlaybackChoice = PlaybackChoice(item: target, startTicks: startTicks, isExplicitStartOver: isExplicitStartOver)
        } else {
            playbackRequest = MediaDetailView.PlaybackRequest(item: target, startTicks: startTicks)
        }
    }

    func playDownloadedCopy(modelContext: ModelContext) {
        if let choice = pendingPlaybackChoice, let downloaded = downloadedItem(itemId: choice.item.id, in: modelContext) {
            offlineStartOverride = choice.isExplicitStartOver ? 0 : nil
            offlinePlaybackTarget = downloaded
        }
        pendingPlaybackChoice = nil
    }

    func streamInstead() {
        if let choice = pendingPlaybackChoice {
            playbackRequest = MediaDetailView.PlaybackRequest(item: choice.item, startTicks: choice.startTicks)
        }
        pendingPlaybackChoice = nil
    }

    private func downloadedItem(itemId: String, in modelContext: ModelContext) -> DownloadedItem? {
        let descriptor = FetchDescriptor<DownloadedItem>(predicate: #Predicate { $0.itemId == itemId })
        return try? modelContext.fetch(descriptor).first
    }

    func play(_ item: MediaItem) {
        playbackRequest = MediaDetailView.PlaybackRequest(item: item, startTicks: 0)
    }

    /// The player moved on to `next` without closing.
    func handOver(to next: MediaItem) {
        lastPlayedItem = next
        playbackRequest = MediaDetailView.PlaybackRequest(item: next, startTicks: 0)
    }

    /// Closing the player lands on whatever it was last playing: a suggestion opens its own
    /// detail screen (returned here), while later episodes of this series just refresh this one.
    func playerDismissed(authManager: AuthManager, downloadManager: DownloadManager) -> MediaItem? {
        let last = lastPlayedItem
        lastPlayedItem = nil
        Task { await refreshAfterPlayback(authManager: authManager) }
        downloadManager.refreshSmartDownloads()
        guard let last, last.id != item.id else { return nil }
        let sameSeries = last.type == .episode && last.seriesId != nil && last.seriesId == seasonSeriesId
        return sameSeries ? nil : last
    }

    func hasPlayableTrailer(trailersEnabled: Bool, youTubeTrailersEnabled: Bool) -> Bool {
        guard trailersEnabled else { return false }
        return !trailers.isEmpty || (youTubeTrailersEnabled && remoteTrailer != nil)
    }

    // MARK: - Rating, favorite, watched

    /// Tapping the current rating again clears it.
    func setRating(_ value: Bool, authManager: AuthManager) {
        guard case let (cred, header)? = session(authManager) else { return }
        let newValue: Bool? = likes == value ? nil : value
        likes = newValue
        HapticManager.impact(.light)
        Task {
            try? await client.setRating(credential: cred, authHeader: header, itemId: item.id, likes: newValue)
        }
    }

    func toggleFavorite(authManager: AuthManager) {
        guard case let (cred, header)? = session(authManager) else { return }
        let newValue = !isFavorite
        isFavorite = newValue
        HapticManager.impact(.light)
        Task {
            try? await client.markFavorite(credential: cred, authHeader: header, itemId: item.id, favorite: newValue)
        }
    }

    func markWatched(_ watched: Bool, authManager: AuthManager) {
        guard case let (cred, header)? = session(authManager) else { return }
        isWatched = watched
        Task {
            try? await client.markWatched(credential: cred, authHeader: header, itemId: item.id, watched: watched)
            await refreshAfterPlayback(waitForReport: false, authManager: authManager)
        }
    }

    func markEpisodeWatched(_ ep: MediaItem, watched: Bool, update: WatchedUpdate, authManager: AuthManager) {
        guard case let (cred, header)? = session(authManager) else { return }
        Task {
            try? await client.markWatched(credential: cred, authHeader: header, itemId: ep.id, watched: watched)
            switch update {
            case .inPlace:
                if let idx = episodes.firstIndex(where: { $0.id == ep.id }) {
                    episodes[idx] = withWatchedUserData(episodes[idx], watched: watched)
                }
            case .reload:
                await refreshAfterPlayback(waitForReport: false, authManager: authManager)
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

    /// Marks a whole season or series watched/unwatched by looping markWatched over the
    /// episode ids already available (current season) or fetched per-season (whole series).
    /// In place, the visible `episodes` array is updated optimistically so watched indicators
    /// refresh without a manual pull-to-refresh, matching markEpisodeWatched's single-item approach.
    func markScopeWatched(_ scope: WatchScope, watched: Bool, update: WatchedUpdate, authManager: AuthManager) {
        guard case let (cred, header)? = session(authManager), let seriesId = seasonSeriesId else { return }
        HapticManager.impact(.light)
        if update == .inPlace {
            episodes = episodes.map { withWatchedUserData($0, watched: watched) }
        }
        let currentEpisodes = episodes
        let allSeasons = seasons
        Task {
            switch scope {
            case .season:
                for ep in currentEpisodes {
                    try? await client.markWatched(credential: cred, authHeader: header, itemId: ep.id, watched: watched)
                }
            case .series:
                for season in allSeasons {
                    let seasonEpisodes = (try? await client.getEpisodes(
                        credential: cred, authHeader: header, seriesId: seriesId, seasonId: season.id
                    )) ?? []
                    for ep in seasonEpisodes {
                        try? await client.markWatched(credential: cred, authHeader: header, itemId: ep.id, watched: watched)
                    }
                }
            }
            if update == .reload {
                await refreshAfterPlayback(waitForReport: false, authManager: authManager)
            }
        }
    }

    /// "NEW" for an unwatched episode that premiered in the last two weeks; "FINALE" for the
    /// last episode of the season being shown. With `marksUnavailable`, an episode listed
    /// before it's out or missing from the server says so instead.
    func episodeBadge(_ ep: MediaItem, marksUnavailable: Bool) -> String? {
        if marksUnavailable, ep.isVirtual { return MediaDetailView.unavailableText(ep).uppercased() }
        if ep.userData?.played != true, let premiere = ep.premiereDate,
           premiere <= Date(), Date().timeIntervalSince(premiere) < 14 * 86_400 {
            return "NEW"
        }
        if episodes.count > 1, ep.id == episodes.last?.id { return "FINALE" }
        return nil
    }

    // MARK: - Downloads

    func setKeptEpisodeCount(_ count: Int, downloadManager: DownloadManager) {
        guard let seriesId = seasonSeriesId else { return }
        keptEpisodeCount = count
        downloadManager.setKeptShow(seriesId: seriesId, name: item.seriesName ?? item.name,
                                    episodeCount: count == 0 ? nil : count)
    }

    /// Every episode in the current season already downloaded — the "Download Season"
    /// button should be inert then, not just silently no-op every episode it loops over.
    func isSeasonFullyDownloaded(in downloadManager: DownloadManager) -> Bool {
        !episodes.isEmpty && seasonEpisodesToDownload(in: downloadManager).isEmpty
    }

    /// Settings › Downloads › Season Downloads can leave out episodes already watched.
    private func seasonEpisodesToDownload(in downloadManager: DownloadManager) -> [MediaItem] {
        let unwatchedOnly = UserDefaults.standard.bool(forKey: "seasonDownloadUnwatchedOnly")
        return episodes.filter { !$0.isVirtual && !downloadManager.isDownloaded($0.id) && !(unwatchedOnly && $0.userData?.played == true) }
    }

    /// Opens the download sheet for the season at once; it fills in from `seasonPreview`.
    func openSeasonDownload(downloadManager: DownloadManager) {
        guard !seasonEpisodesToDownload(in: downloadManager).isEmpty else { return }
        isSeasonDownloadSheetShown = true
    }

    /// One representative preview (the first episode not downloaded yet), scaled to every
    /// episode still to download rather than a playback-info round trip per episode.
    func seasonPreview(authManager: AuthManager, downloadManager: DownloadManager) async -> DownloadManager.DownloadPreview? {
        guard case .authenticated(let credential) = authManager.state else { return nil }
        let pending = seasonEpisodesToDownload(in: downloadManager)
        guard let firstPending = pending.first else { return nil }
        let authHeader = authManager.authClient.authHeader(token: credential.accessToken)
        guard var preview = await downloadManager.preview(for: firstPending, credential: credential, authHeader: authHeader) else { return nil }
        let count = Int64(pending.count)
        preview.estimatedSizeBytes = preview.estimatedSizeBytes.map { $0 * count }
        preview.estimatedSizeIsApproximate = true
        preview.runtimeTicks = preview.runtimeTicks.map { $0 * count }
        preview.episodeCount = pending.count
        return preview
    }

    func downloadSeason(_ choice: DownloadChoice, authManager: AuthManager, downloadManager: DownloadManager) {
        guard case .authenticated(let credential) = authManager.state else { return }
        let authHeader = authManager.authClient.authHeader(token: credential.accessToken)
        for episode in seasonEpisodesToDownload(in: downloadManager) {
            Task {
                await downloadManager.startDownload(item: episode, credential: credential, authHeader: authHeader,
                                                    bitrateCap: choice.bitrateCap, tracks: choice.tracks)
            }
        }
    }

    /// Picks up the first failure among this season's episodes.
    func noteSeasonDownloadErrors(_ newErrors: [String: String], downloadManager: DownloadManager) {
        guard seasonDownloadErrorMessage == nil else { return }
        for episode in episodes {
            if let raw = newErrors[episode.id] {
                seasonDownloadErrorMessage = friendlyDownloadError(raw)
                downloadManager.errors[episode.id] = nil
                break
            }
        }
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

    // MARK: - Seerr

    func seerrRelatedSubtitle(_ item: SeerrItem, mediaRepo: MediaRepository, seerrRepo: SeerrRepository) -> String? {
        let status: String? = mediaRepo.hasInLibrary(item) ? String(localized: "In Library")
            : seerrRepo.isRequested(item) ? String(localized: "Requested") : nil
        return [item.year, status].compactMap { $0 }.joined(separator: " · ").nilIfEmpty
    }

    /// The library's copy when the server has it, the title's Seerr page when it's already
    /// requested, and only otherwise the request sheet.
    func destination(forRelated item: SeerrItem, authManager: AuthManager, seerrRepo: SeerrRepository) async -> RelatedDestination {
        if case let (cred, header)? = session(authManager),
           let local = try? await client.findItem(
               credential: cred, authHeader: header, tmdbId: item.id, isSeries: item.mediaType == .tv,
               title: item.title, year: item.year.flatMap { Int($0.prefix(4)) }) {
            return .library(local)
        } else if seerrRepo.isRequested(item) {
            return .seerrPage(item)
        } else {
            return .request(item)
        }
    }

    // MARK: - Helpers

    /// Jellyfin web client's details page for this item — the same link the web UI's own
    /// "copy link" produces, so anyone with access to the server can open it.
    func shareURL(authManager: AuthManager) -> URL? {
        guard let base = authManager.state.credential?.baseURL,
              var comps = URLComponents(url: base, resolvingAgainstBaseURL: false)
        else { return nil }
        let basePath = comps.path.hasSuffix("/") ? String(comps.path.dropLast()) : comps.path
        comps.path = basePath + "/web/"
        comps.fragment = "/details?id=\(item.id)"
        return comps.url
    }

    /// An episode's TMDB id is the episode's own, which Seerr's title lookups don't take, so
    /// episodes show the server's details only.
    var insightsTmdbId: Int? {
        item.type == .episode ? nil : (detail?.item.tmdbId ?? item.tmdbId)
    }

    static func seerrMediaType(for item: MediaItem) -> RequestMediaType? {
        switch item.type {
        case .movie: .movie
        case .series, .season, .episode: .tv
        default: nil
        }
    }

    var seasonSeriesId: String? {
        switch item.type {
        case .series: item.id
        case .season, .episode: item.seriesId
        default: nil
        }
    }
}

extension MediaDetailView {
    struct PlaybackRequest: Identifiable, Equatable {
        // One constant identity, so handing over to the next title updates the open player
        // cover in place instead of dismissing and re-presenting it (which dropped the
        // rotation and flashed the detail screen in between).
        var id: String { "player" }
        let item: MediaItem
        let startTicks: Int64
    }

    /// "Airs 30 Oct" for an episode listed before it's out; "Not on Your Server" for one missing.
    static func unavailableText(_ item: MediaItem) -> String {
        if let premiere = item.premiereDate, premiere > Date() {
            return "Airs \(premiere.formatted(.dateTime.day().month(.abbreviated)))"
        }
        return "Not on Your Server"
    }
}
