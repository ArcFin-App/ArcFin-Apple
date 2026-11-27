// SPDX-License-Identifier: AGPL-3.0-or-later

import AVFoundation
import AuthCore
import JellyfinAPI
import Network
import Observation
import SwiftUI

/// The Arcs feed: pages of clips from the plugin, the players for the one on screen and its
/// neighbours, and what the person does with each, sent back so the next page fits them better.
@MainActor @Observable
final class ArcsModel {
    enum Phase: Equatable { case loading, ready, empty, unavailable(String?), failed(String?) }

    private(set) var phase: Phase = .loading
    private(set) var availability: ArcsAvailability?
    private(set) var clips: [ArcClip] = []
    var feed: ArcsFeed
    /// The clip on screen.
    var currentID: String? {
        didSet { if oldValue != currentID { currentChanged(from: oldValue) } }
    }
    private(set) var isLoadingMore = false
    /// Paused by a tap (or because another screen is over the feed).
    var isPaused = false { didSet { updatePlayback() } }
    /// The feed's screen is showing: off, nothing plays.
    var isVisible = false { didSet { updatePlayback() } }
    /// A message shown briefly over the feed ("Hidden", "You'll see fewer…").
    var toast: LocalizedStringResource?

    let seriesID: String?
    /// Saved on the device: plays the files, asks the server for nothing.
    let isOffline: Bool
    /// The feed narrowed to a mood; nil for everything.
    private(set) var mood: ArcsMood?
    /// Trailers of titles to request are mixed in: Seerr is set up here and the setting is on.
    var requestsAllowed = false
    /// Request clips play their YouTube trailer: the person's setting, unless the admin turned trailers off.
    var trailersAllowed = true
    private let authManager: AuthManager
    private let client = ArcsClient()
    private let media = JellyfinMediaClient()
    private var cursor: String?
    private var reachedEnd = false
    private var players: [String: ArcPlayback] = [:]
    private var pendingEvents: [ArcEvent] = []
    private var flushTask: Task<Void, Never>?
    private var items: [String: MediaItem] = [:]
    private let pathMonitor = NWPathMonitor()
    private var onExpensiveNetwork = false
    /// The playback audio session is set up once, when the feed first plays.
    private var audioReady = false

    init(authManager: AuthManager, feed: ArcsFeed = .forYou, seriesID: String? = nil, startingWith first: [ArcClip] = [],
         offline: Bool = false) {
        self.authManager = authManager
        self.feed = feed
        self.seriesID = seriesID
        isOffline = offline
        clips = first
        currentID = first.first?.id
        if !first.isEmpty { phase = .ready }
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let expensive = path.status == .satisfied && (path.isExpensive || path.isConstrained)
            Task { @MainActor [weak self] in self?.onExpensiveNetwork = expensive }
        }
        pathMonitor.start(queue: DispatchQueue(label: "arcfin.arcs.path"))
    }

    // MARK: Settings

    private var defaults: UserDefaults { .standard }
    var spoilerSafe: Bool {
        availability?.spoilers == .alwaysSafe || (defaults.object(forKey: ArcsSettings.spoilerSafeKey) as? Bool ?? true)
    }
    var seconds: Int {
        let chosen = defaults.object(forKey: ArcsSettings.clipSecondsKey) as? Int ?? availability?.defaultSeconds ?? 30
        guard let availability else { return chosen }
        return min(max(chosen, availability.minSeconds), availability.maxSeconds)
    }
    var framing: ArcsFraming { ArcsFraming(rawValue: defaults.string(forKey: ArcsSettings.framingKey) ?? "") ?? .fill }
    var loopsAtEnd: Bool { (ArcsClipEnd(rawValue: defaults.string(forKey: ArcsSettings.clipEndKey) ?? "") ?? .loop) == .loop }
    var showsReasons: Bool { defaults.object(forKey: ArcsSettings.showReasonsKey) as? Bool ?? true }
    var canShare: Bool { availability?.sharing != .off }
    private var quality: ArcsClient.Quality {
        switch ArcsDataSaver(rawValue: defaults.string(forKey: ArcsSettings.dataSaverKey) ?? "") ?? .mobile {
        case .always: .low
        case .off:    .high
        case .mobile: onExpensiveNetwork ? .low : .high
        }
    }

    // MARK: Loading

    func load() async {
        if isOffline {
            reachedEnd = true
            phase = clips.isEmpty ? .empty : .ready
            prepareNeighbours()
            updatePlayback()
            return
        }
        guard let (credential, header) = auth() else { return }
        // The page asked for while Home was up: its first scenes are already being made.
        if clips.isEmpty, feed == .forYou, seriesID == nil, mood == nil, let page = ArcsPrefetch.shared.take(profile: credential.id) {
            show(page)
        }
        // The feed and the server's rules at the same time: the server applies its own limits
        // to the feed either way, so waiting for them first only delays the first scene.
        let needsPage = clips.isEmpty || feed != .forYou || seriesID != nil || cursor == nil
        async let feedLoad: Void = needsPage ? (clips.isEmpty ? reload() : loadMore()) : ()
        do {
            let availability = try await client.availability(spoilerSafe: defaults.object(forKey: ArcsSettings.spoilerSafeKey) as? Bool ?? true,
                                                             credential: credential, authHeader: header)
            self.availability = availability
            ArcsBadge.shared.unseen = availability.enabled ? availability.unseen : 0
            await feedLoad
            // The first page went out before the server's rules were known; a later page follows them.
            if !availability.requests { requestsAllowed = false }
            if !availability.youTubeTrailers { trailersAllowed = false }
            guard availability.enabled else {
                stopAll()
                phase = .unavailable(nil)
                return
            }
        } catch let error as PickTogetherError where error.status == 403 || error.status == 404 {
            await feedLoad
            stopAll()
            phase = .unavailable(error.message)
            return
        } catch {
            await feedLoad
            if clips.isEmpty { phase = .failed(nil) }
            return
        }
        updatePlayback()
    }

    private func show(_ page: ArcsPage) {
        clips = page.clips
        cursor = page.cursor
        reachedEnd = page.cursor == nil || page.clips.isEmpty
        phase = clips.isEmpty ? .empty : .ready
        currentID = clips.first?.id
    }

    private func stopAll() {
        for player in players.values { player.stop() }
        players = [:]
    }

    /// From the top, for a new feed or a pull to refresh.
    func reload() async {
        flush()
        for player in players.values { player.stop() }
        players = [:]
        cursor = nil
        reachedEnd = false
        let keep = clips.first.map { [$0] } ?? []
        clips = feed == .liked ? keep : []
        if clips.isEmpty { phase = .loading }
        await loadMore()
        if currentID == nil || !clips.contains(where: { $0.id == currentID }) { currentID = clips.first?.id }
        updatePlayback()
    }

    func switchMood(to mood: ArcsMood?) {
        guard mood != self.mood else { return }
        self.mood = mood
        clips = []
        currentID = nil
        Task { await reload() }
    }

    func switchFeed(to feed: ArcsFeed) {
        guard feed != self.feed else { return }
        self.feed = feed
        clips = []
        currentID = nil
        Task { await reload() }
    }

    func loadMore() async {
        guard !isLoadingMore, !reachedEnd, let (credential, header) = auth() else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await client.feed(feed, cursor: cursor, spoilerSafe: spoilerSafe, seconds: seconds, seriesID: seriesID,
                                             exclude: clips.map(\.id), quality: quality, mood: mood,
                                             requests: requestsAllowed && feed == .forYou && seriesID == nil,
                                             credential: credential, authHeader: header)
            let known = Set(clips.map(\.id))
            clips.append(contentsOf: page.clips.filter { !known.contains($0.id) })
            cursor = page.cursor
            reachedEnd = page.cursor == nil || page.clips.isEmpty
            phase = clips.isEmpty ? .empty : .ready
            if currentID == nil { currentID = clips.first?.id }
            prepareNeighbours()
        } catch let error as PickTogetherError where error.status == 403 {
            phase = .unavailable(error.message)
        } catch {
            if clips.isEmpty { phase = .failed(nil) }
        }
    }

    // MARK: Players

    private var currentIndex: Int? { clips.firstIndex { $0.id == currentID } }

    /// The clip's player, if it's one of those kept ready. Views only read: the model makes them.
    func playback(for clip: ArcClip) -> ArcPlayback? { players[clip.id] }

    /// The clip's player, made the first time it's asked for.
    private func player(for clip: ArcClip) -> ArcPlayback? {
        if let existing = players[clip.id] { return existing }
        // A title to request plays its trailer in its own player.
        guard !clip.isRequest, let credential = authManager.state.credential else { return nil }
        let saved = ArcsOfflineStore.shared.localURL(for: clip)
        guard let url = saved ?? (isOffline ? nil : ArcsClient.streamURL(for: clip, seconds: seconds, quality: quality, baseURL: credential.baseURL)) else { return nil }
        let playback = ArcPlayback(clipID: clip.id, url: url, authHeader: authManager.authClient.authHeader(token: credential.accessToken),
                                   expectedSeconds: clip.seconds)
        playback.loopsAtEnd = loopsAtEnd
        playback.onEnd = { [weak self] in self?.advance() }
        players[clip.id] = playback
        return playback
    }

    /// The one on screen, the next three and the one before: the rest are let go. Opening the next
    /// ones also has the server start making them, so a fast swipe finds them ready.
    private func prepareNeighbours() {
        guard let index = currentIndex else { return }
        let keep = Set(clips[max(0, index - 1)..<min(clips.count, index + 4)].map(\.id))
        for (id, player) in players where !keep.contains(id) {
            player.stop()
            players[id] = nil
        }
        for clip in clips where keep.contains(clip.id) { _ = player(for: clip) }
    }

    /// Sent scenes counted off the badge once they're watched.
    private var seenSent: Set<String> = []

    private func currentChanged(from old: String?) {
        if let id = currentID, let clip = clips.first(where: { $0.id == id }), clip.sentBy != nil, seenSent.insert(id).inserted {
            ArcsBadge.shared.unseen = max(0, ArcsBadge.shared.unseen - 1)
        }
        if let old, let clip = clips.first(where: { $0.id == old }), let player = players[old] {
            record(player.loops > 0 ? .rewatch : .view, clip, watched: player.loops > 0 ? player.duration : player.furthest)
            player.reset()
        }
        isPaused = false
        prepareNeighbours()
        updatePlayback()
        if let index = currentIndex, index >= clips.count - 4 { Task { await loadMore() } }
    }

    private func updatePlayback() {
        for (id, player) in players where id != currentID { player.pause() }
        guard let id = currentID, let player = players[id] else { return }
        if isVisible && !isPaused {
            prepareAudio()
            player.play()
        } else {
            player.pause()
        }
    }

    /// The clip ended with Play It Again off: on to the next.
    func advance() {
        guard let index = currentIndex, index + 1 < clips.count else { return }
        withAnimation { currentID = clips[index + 1].id }
    }

    /// The clip takes the audio, and music stops. AVAudioSession's calls block, so they run off
    /// the main thread (Xcode flags them there), and only once rather than at every play.
    private func prepareAudio() {
        if AppServices.music.isPlaying { AppServices.music.pause() }
        guard !audioReady else { return }
        audioReady = true
        Task.detached(priority: .userInitiated) {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try? AVAudioSession.sharedInstance().setActive(true)
        }
    }

    /// Leaving the screen for good: the views are counted and every player let go.
    func close() {
        if let id = currentID, let clip = clips.first(where: { $0.id == id }), let player = players[id] {
            record(player.loops > 0 ? .rewatch : .view, clip, watched: player.loops > 0 ? player.duration : player.furthest)
        }
        flush()
        for player in players.values { player.stop() }
        players = [:]
        pathMonitor.cancel()
    }

    // MARK: Actions

    func toggleLike(_ clip: ArcClip) {
        update(clip.id) {
            $0.liked.toggle()
            $0.likeCount = max(0, $0.likeCount + ($0.liked ? 1 : -1))
            if $0.liked { $0.disliked = false }
        }
        guard let updated = clips.first(where: { $0.id == clip.id }) else { return }
        record(updated.liked ? .like : .unlike, updated)
    }

    /// Double tap: only ever likes, as a second double tap on a liked clip shouldn't take it back.
    func like(_ clip: ArcClip) {
        guard clips.first(where: { $0.id == clip.id })?.liked == false else { return }
        toggleLike(clip)
    }

    func toggleDislike(_ clip: ArcClip) {
        update(clip.id) {
            $0.disliked.toggle()
            if $0.disliked, $0.liked { $0.liked = false; $0.likeCount = max(0, $0.likeCount - 1) }
        }
        guard let updated = clips.first(where: { $0.id == clip.id }) else { return }
        record(updated.disliked ? .dislike : .undislike, updated)
        if updated.disliked {
            toast = "You'll see fewer scenes like this."
            advance()
        }
    }

    func toggleFavorite(_ clip: ArcClip) {
        guard let (credential, header) = auth() else { return }
        let favorite = !clip.isFavorite
        updateAll(itemID: clip.itemId) { $0.isFavorite = favorite }
        HapticManager.impact(.light)
        Task {
            do {
                try await media.markFavorite(credential: credential, authHeader: header, itemId: clip.itemId, favorite: favorite)
            } catch {
                updateAll(itemID: clip.itemId) { $0.isFavorite = !favorite }
            }
        }
    }

    func markWatched(_ clip: ArcClip) {
        guard let (credential, header) = auth() else { return }
        Task { try? await media.markWatched(credential: credential, authHeader: header, itemId: clip.itemId, watched: true) }
        toast = "Marked as Watched"
    }

    /// Hide, Fewer or Not Now: that title's other clips leave the feed straight away.
    func keepOut(_ clip: ArcClip, _ kind: ArcEventKind) {
        record(kind, clip)
        switch kind {
        case .hide:            toast = "Hidden. Undo it in Settings › Arcs › Hidden Titles."
        case .fewerFromSeries: toast = "You'll see fewer scenes from this."
        case .notNow:          toast = "You won't see this for a week."
        case .report:          toast = "Thanks. This scene won't be shown again."
        default:               break
        }
        let title = clip.titleID
        // A report is about this scene only; the others are about the whole title.
        let removing = kind == .report ? [] : clips.filter { $0.titleID == title && $0.id != clip.id }.map(\.id)
        // Fewer leaves this one playing; the rest move on from it.
        if kind != .fewerFromSeries { advance() }
        let ahead = Set(removing).subtracting([currentID ?? ""])
        clips.removeAll { ahead.contains($0.id) }
        for id in ahead { players[id]?.stop(); players[id] = nil }
        prepareNeighbours()
    }

    func noteShared(_ clip: ArcClip) { record(.share, clip) }
    func noteWatchFromHere(_ clip: ArcClip) { record(.watchFromHere, clip) }
    func noteStartEpisode(_ clip: ArcClip) { record(.startEpisode, clip) }
    func noteRequested(_ clip: ArcClip) { record(.request, clip) }

    /// A quick reaction; the same one again takes it back.
    func react(_ clip: ArcClip, _ reaction: ArcReaction) {
        let next: ArcReaction? = clip.myReaction == reaction ? nil : reaction
        update(clip.id) {
            if let old = $0.myReaction { $0.reactions[old.rawValue] = max(0, ($0.reactions[old.rawValue] ?? 0) - 1) }
            $0.myReaction = next
            if let next { $0.reactions[next.rawValue] = ($0.reactions[next.rawValue] ?? 0) + 1 }
        }
        HapticManager.impact(.light)
        guard let updated = clips.first(where: { $0.id == clip.id }) else { return }
        pendingEvents.append(ArcEvent(clip: updated, kind: .react, feed: feed, reaction: next?.rawValue ?? "none"))
        flush()
    }

    /// The people on this server a scene can be sent to.
    func people() async -> [ArcPerson] {
        guard let (credential, header) = auth() else { return [] }
        return (try? await client.people(credential: credential, authHeader: header)) ?? []
    }

    /// Sends a scene to someone; a message to show if it didn't go.
    func send(_ clip: ArcClip, to person: ArcPerson, note: String) async -> String? {
        guard let (credential, header) = auth() else { return String(localized: "Couldn't send this scene.") }
        do {
            let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
            try await client.send(clipID: clip.id, to: person.id, note: trimmed.isEmpty ? nil : String(trimmed.prefix(140)),
                                  credential: credential, authHeader: header)
            toast = "Sent"
            return nil
        } catch let error as PickTogetherError {
            return error.message ?? String(localized: "Couldn't send this scene.")
        } catch {
            return String(localized: "Couldn't send this scene.")
        }
    }
    func noteOpenedTitle(_ clip: ArcClip) { record(.openTitle, clip) }

    /// The film or episode, for its page, the player and the playlist sheet.
    func mediaItem(for clip: ArcClip) async -> MediaItem? {
        if let item = items[clip.itemId] { return item }
        guard let (credential, header) = auth(),
              let detail = try? await media.getItemDetail(credential: credential, authHeader: header, itemId: clip.itemId) else { return nil }
        items[clip.itemId] = detail.item
        return detail.item
    }

    func seriesItem(for clip: ArcClip) async -> MediaItem? {
        guard let seriesID = clip.seriesId else { return await mediaItem(for: clip) }
        if let item = items[seriesID] { return item }
        guard let (credential, header) = auth(),
              let detail = try? await media.getItemDetail(credential: credential, authHeader: header, itemId: seriesID) else { return nil }
        items[seriesID] = detail.item
        return detail.item
    }

    // MARK: Events

    private func record(_ kind: ArcEventKind, _ clip: ArcClip, watched: Double? = nil) {
        // A swipe straight past before anything showed isn't a view.
        if kind == .view, (watched ?? 0) < 0.3 { return }
        pendingEvents.append(ArcEvent(clip: clip, kind: kind, watchedSeconds: watched, feed: feed))
        // Likes and the like count for the next page at once; views can wait for a few more.
        if kind != .view || pendingEvents.count >= 5 { flush() } else { scheduleFlush() }
    }

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    private func flush() {
        flushTask?.cancel()
        flushTask = nil
        guard !pendingEvents.isEmpty, let (credential, header) = auth() else { return }
        let events = pendingEvents
        pendingEvents = []
        Task { try? await client.send(events, credential: credential, authHeader: header) }
    }

    // MARK: Helpers

    private func update(_ id: String, _ change: (inout ArcClip) -> Void) {
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return }
        change(&clips[index])
    }

    private func updateAll(itemID: String, _ change: (inout ArcClip) -> Void) {
        for index in clips.indices where clips[index].itemId == itemID { change(&clips[index]) }
    }

    func auth() -> (ServerCredential, String)? {
        guard let credential = authManager.state.credential else { return nil }
        return (credential, authManager.authClient.authHeader(token: credential.accessToken))
    }
}

/// The first page of For You, asked for once the tabs are up, so the server starts making its
/// first scenes before Arcs is opened. Kept for ten minutes, for the profile that asked.
@MainActor
final class ArcsPrefetch {
    static let shared = ArcsPrefetch()

    private var stored: (page: ArcsPage, at: Date, profile: UUID)?
    private var started: Set<UUID> = []

    func start(authManager: AuthManager) {
        guard UserDefaults.standard.object(forKey: ArcsSettings.preloadKey) as? Bool ?? true,
              let credential = authManager.state.credential, !started.contains(credential.id) else { return }
        started.insert(credential.id)
        let header = authManager.authClient.authHeader(token: credential.accessToken)
        let defaults = UserDefaults.standard
        let spoilerSafe = defaults.object(forKey: ArcsSettings.spoilerSafeKey) as? Bool ?? true
        let seconds = defaults.object(forKey: ArcsSettings.clipSecondsKey) as? Int ?? 30
        let quality: ArcsClient.Quality = defaults.string(forKey: ArcsSettings.dataSaverKey) == ArcsDataSaver.always.rawValue ? .low : .high
        Task {
            // After Home's own first load, which matters more.
            try? await Task.sleep(for: .seconds(4))
            guard let page = try? await ArcsClient().feed(.forYou, spoilerSafe: spoilerSafe, seconds: seconds, quality: quality,
                                                          credential: credential, authHeader: header) else {
                started.remove(credential.id)
                return
            }
            stored = (page, .now, credential.id)
        }
    }

    func take(profile: UUID) -> ArcsPage? {
        guard let stored, stored.profile == profile, Date.now.timeIntervalSince(stored.at) < 600 else { return nil }
        self.stored = nil
        return stored.page
    }
}
