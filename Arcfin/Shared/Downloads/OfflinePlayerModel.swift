// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import SwiftData
import MediaEngine
import AuthCore
import JellyfinAPI
import SyncEngine
import Persistence
import SwiftVLC

/// A download's playback, saved position, subtitles, skips and controls, shared by the
/// iPhone, iPad and Mac `OfflinePlayerView`.
@MainActor @Observable
final class OfflinePlayerModel {
    let downloadedItem: DownloadedItem

    // Aether first, same as the online PlayerView — handles whatever container/codec the
    // server has, including what used to force VLC here (AVFoundation's mkv/HEVC-tag
    // limitations). Falls back to VLC if Aether itself can't construct or open this file
    // (see loadAndPlay); VLC stays the fallback rather than AVFoundation for the same reason
    // the comment this replaced gave — a downloaded file's container/codec can be anything.
    private(set) var player: any MediaPlayerProtocol = (try? AetherEnginePlayer()) ?? VLCEnginePlayer()
    private(set) var isControlsVisible = true
    @ObservationIgnored private var hideControlsTask: Task<Void, Never>?
    /// VoiceOver is on: hidden controls drop out of the accessibility tree, so they stay up.
    @ObservationIgnored var keepsControlsVisible = false {
        didSet {
            guard keepsControlsVisible else { return }
            hideControlsTask?.cancel()
            isControlsVisible = true
        }
    }
    private(set) var isScrubbing = false
    private(set) var scrubTicks: Double = 0
    private var subtitleCues: [SubtitleCue] = []
    private(set) var currentSubtitleText: String?
    private(set) var selectedSubtitleIndex: Int?
    var showTrackMenu = false
    @ObservationIgnored private var progressSaveTask: Task<Void, Never>?
    private(set) var autoSkipCountdown: PlayerView.AutoActionCountdown?
    @ObservationIgnored private var autoSkipTask: Task<Void, Never>?
    private var autoSkipped: Set<String> = []
    /// Reached Mark as Watched's point in this playback, for Delete After Watching.
    @ObservationIgnored private var finishedHere = false
    var isFillScreen = false
    /// Settings › Playback › When Resuming is Ask, and the answer isn't in yet.
    var isAskingToResume = false
    private(set) var askedResumeTicks: Int64 = 0
    var resumeAnswer: Int64?

    /// Set once the screen closes: a load that finishes after that stops instead of playing.
    @ObservationIgnored private var isClosed = false
    /// Playback has actually started, so there's a real position to save.
    @ObservationIgnored private var hasStarted = false
    /// Neither engine could open the file (missing or damaged).
    private(set) var loadFailed = false

    @ObservationIgnored private var modelContext: ModelContext?
    @ObservationIgnored private var authManager: AuthManager?
    @ObservationIgnored var closePlayer: () -> Void = {}

    init(downloadedItem: DownloadedItem) {
        self.downloadedItem = downloadedItem
    }

    private var dir: URL { DownloadStore.directory(for: downloadedItem.itemId) }

    /// Hands over the environment saving and syncing the position need.
    func attach(modelContext: ModelContext, authManager: AuthManager) {
        self.modelContext = modelContext
        self.authManager = authManager
    }

    // MARK: - Setup

    /// Where to start, or nil while Settings › Playback › When Resuming asks.
    func startTicks(startPositionOverride: Int64?) async -> Int64? {
        let startTicks = await resumeTicks(startPositionOverride: startPositionOverride)
        // Settings › Playback › When Resuming; an explicit Start Over has already decided.
        if startPositionOverride == nil, startTicks > 0 {
            switch ResumeBehavior.current {
            case .startOver:
                return 0
            case .ask:
                askedResumeTicks = startTicks
                isAskingToResume = true
                return nil
            case .resume:
                break
            }
        }
        return startTicks
    }

    static func timeText(_ ticks: Int64) -> String {
        let total = Int(ticks / 10_000_000)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// Whether playback started; false when the screen closed first or the file wouldn't open.
    func loadAndPlay(from startTicks: Int64, enginePreference: PlaybackEngineKind) async -> Bool {
        guard !isClosed else { return false }
        let videoURL = dir.appendingPathComponent(downloadedItem.videoFileName)
        // The engine picked in Settings; Aether otherwise (AVFoundation can't open most
        // downloaded containers, so it isn't offered here).
        if enginePreference == .vlc, !(player is VLCEnginePlayer) {
            player = VLCEnginePlayer()
        }
        AppServices.music.yieldToVideo()
        do {
            try await player.load(url: videoURL, startPositionTicks: startTicks)
        } catch where player is AetherEnginePlayer {
            // A load cut short by closing isn't Aether failing; falling back then would leave
            // a second player going that nothing stops.
            guard !isClosed else { return false }
            // Same runtime fallback as the online PlayerView — DownloadedItem has no stored
            // container/codec metadata to run a real pre-flight check against offline, so
            // this only ever triggers reactively, on an actual Aether load failure.
            player = VLCEnginePlayer()
            do {
                try await player.load(url: videoURL, startPositionTicks: startTicks)
            } catch {
                loadFailed = !isClosed
                return false
            }
        } catch {
            loadFailed = !isClosed
            return false
        }
        guard !isClosed else {
            await player.stop()
            return false
        }
        await player.play()
        return true
    }

    /// The screen closing: stops the timers and saves where playback got to.
    func close() {
        isClosed = true
        hideControlsTask?.cancel()
        autoSkipTask?.cancel()
        savePosition(final: true)
    }

    /// Where to start: an explicit Start Over, else the local position, unless the server
    /// (asked briefly, so offline starts aren't held up) has a newer one from another device.
    private func resumeTicks(startPositionOverride: Int64?) async -> Int64 {
        if let startPositionOverride { return startPositionOverride }
        let local = downloadedItem.playbackPositionTicks
        // Unsynced local progress is the newest there is.
        guard !downloadedItem.needsSync, let authManager,
              let credential = authManager.profiles.first(where: {
                  $0.id.uuidString == downloadedItem.serverId && $0.userID == downloadedItem.userId
              })
        else { return local }
        let header = authManager.authClient.authHeader(token: credential.accessToken)
        let itemId = downloadedItem.itemId
        // Whichever finishes first: the server's answer, or nil after 2.5 seconds.
        let server: UserData? = await withTaskGroup(of: UserData?.self) { group in
            group.addTask {
                let data = try? await JellyfinMediaClient().getUserData(credential: credential, authHeader: header, itemId: itemId)
                return data ?? nil
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(2.5))
                return nil
            }
            let first = await group.next()
            group.cancelAll()
            return first ?? nil
        }
        guard let server else { return local }
        if server.played && server.playbackPositionTicks == 0 { return local }
        return server.playbackPositionTicks
    }

    func startProgressSaving() {
        guard !isClosed else { return }
        progressSaveTask?.cancel()
        progressSaveTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { return }
                savePosition(final: false)
            }
        }
    }

    func savePosition(final: Bool) {
        if final { progressSaveTask?.cancel() }
        // Before playback has started the position is still 0, which saved as a newer local
        // change would overwrite the server's resume point.
        guard hasStarted, player.durationTicks > 0 else { return }
        downloadedItem.playbackPositionTicks = player.positionTicks
        // Settings › Playback › Mark as Watched, with Jellyfin's own 90% for Server Default.
        // Only ever set here, never cleared: watching a finished title again doesn't make it
        // unwatched, on the server either.
        if player.durationTicks > 0 {
            let seconds = Double(player.positionTicks) / 10_000_000
            let duration = Double(player.durationTicks) / 10_000_000
            let threshold = WatchedThreshold.current
            let reached = threshold == .server
                ? seconds / duration >= 0.9
                : threshold.isReached(seconds: seconds, duration: duration, creditsStart: downloadedItem.creditsStartSeconds)
            if reached {
                downloadedItem.played = true
                finishedHere = true
            }
        }
        // Picked up by OfflineProgressSync once the app's back online — this is the only
        // record that playback happened at all while offline.
        downloadedItem.needsSync = true
        downloadedItem.progressChangedAt = Date()
        try? modelContext?.save()
        if final { syncNow() }
    }

    /// Hands the position to the server right away when it's reachable; otherwise it waits
    /// for the next sync (coming back online, the app reopening).
    private func syncNow() {
        guard let authManager, let modelContext else { return }
        let profiles = authManager.profiles
        let authClient = authManager.authClient
        let context = modelContext
        Task {
            await OfflineProgressSync.syncPending(
                modelContext: context, profiles: profiles,
                authHeader: { authClient.authHeader(token: $0.accessToken) }
            )
        }
    }

    // MARK: - Events from the view

    func positionChanged(to ticks: Int64) {
        updateSubtitleText(forTicks: ticks)
        autoSkipIfNeeded(positionTicks: ticks)
    }

    func statusChanged(to status: PlaybackStatus, deleteAfterWatching: Bool, downloadManager: DownloadManager) {
        if status == .playing {
            hasStarted = true
            scheduleAutoHide()
        }
        if status == .ended {
            savePosition(final: true)
            // The player's end can come early (a converted file cut short), so only a title
            // watched to the end in this playback goes: one watched before it was downloaded
            // is already marked watched.
            if deleteAfterWatching && finishedHere {
                downloadManager.markForDeletionAfterWatching(itemId: downloadedItem.itemId)
            }
            closePlayer()
        }
    }

    func applyFillScreen() {
        if let vlcEngine = player as? VLCEnginePlayer {
            vlcEngine.vlcPlayer.aspectRatio = isFillScreen ? .fill : .default
        } else if let aetherEngine = player as? AetherEnginePlayer {
            aetherEngine.isFillScreen = isFillScreen
        }
    }

    // MARK: - Subtitles

    func loadSubtitles(index: Int?) {
        selectedSubtitleIndex = index
        guard let index, downloadedItem.subtitleFileNames.indices.contains(index) else {
            subtitleCues = []
            currentSubtitleText = nil
            return
        }
        let fileURL = dir.appendingPathComponent(downloadedItem.subtitleFileNames[index])
        subtitleCues = SubtitleLoader.loadCues(fileURL: fileURL)
    }

    private func updateSubtitleText(forTicks ticks: Int64) {
        let text = subtitleCues.isEmpty ? nil : SubtitleLoader.cue(at: Double(ticks) / 10_000_000, in: subtitleCues)
        // Only on a change: the screen reads it, and this runs on every tick.
        if text != currentSubtitleText { currentSubtitleText = text }
    }

    // MARK: - Skipping segments

    var currentSkippable: (kind: String, label: String, span: ClosedRange<Double>)? {
        let seconds = Double(shownTicks) / 10_000_000
        guard seconds > 0.5 else { return nil }
        let segments = downloadedItem.skipSegments
        // Recap ("previously on") is the cold open ahead of the intro, so it's checked first.
        if let span = segments.recap, span.contains(seconds) { return ("recap", String(localized: "Skip Recap"), span) }
        if let span = segments.intro, span.contains(seconds) { return ("intro", String(localized: "Skip Intro"), span) }
        if let span = segments.credits, span.contains(seconds) { return ("credits", String(localized: "Skip Credits"), span) }
        if let span = segments.preview, span.contains(seconds) { return ("preview", String(localized: "Skip Preview"), span) }
        if let span = segments.commercials.first(where: { $0.contains(seconds) }) {
            return ("commercial", String(localized: "Skip Ad"), span)
        }
        return nil
    }

    /// The same Skip Intro, Recap and Credits settings, and countdown, as streaming.
    private func autoSkipIfNeeded(positionTicks: Int64) {
        let seconds = Double(positionTicks) / 10_000_000
        let segments = downloadedItem.skipSegments
        let defaults = UserDefaults.standard
        // Each ad break skips once, by itself, like the other segments.
        if defaults.bool(forKey: "skipCommercials"),
           let span = segments.commercials.first(where: { $0.contains(seconds) }),
           autoSkipped.insert("commercial@\(span.lowerBound)").inserted {
            startAutoSkip(kind: "commercial")
            return
        }
        for (kind, span, enabled) in [
            ("recap", segments.recap, defaults.bool(forKey: "skipRecap")),
            ("intro", segments.intro, defaults.bool(forKey: "skipIntro")),
            ("credits", segments.credits, defaults.bool(forKey: "skipCredits")),
        ] {
            guard enabled, let span, span.contains(seconds), !autoSkipped.contains(kind) else { continue }
            autoSkipped.insert(kind)
            startAutoSkip(kind: kind)
            return
        }
    }

    private func startAutoSkip(kind: String) {
        autoSkipTask?.cancel()
        let countdown = PlayerView.AutoActionCountdown(kind: kind, startedAt: Date(), seconds: PlayerView.autoActionSeconds)
        autoSkipCountdown = countdown
        autoSkipTask = Task {
            try? await Task.sleep(for: .seconds(countdown.seconds))
            guard !Task.isCancelled, autoSkipCountdown == countdown else { return }
            autoSkipCountdown = nil
            // Seeking out of the segment, or skipping it by hand, calls the skip off.
            guard let current = currentSkippable, current.kind == kind else { return }
            skip(kind: kind, span: current.span)
        }
    }

    /// The Skip button, tapped by hand.
    func skipNow(kind: String, span: ClosedRange<Double>) {
        autoSkipCountdown = nil
        skip(kind: kind, span: span)
    }

    /// Past the end of a segment. Credits or a preview running to the end finish the title;
    /// credits with more after them (a mid-credits scene) seek to it.
    private func skip(kind: String, span: ClosedRange<Double>) {
        let duration = Double(player.durationTicks) / 10_000_000
        let endsTitle = (kind == "credits" || kind == "preview") && (duration == 0 || span.upperBound >= duration - 5)
        if endsTitle {
            savePosition(final: true)
            closePlayer()
        } else {
            Task { await player.seek(to: Int64(span.upperBound * 10_000_000)) }
        }
    }

    // MARK: - Trickplay

    func trickplayImage(forTicks ticks: Int64) -> PlatformImage? {
        guard let intervalMs = downloadedItem.trickplayIntervalMs, intervalMs > 0,
              let thumbnailCount = downloadedItem.trickplayThumbnailCount, thumbnailCount > 0,
              let tileWidth = downloadedItem.trickplayTileWidth, tileWidth > 0,
              let tileHeight = downloadedItem.trickplayTileHeight, tileHeight > 0,
              let width = downloadedItem.trickplayWidth, let height = downloadedItem.trickplayHeight
        else { return nil }
        let positionMs = Int(Double(ticks) / 10_000)
        let thumbIndex = min(max(positionMs / intervalMs, 0), thumbnailCount - 1)
        let gridSize = max(tileWidth * tileHeight, 1)
        let tileIndex = thumbIndex / gridSize
        let indexInTile = thumbIndex % gridSize
        let row = indexInTile / tileWidth
        let col = indexInTile % tileWidth
        guard downloadedItem.trickplayFileNames.indices.contains(tileIndex),
              let tileImage = PlatformImage.from(contentsOfFile: dir.appendingPathComponent(downloadedItem.trickplayFileNames[tileIndex]).path),
              let cgTile = tileImage.cgImageRepresentation
        else { return nil }
        let cropRect = CGRect(x: col * width, y: row * height, width: width, height: height)
        guard let cropped = cgTile.cropping(to: cropRect) else { return nil }
        return PlatformImage.from(cgImage: cropped)
    }

    // MARK: - Actions

    /// The web app's or the dashboard's playback controls. Track and volume changes are left
    /// to the player that streams from the server.
    func applyRemoteCommand(_ kind: RemoteControl.Kind) {
        let defaults = UserDefaults.standard
        switch kind {
        case .stop: closePlayer()
        case .pause: if player.status == .playing { togglePlayPause() }
        case .unpause: if player.status != .playing { togglePlayPause() }
        case .playPause: togglePlayPause()
        case .seek(let ticks): Task { await player.seek(to: min(max(ticks, 0), player.durationTicks)) }
        case .rewind: seek(by: -((defaults.object(forKey: "skipBackwardSeconds") as? Int) ?? 10))
        case .fastForward: seek(by: (defaults.object(forKey: "skipForwardSeconds") as? Int) ?? 10)
        default: break
        }
    }

    func togglePlayPause() {
        Task { if player.status == .playing { await player.pause() } else { await player.play() } }
        revealControls()
    }

    func seek(by seconds: Int) {
        let newTicks = max(0, player.positionTicks + Int64(seconds) * 10_000_000)
        Task { await player.seek(to: min(newTicks, player.durationTicks)) }
        revealControls()
    }

    func scrub(to fraction: Double) {
        isScrubbing = true
        hideControlsTask?.cancel()
        scrubTicks = Double(player.durationTicks) * fraction
    }

    func endScrub() {
        Task {
            await player.seek(to: Int64(scrubTicks))
            isScrubbing = false
            scheduleAutoHide()
        }
    }

    func toggleControls() {
        withAnimation(DT.Animation.fast) { isControlsVisible.toggle() }
        if isControlsVisible { scheduleAutoHide() }
    }

    /// Shows the controls after something was done (or, on the Mac, the pointer moved) and
    /// restarts the timer that hides them.
    func revealControls() {
        if !isControlsVisible { withAnimation(DT.Animation.fast) { isControlsVisible = true } }
        scheduleAutoHide()
    }

    func scheduleAutoHide() {
        hideControlsTask?.cancel()
        guard !keepsControlsVisible else { return }
        hideControlsTask = Task {
            try? await Task.sleep(for: .seconds(3.5))
            guard !Task.isCancelled, player.status == .playing else { return }
            withAnimation(DT.Animation.fast) { isControlsVisible = false }
        }
    }

    var shownTicks: Int64 { isScrubbing ? Int64(scrubTicks) : player.positionTicks }

    /// The file wouldn't open, or the engine gave up on it part-way.
    var hasFailed: Bool {
        if loadFailed { return true }
        if case .failed = player.status { return true }
        return false
    }

    var remainingLabel: String {
        let remaining = max(player.durationTicks - player.positionTicks, 0)
        return "-" + Self.timeLabel(ticks: remaining)
    }

    static func timeLabel(ticks: Int64) -> String {
        let totalSeconds = Int(Double(ticks) / 10_000_000)
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
