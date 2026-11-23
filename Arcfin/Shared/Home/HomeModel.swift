// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI
import SeerrAPI
import AuthCore
import Telemetry
import os

/// Home's shelves and Seerr rows, and the titles and playback it has been asked to open,
/// shared by every platform's `HomeView`.
@MainActor @Observable
final class HomeModel {
    private(set) var shuffledShelves = HomeShelfPrefs.shuffledOrder()
    /// Titles the user requested through Seerr that have since arrived in the library.
    private(set) var nowAvailable: [MediaItem] = []
    /// "Popular on …" rows, by streaming service id.
    private(set) var serviceRows: [Int: [SeerrItem]] = [:]
    /// The first load has been trying for a while with nothing to show yet; offers a way
    /// out instead of leaving the placeholder shelves up for the whole retry cycle.
    private(set) var isSlowFirstLoad = false

    var detailItem: MediaItem?
    /// Play / Resume straight away, without opening the title's page.
    var playbackRequest: PlaybackRequest?
    /// The Live TV shelves' channels and programmes.
    let liveTV = HomeLiveTVShelves()
    var seerrDetailItem: SeerrItem?
    var seerrRequestItem: SeerrItem?
    var deepLinkItemID: String?

    // MARK: - Shelves

    func reshuffleShelves() {
        shuffledShelves = HomeShelfPrefs.shuffledOrder()
    }

    /// The user's shelves from Settings › Appearance › Home Shelves, in their order.
    func shelves(order: String, active: String, shuffled: Bool) -> [HomeShelf] {
        let activeShelves = HomeShelfPrefs.active(from: active)
        let order = shuffled ? shuffledShelves : HomeShelfPrefs.order(from: order)
        return order.filter { activeShelves.contains($0) }
    }

    /// Continue Watching then Up Next, each title once.
    static func continueAndNext(in mediaRepo: MediaRepository) -> [MediaItem] {
        var seen = Set<String>()
        return (mediaRepo.continueWatching + mediaRepo.nextUp).filter { seen.insert($0.id).inserted }
    }

    /// During the first load nothing has content yet, so shelves would pop in one by one and
    /// the shuffled order would look like it is rearranging. Showing every shelf as a
    /// placeholder row, in its final position, keeps the layout steady until real data arrives.
    static func showsShelfSkeleton(shuffled: Bool, mediaRepo: MediaRepository) -> Bool {
        shuffled && !mediaRepo.hasAnyContent && !mediaRepo.connectionFailed
    }

    // MARK: - Loading

    /// Loads the library's shelves; false when nobody is signed in.
    /// `shelves` is Home's rows in their current order; they load one at a time in it.
    func loadShelves(force: Bool, shelves: [HomeShelf], authManager: AuthManager, mediaRepo: MediaRepository) async -> Bool {
        guard case .authenticated(let cred) = authManager.state else { return false }
        await mediaRepo.load(credential: cred, authClient: authManager.authClient, force: force, shelfOrder: shelves)
        mediaRepo.prefetchQuickLookAssets(for: mediaRepo.continueWatching + mediaRepo.recentlyAdded)
        return true
    }

    func loadDiscover(enabled: Bool, mediaRepo: MediaRepository, seerrRepo: SeerrRepository) async {
        guard seerrRepo.hasCatalog && enabled else { return }
        await seerrRepo.loadDiscover()
        await seerrRepo.loadWatchlist()
        // Only the posters the rows show; a full-size backdrop for every title was mostly for
        // pages nobody opened.
        let seerrPosterURLs = (seerrRepo.trending + seerrRepo.popularMovies + seerrRepo.popularTV + seerrRepo.watchlist)
            .compactMap(\.posterURL)
        mediaRepo.prefetch(urls: seerrPosterURLs)
    }

    func saveTopShelf(mediaRepo: MediaRepository, title: (MediaItem) -> String, subtitle: (MediaItem) -> String?) {
        func entry(_ item: MediaItem, title: String, subtitle: String?, progress: Double, context: String) -> TopShelfMediaItem {
            TopShelfMediaItem(
                id: item.id, title: title, subtitle: subtitle,
                imageURL: mediaRepo.tvImageURL(for: item, fillWidth: 640),
                progress: progress,
                summary: item.overview,
                genre: item.genres.first,
                duration: item.runTimeTicks.map { TimeInterval($0) / 10_000_000 },
                year: item.productionYear,
                backdropURL: topShelfBackdropURL(for: item, mediaRepo: mediaRepo),
                contextTitle: [context, HomeText.episodeLabel(item), progress > 0 ? progress.formatted(.percent.precision(.fractionLength(0))) : nil]
                    .compactMap { $0 }.joined(separator: " · "),
                logoURL: mediaRepo.logoURL(itemID: item.type == .episode ? item.seriesId ?? item.id : item.id, fillWidth: 800),
                ratingTitle: String(localized: "Rating"),
                ratingValue: item.communityRating.flatMap { $0 > 0 ? "★ \($0.ratingText)" : nil },
                trailerItemID: item.type == .episode ? item.seriesId : item.id
            )
        }
        let resumeContext = String(localized: "Continue Watching")
        let nextUpContext = String(localized: "Next Up")
        let addedContext = String(localized: "Recently Added")
        TopShelfBridge.save(
            continueWatching: mediaRepo.continueWatching.prefix(5).map { item in
                let progress = item.userData?.playedPercentage.map { $0 / 100 } ?? 0
                return entry(item, title: title(item), subtitle: subtitle(item), progress: progress, context: resumeContext)
            },
            nextUp: mediaRepo.nextUp.prefix(3).map { item in
                entry(item, title: title(item), subtitle: subtitle(item), progress: 0, context: nextUpContext)
            },
            recentlyAdded: mediaRepo.recentlyAdded.prefix(3).map { item in
                entry(item, title: item.name, subtitle: nil, progress: 0, context: addedContext)
            },
            liveChannels: topShelfChannels(mediaRepo: mediaRepo)
        )
    }

    /// Favourite channels, when the Favorite Channels shelf is on: what's on now as the picture
    /// where the guide has one, otherwise the channel's logo.
    private func topShelfChannels(mediaRepo: MediaRepository) -> [TopShelfMediaItem] {
        let active = HomeShelfPrefs.active(from: UserDefaults.standard.string(forKey: HomeShelfPrefs.activeKey) ?? "")
        guard active.contains(.liveFavoriteChannels), HomeShelf.hasLiveTV(in: mediaRepo) else { return [] }
        let context = String(localized: "Favorite Channels")
        return liveTV.favorites.prefix(3).map { channel in
            let logo = mediaRepo.primaryImageURL(itemID: channel.id, tag: channel.primaryImageTag, fillWidth: 800)
            let program = channel.currentProgram.flatMap { $0.isAiring() ? $0 : nil }
            return TopShelfMediaItem(
                id: channel.id, title: channel.name, subtitle: program?.name, imageURL: logo, progress: 0,
                summary: program.map { [$0.name, $0.overview].compactMap { $0 }.joined(separator: "\n") },
                backdropURL: program.flatMap { mediaRepo.primaryImageURL(itemID: $0.id, tag: $0.primaryImageTag, fillWidth: 1920) },
                contextTitle: context, logoURL: logo)
        }
    }

    /// Episodes use the series' backdrop; the carousel is a full-width hero, not an episode still.
    private func topShelfBackdropURL(for item: MediaItem, mediaRepo: MediaRepository) -> URL? {
        if item.type == .episode,
           let parentID = item.parentBackdropItemId ?? item.seriesId,
           let tag = item.parentBackdropImageTags.first,
           let base = mediaRepo.baseURL, let token = mediaRepo.accessToken {
            return JellyfinMediaClient.imageURL(baseURL: base, itemID: parentID, tag: tag,
                                                type: .backdrop, fillWidth: 1920, token: token)
        }
        return mediaRepo.imageURL(for: item, type: .backdrop, fillWidth: 1920)
    }

    func loadServiceRows(seerrRepo: SeerrRepository) async {
        serviceRows = await HomeShelfLoader.serviceRows(seerrRepo: seerrRepo, previous: serviceRows)
    }

    func loadNowAvailable(_ requests: [SeerrRequestItem], authManager: AuthManager) async {
        guard !requests.isEmpty, let cred = authManager.state.credential else {
            nowAvailable = []
            return
        }
        let header = authManager.authClient.authHeader(token: cred.accessToken)
        let found = await HomeShelfLoader.nowAvailable(requests, credential: cred, authHeader: header)
        guard !Task.isCancelled, found != nil || nowAvailable.isEmpty else { return }
        nowAvailable = found ?? []
    }

    /// Run whenever `mediaRepo.isLoading` changes.
    func watchFirstLoad(mediaRepo: MediaRepository) async {
        guard mediaRepo.isLoading, !mediaRepo.hasAnyContent else {
            isSlowFirstLoad = false
            return
        }
        try? await Task.sleep(for: .seconds(6))
        guard !Task.isCancelled, mediaRepo.isLoading, !mediaRepo.hasAnyContent else { return }
        withAnimation(DT.Animation.fast) { isSlowFirstLoad = true }
    }

    // MARK: - Opening titles

    /// What Play on a series starts: its next episode, else its first.
    static func seriesPlayback(_ series: MediaItem, authManager: AuthManager) async -> PlaybackRequest? {
        guard let cred = authManager.state.credential else { return nil }
        let header = authManager.authClient.authHeader(token: cred.accessToken)
        return await WatchRoute.resolve(id: series.id, credential: cred, authHeader: header)
    }

    /// Opens a title from a widget, Spotlight, Siri or the Top Shelf. Titles that aren't on
    /// one of Home's shelves (an Up Next episode, a Spotlight result) are fetched by id.
    func openDeepLinkItem(id: String, authManager: AuthManager, mediaRepo: MediaRepository) {
        deepLinkItemID = nil
        let known = mediaRepo.continueWatching + mediaRepo.nextUp + mediaRepo.recentlyAdded
        if let local = known.first(where: { $0.id == id }) {
            detailItem = local
            return
        }
        guard let cred = authManager.state.credential else {
            deepLinkItemID = id
            return
        }
        let header = authManager.authClient.authHeader(token: cred.accessToken)
        Task {
            if let detail = try? await JellyfinMediaClient().getItemDetail(credential: cred, authHeader: header, itemId: id) {
                // A channel (a reminder, Siri) plays rather than opening a page it doesn't have.
                if detail.item.type == .tvChannel {
                    PlayQueue.clear()
                    playbackRequest = PlaybackRequest(item: detail.item, startTicks: 0)
                } else {
                    detailItem = detail.item
                }
            }
        }
    }

    /// Resolve deep link — prefer in-memory ID (warm launch), fall back to UserDefaults
    /// buffer written by onOpenURL before this view appeared (cold launch).
    func openPendingDeepLink(authManager: AuthManager, mediaRepo: MediaRepository) {
        let pendingID = deepLinkItemID
            ?? UserDefaults.standard.string(forKey: "arcfin.pendingPlayID")
        if let id = pendingID {
            UserDefaults.standard.removeObject(forKey: "arcfin.pendingPlayID")
            openDeepLinkItem(id: id, authManager: authManager, mediaRepo: mediaRepo)
        }
    }

    /// The Resume Watching control: plays the most recent title straight away.
    func resumeLatest(mediaRepo: MediaRepository) {
        guard let item = mediaRepo.continueWatching.first ?? mediaRepo.nextUp.first else { return }
        UserDefaults.standard.removeObject(forKey: "arcfin.pendingResume")
        playbackRequest = PlaybackRequest(item: item, startTicks: item.userData?.playbackPositionTicks ?? 0)
    }

    /// Siri's Play, a SharePlay title and the web app's Play On: straight into the player.
    func playPendingWatch(authManager: AuthManager) {
        guard let cred = authManager.state.credential, let pending = WatchRoute.takePending() else { return }
        let header = authManager.authClient.authHeader(token: cred.accessToken)
        Task {
            if let request = await WatchRoute.resolve(id: pending.id, startTicks: pending.startTicks,
                                                      credential: cred, authHeader: header) {
                playbackRequest = request
            }
        }
    }

    /// The library's own copy when the server has the title, even where Seerr hasn't caught up
    /// yet; the title's page when it's already requested, there's no Seerr to request from, or
    /// this Seerr account can't request it; otherwise the request sheet.
    func openSeerrShelfItem(_ item: SeerrItem, authManager: AuthManager, seerrRepo: SeerrRepository) {
        Task {
            if let local = await libraryCopy(of: item, authManager: authManager) {
                detailItem = local
            } else if seerrRepo.isConfigured, !seerrRepo.isRequested(item), seerrRepo.mayRequest(item.mediaType) {
                seerrRequestItem = item
            } else {
                seerrDetailItem = item
            }
        }
    }

    func libraryCopy(of item: SeerrItem, authManager: AuthManager) async -> MediaItem? {
        guard let credential = authManager.state.credential else { return nil }
        let header = authManager.authClient.authHeader(token: credential.accessToken)
        return try? await JellyfinMediaClient().findItem(
            credential: credential, authHeader: header, tmdbId: item.id, isSeries: item.mediaType == .tv,
            title: item.title, year: item.year.flatMap { Int($0.prefix(4)) })
    }

    // MARK: - Hero trailer

    /// Whether `item` has a local trailer indexed on the server, resolved to a real playable
    /// stream URL the same way the main player does — reusing getPlaybackInfo rather than
    /// hand-building a stream URL, since it already handles direct-play vs transcode
    /// negotiation correctly. Nil when there's none or the task was cancelled.
    static func heroTrailerURL(for item: MediaItem, credential: ServerCredential, authHeader: String) async -> URL? {
        await trailerURL(itemID: item.id, credential: credential, authHeader: authHeader)
    }

    static func trailerURL(itemID: String, credential: ServerCredential, authHeader: String) async -> URL? {
        let log = Telemetry.logger(category: "HeroVideoBackdrop")
        let client = JellyfinMediaClient()
        let trailer: MediaItem?
        do {
            trailer = try await client.getTrailers(credential: credential, authHeader: authHeader, itemId: itemID, limit: 1).first
        } catch {
            log.error("getTrailers failed for \(itemID, privacy: .public): \(Telemetry.summary(error), privacy: .public) \(error, privacy: .private)")
            return nil
        }
        guard let trailer, !Task.isCancelled else {
            log.debug("no local trailer indexed for \(itemID, privacy: .public)")
            return nil
        }
        let info: JellyfinPlaybackInfo
        do {
            info = try await client.getPlaybackInfo(credential: credential, authHeader: authHeader, itemId: trailer.id)
        } catch {
            log.error("getPlaybackInfo failed for trailer \(trailer.id, privacy: .public): \(Telemetry.summary(error), privacy: .public) \(error, privacy: .private)")
            return nil
        }
        return info.playURL
    }
}

/// A shelf opened in full from its See All button.
struct SeeAllShelf: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let items: [MediaItem]
    var isLandscape: Bool = false
}
