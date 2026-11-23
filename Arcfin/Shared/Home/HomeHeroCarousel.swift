// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI
import AuthCore

/// The rotating hero at the top of Home on iPhone, iPad and Mac, with each slide's trailer.
@MainActor @Observable
final class HomeHeroCarousel {
    var index: Int = 0
    // Keyed by hero item index — only the current slide's trailer is ever fetched/played,
    // and only after a short delay once it's actually the one on screen (see
    // loadVideoBackdrop), so swiping past several slides quickly doesn't fire off a
    // burst of trailer lookups + stream negotiations for slides nobody paused on.
    private(set) var videoBackdropIndex: Int?
    private(set) var videoBackdropURL: URL?
    private var videoBackdropTask: Task<Void, Never>?
    /// The rotation (and the trailer fetch each new slide starts) only runs while Home is
    /// actually on screen: the timer kept firing behind other tabs, pushed screens and a
    /// backgrounded app, loading hero trailers nobody could see.
    var isHomeVisible = false { didSet { if !isShowing { stopVideoBackdrop() } } }
    /// Something over Home that onDisappear doesn't report: a title's page, a sheet, the
    /// player (a full-screen cover, or a Mac's own window).
    var isCovered = false { didSet { if !isShowing { stopVideoBackdrop() } } }
    var isShowing: Bool { isHomeVisible && !isCovered }
    var playbackRequest: HeroPlaybackRequest?

    struct HeroPlaybackRequest: Identifiable, Equatable {
        // Constant, so the next episode plays in the open cover (see PlaybackRequest).
        var id: String { "player" }
        let item: MediaItem
        let startTicks: Int64
    }

    /// 2 Continue Watching + 2 Up Next + 6 Recently Added — deduped in case the same item
    /// shows up in more than one list. TabView's page style only instantiates the current
    /// page plus its immediate neighbors, so this doesn't mean 10 images loading at once —
    /// each poster/backdrop loads lazily as the user actually swipes to it.
    static func items(in mediaRepo: MediaRepository) -> [MediaItem] {
        var items: [MediaItem] = []
        items.append(contentsOf: mediaRepo.continueWatching.prefix(2))
        items.append(contentsOf: mediaRepo.nextUp.prefix(2))
        // The server admin's picks take the place of Recently Added when there are any.
        items.append(contentsOf: mediaRepo.featuredItems.isEmpty ? Array(mediaRepo.recentlyAdded.prefix(6)) : Array(mediaRepo.featuredItems.prefix(8)))
        var seen = Set<String>()
        return items.filter { seen.insert($0.id).inserted }
    }

    /// A series in the hero (Recently Added, an admin's pick) plays its next episode, or its
    /// first: the player can't play the series item itself.
    func play(_ item: MediaItem, authManager: AuthManager) {
        guard item.type == .series else {
            let resumable = (item.userData?.playbackPositionTicks ?? 0) > 0 && !(item.userData?.played ?? false)
            playbackRequest = HeroPlaybackRequest(
                item: item,
                startTicks: resumable ? (item.userData?.playbackPositionTicks ?? 0) : 0
            )
            return
        }
        Task {
            guard let request = await HomeModel.seriesPlayback(item, authManager: authManager) else { return }
            playbackRequest = HeroPlaybackRequest(item: request.item, startTicks: request.startTicks)
        }
    }

    /// The rotation timer's tick.
    func advance(itemCount: Int, isActive: Bool) {
        guard itemCount > 1, isShowing, isActive else { return }
        // A trailer is actively showing for this slide — let loadVideoBackdrop's own
        // 15s timeout advance instead of jumping away mid-playback just because the
        // regular rotation interval happened to land first.
        guard videoBackdropIndex != index else { return }
        withAnimation(DT.Animation.slow) { index = (index + 1) % itemCount }
    }

    /// The hero items are computed live from continueWatching/nextUp/recentlyAdded — a data
    /// refresh can shrink them while index still points past the new end. TabView(selection:)
    /// doesn't clamp that itself, so it asked its internal UICollectionView to scroll to an
    /// index that no longer existed — a hard crash (_validateScrollingTargetIndexPath),
    /// confirmed from a real TestFlight crash log.
    func clamp(toCount newCount: Int) {
        guard index >= newCount else { return }
        // max(0, ...) covers shrinking all the way to zero too, not just "smaller but
        // still non-empty" — 0 is an inert, always-valid value to sit at either way.
        index = max(0, newCount - 1)
    }

    /// Warms the image cache with every hero logo, so flipping between slides shows each one
    /// straight away instead of waiting on a fresh request.
    func prefetchLogos(_ items: [MediaItem], mediaRepo: MediaRepository) {
        mediaRepo.prefetch(urls: items.compactMap { mediaRepo.logoURL(for: $0) })
    }

    private func stopVideoBackdrop() {
        videoBackdropTask?.cancel()
        videoBackdropTask = nil
        videoBackdropURL = nil
        videoBackdropIndex = nil
    }

    /// Fetches (after a short pause, so quickly swiping past several slides doesn't fire a
    /// burst of these) whether the current hero slide has a local trailer indexed on the
    /// server, and if so plays it behind the slide.
    func loadVideoBackdrop(enabled: Bool, authManager: AuthManager, mediaRepo: MediaRepository) {
        videoBackdropTask?.cancel()
        videoBackdropURL = nil
        videoBackdropIndex = nil
        let items = Self.items(in: mediaRepo)
        guard enabled, isShowing, items.indices.contains(index),
              case .authenticated(let credential) = authManager.state
        else { return }
        let item = items[index]
        let index = index
        let authHeader = authManager.authClient.authHeader(token: credential.accessToken)
        videoBackdropTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            guard let url = await HomeModel.heroTrailerURL(for: item, credential: credential, authHeader: authHeader)
            else { return }
            guard !Task.isCancelled, self.index == index else { return }
            withAnimation(DT.Animation.motion(.easeIn(duration: 0.6))) {
                videoBackdropURL = url
                videoBackdropIndex = index
            }
            // Loops indefinitely otherwise — auto-reverts to the still backdrop after a
            // short preview instead, same idea as tvOS's own featured-app hero rotators.
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled, self.index == index else { return }
            withAnimation(DT.Animation.motion(.easeOut(duration: 0.6))) {
                videoBackdropURL = nil
                videoBackdropIndex = nil
            }
            // The regular rotation timer skips advancing while this slide's trailer is
            // playing (see advance's guard) — advance here instead, right as the
            // trailer ends, rather than leaving the still image sitting until the timer's
            // next regular tick.
            let count = Self.items(in: mediaRepo).count
            if count > 1, isShowing {
                withAnimation(DT.Animation.slow) { self.index = (index + 1) % count }
            }
        }
    }
}
