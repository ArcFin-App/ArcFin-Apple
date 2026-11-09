// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AVFoundation
import AuthCore
import JellyfinAPI
import MediaEngine
import SwiftVLC
import CastKit

/// A title's playback on the player screen, shared by the iPhone, iPad, Mac and Apple TV
/// `PlayerView`: the engine, what's reported to the server, quality, tracks, skipping, Up Next,
/// SyncPlay, SharePlay and Cast, and whether the controls are showing.
@MainActor @Observable
final class PlayerModel {
    let item: MediaItem
    let startPositionTicks: Int64
    @ObservationIgnored let onPlayNext: (MediaItem) -> Void
    @ObservationIgnored let client = JellyfinMediaClient()
    /// Apple TV hides the controls by fading them out, so they stay focusable (see its PlayerView).
    @ObservationIgnored let hidesControlsByFading: Bool
    /// Play, pause and seek go to the SyncPlay group while in one, rather than to the player.
    @ObservationIgnored let routesThroughSyncPlay: Bool

    @ObservationIgnored var authManager: AuthManager!
    @ObservationIgnored var mediaRepo: MediaRepository!
    @ObservationIgnored var syncPlayManager: SyncPlayManager!
    @ObservationIgnored var sharePlay: SharePlayManager!
    @ObservationIgnored var scenePhase: ScenePhase = .active

    // What the platform's view does around the shared steps. Cleared on teardown, since they
    // hold on to the view.
    @ObservationIgnored var closePlayer: () -> Void = {}
    /// Playback has just started: picture in picture and the like.
    @ObservationIgnored var playbackStarted: () -> Void = {}
    @ObservationIgnored var streamReloaded: () -> Void = {}
    /// The engine is about to be swapped for another, which must take over picture in picture.
    @ObservationIgnored var engineReleased: () -> Void = {}
    @ObservationIgnored var replacementEngineStarting: () async -> Void = {}

    var player: any MediaPlayerProtocol = AVFoundationPlayer()
    var playbackInfo: JellyfinPlaybackInfo?
    var errorMessage: String?
    var isControlsVisible = true
    // A separate flag, not reusing isControlsVisible — the latter also drives
    // allowsHitTesting, which must stay true always on tvOS. This only ever changes
    // opacity, so hit-testing/focusability never turns off and there's never a moment with
    // nothing reachable for the remote to bring back, even while fully invisible.
    var tvControlsHidden = false
    @ObservationIgnored var hideControlsTask: Task<Void, Never>?
    var isScrubbing = false
    var scrubTicks: Double = 0
    @ObservationIgnored var castLoadTask: Task<Void, Never>?
    @ObservationIgnored var sleepTimerTask: Task<Void, Never>?
    var sleepTimerEndsAt: Date?
    var sleepAtEndOfItem = false
    var tracksAtCastStart: (audio: Int?, subtitle: Int?)?
    var castSubtitleTrackIDs: Set<Int> = []
    var syncPlayGroupNameInput = ""
    var isSyncPlayBusy = false
    var quality: VideoQuality
    var selectedAudioIndex: Int?
    var selectedSubtitleIndex: Int?
    var subtitleCues: [SubtitleCue] = []
    var lastSubtitleIndex: Int?
    /// Seconds subtitles are shifted later (+) or earlier (-) — for sources whose subtitle
    /// timing doesn't match the cut being played. Not persisted: it's per-viewing.
    var subtitleDelay: Double = 0
    var currentSubtitleText: String?
    /// Only ever non-nil on AetherEnginePlayer — a native embedded PGS/DVB bitmap track has
    /// no Jellyfin delivery URL for SubtitleLoader to fetch, so this is genuinely new
    /// capability, not a duplicate of the text-cue path above.
    var currentBitmapCue: NativeBitmapCue?
    var trickplayLoader: TrickplayLoader?
    var scrubThumbnail: PlatformImage?
    var lastThumbnailBucket: Int?
    /// Intro, recap, credits and preview spans from the server's segment plugins.
    var segments = SkipSegments()
    /// Segments already skipped automatically, so seeking back into one lets it play.
    var autoSkipped: Set<String> = []
    /// A Skip … Automatically setting about to act: the button shows it filling, then skips.
    var autoSkipCountdown: PlayerView.AutoActionCountdown?
    @ObservationIgnored var autoSkipTask: Task<Void, Never>?
    @ObservationIgnored var progressReportTask: Task<Void, Never>?
    var seekFeedback: PlayerView.SeekFeedback?
    /// Optimistic target of the most recent seek request — player.positionTicks only
    /// updates once the AVPlayer seek actually completes, which lags behind on a slow
    /// server. Rapid skip taps must accumulate on this, not on the stale confirmed
    /// position, or they collapse into far less than the sum requested.
    var pendingSeekTargetTicks: Int64?
    @ObservationIgnored var stallObserver: NSObjectProtocol?
    /// Auto's current cap, nil = uncapped. Only meaningful while `quality == .auto` — a
    /// manual pick never touches this.
    var autoCap: StreamQualityCap?
    var lastSeekAt: Date?
    @ObservationIgnored var autoRecoveryTask: Task<Void, Never>?
    var wasBackgrounded = false
    @ObservationIgnored var foregroundCheckTask: Task<Void, Never>?
    @ObservationIgnored var pictureCheckTask: Task<Void, Never>?
    var lastStallHandledAt: Date?
    var recentStallTimestamps: [Date] = []
    var lastLoadStartedAt: Date?
    /// What setup() is waiting on, shown under the spinner when a start takes a while.
    var loadingStage: String?
    var networkToast: String?
    var chapters: [MediaChapter] = []
    var castMembers: [MediaPerson] = []
    /// The version picked for a title with several (Merge Versions); nil plays the server's first.
    var selectedMediaSourceId: String?
    var moreLikeThis: [MediaItem] = []
    var currentLikes: Bool?
    var showMoreLikeThis = false
    var moreLikeThisDismissed = false
    var nextEpisode: MediaItem?
    /// The title before this one in the queue or the series, for the Previous button.
    var previousItem: MediaItem?
    var showUpNext = false
    var upNextDismissed = false
    @ObservationIgnored var upNextCountdown: Task<Void, Never>?
    var upNextCountdownState: PlayerView.AutoActionCountdown?
    /// Where playback starts: the resume point, or the beginning under Start Over.
    var resumeFrom: Int64 = 0
    /// Settings › Playback › When Resuming is Ask, and the answer isn't in yet.
    var isAskingToResume = false
    var resumeAnswered = false
    var showStillWatchingPrompt = false
    var pendingAutoAdvanceEpisode: MediaItem?
    @ObservationIgnored var stillWatchingTimeoutTask: Task<Void, Never>?

    @ObservationIgnored let nowPlayingManager = NowPlayingManager()
    // Not PiP-specific — used by videoSurface's own aspect-fill toggle, which is
    // meaningful on tvOS too even though PiP itself isn't available there.
    var isFillScreen = false

    init(item: MediaItem, startPositionTicks: Int64, onPlayNext: @escaping (MediaItem) -> Void,
         hidesControlsByFading: Bool = false, routesThroughSyncPlay: Bool = true) {
        self.item = item
        self.startPositionTicks = startPositionTicks
        self.onPlayNext = onPlayNext
        self.hidesControlsByFading = hidesControlsByFading
        self.routesThroughSyncPlay = routesThroughSyncPlay
        let defaults = UserDefaults.standard
        let mobileQuality = DownloadManager.isOnMobileDataNow
            ? defaults.string(forKey: "mobileVideoQuality").flatMap(VideoQuality.init(rawValue:)) : nil
        quality = mobileQuality ?? VideoQuality(rawValue: defaults.string(forKey: "videoQuality") ?? "") ?? .max
        let behavior = ResumeBehavior.current
        resumeFrom = behavior == .startOver ? 0 : startPositionTicks
        isAskingToResume = behavior == .ask && startPositionTicks > 0
    }

    /// Hands over the environment the shared steps need.
    func attach(authManager: AuthManager, mediaRepo: MediaRepository, syncPlayManager: SyncPlayManager,
                sharePlay: SharePlayManager, scenePhase: ScenePhase) {
        self.authManager = authManager
        self.mediaRepo = mediaRepo
        self.syncPlayManager = syncPlayManager
        self.sharePlay = sharePlay
        self.scenePhase = scenePhase
    }

    private var credential: ServerCredential? { authManager.state.credential }
    private var authHeader: String? {
        credential.map { authManager.authClient.authHeader(token: $0.accessToken) }
    }

    // Settings › Playback, read where the decisions are made.
    private var playbackEnginePreference: PlaybackEngineKind {
        PlaybackEngineKind(rawValue: UserDefaults.standard.string(forKey: "playbackEngine") ?? "") ?? .auto
    }
    private var stillWatchingPromptEnabled: Bool {
        UserDefaults.standard.object(forKey: "stillWatchingPromptEnabled") as? Bool ?? true
    }

    // MARK: - Events from the view

    func positionChanged(from oldValue: Int64, to newValue: Int64) {
        // Every seek path (scrubber, skip buttons, chapters, SyncPlay, auto-skip) shows
        // up as a jump here, so this is where Auto learns a seek just happened.
        if abs(newValue - oldValue) > 30_000_000 { lastSeekAt = Date() }
        updateSubtitleText(forTicks: newValue)
        checkUpNextThreshold(positionTicks: newValue)
        checkMoreLikeThisThreshold(positionTicks: newValue)
        autoSkipIfNeeded(positionTicks: newValue)
        updateNowPlayingInfo()
    }

    func statusChanged(to newStatus: PlaybackStatus) {
        // The receiver is the one playing — any local resume (a load finishing, a seek
        // completing, an interruption ending) would play the same audio twice.
        if newStatus == .playing, CastManager.shared.isConnected {
            Task { await player.pause() }
        }
        handleStatusChange(newStatus)
        updateNowPlayingInfo()
    }

    func scenePhaseChanged(to phase: ScenePhase) {
        scenePhase = phase
        switch phase {
        case .background: wasBackgrounded = true
        case .active where wasBackgrounded:
            wasBackgrounded = false
            checkPlaybackAfterForeground()
        default: break
        }
    }

    func showSharePlayNotice(_ notice: String) {
        sharePlay.notice = nil
        networkToast = notice
        Task {
            try? await Task.sleep(for: .seconds(4))
            if networkToast == notice { networkToast = nil }
        }
    }

    func castPlaybackFinished() {
        // Local playback is paused for the whole cast, so the Up Next countdown (which
        // follows the local position) never fires — the receiver's end-of-item is the
        // signal instead.
        guard CastManager.shared.isConnected, nextEpisode != nil,
              UserDefaults.standard.bool(forKey: "autoPlayNext") else { return }
        playNextEpisode(isAutomatic: true)
    }

    /// Shared by macOS's Up/Down-arrow volume shortcuts and tvOS's remote volume commands
    /// (PlayerView+Gestures.swift) — both platforms drive the active engine's own volume
    /// directly rather than through a system volume surface, since neither has one reachable
    /// from here (macOS has no "hidden MPVolumeView" trick the way iOS does; tvOS's physical
    /// volume buttons don't reach the app at all unless wired up this way).
    func setEngineVolume(_ volume: Float) {
        if let avPlayer = player as? AVFoundationPlayer {
            avPlayer.player.volume = volume
        } else if let vlcEngine = player as? VLCEnginePlayer {
            try? vlcEngine.vlcPlayer.setAudioVolume(Volume(volume))
        } else if let aetherEngine = player as? AetherEnginePlayer {
            aetherEngine.volume = volume
        }
    }

    func applyFillScreen() {
        if let vlcEngine = player as? VLCEnginePlayer {
            vlcEngine.vlcPlayer.aspectRatio = isFillScreen ? .fill : .default
        } else if let aetherEngine = player as? AetherEnginePlayer {
            aetherEngine.isFillScreen = isFillScreen
        }
        // AVFoundation's videoGravity is driven declaratively via videoSurface's
        // isFillScreen param above — no imperative call needed for that branch.
    }

    private func handleStatusChange(_ newStatus: PlaybackStatus) {
        if newStatus == .playing { scheduleAutoHide() }
        if newStatus == .ended { Task { await finishPlayback() } }
        // A failure while loading throws from setup(), which handles it (and Aether's
        // fallback); this is the engine giving up after playback had already started.
        if case .failed = newStatus, loadingStage == nil, errorMessage == nil {
            errorMessage = String(localized: "Playback stopped because the video couldn't be read. Try again, or pick another engine in Settings › Playback.")
        }
    }

    // MARK: - Now Playing / AirPlay metadata

    /// Reflects Cast state too — the local player stays paused for the whole cast session
    /// (see startCasting), so its own `.status` alone would show "paused" the entire time.
    var isEffectivelyPlaying: Bool {
        if CastManager.shared.isConnected { return !CastManager.shared.isPaused }
        return player.status == .playing
    }

    func nowPlayingPlay() {
        if CastManager.shared.isConnected { CastManager.shared.play(); return }
        Task { await player.play() }
    }

    func nowPlayingPause() {
        if CastManager.shared.isConnected { CastManager.shared.pause(); return }
        Task { await player.pause() }
    }

    private func setUpNowPlayingCommandsIfNeeded() {
        nowPlayingManager.configureCommands(
            isPlaying: { [self] in isEffectivelyPlaying },
            onPlay: nowPlayingPlay,
            onPause: nowPlayingPause,
            onSkip: { [self] seconds in seek(by: seconds) },
            onSeek: { [self] seconds in performSeek(to: Int64(seconds * 10_000_000)) },
            onNextTrack: item.type == .episode ? { [self] in playNextEpisode() } : nil
        )
    }

    func updateNowPlayingInfo() {
        let durationSeconds = Double(player.durationTicks) / 10_000_000
        guard durationSeconds > 0 else { return }
        nowPlayingManager.update(
            title: item.name,
            artist: episodeSubtitle,
            duration: durationSeconds,
            elapsed: Double(player.positionTicks) / 10_000_000,
            rate: isEffectivelyPlaying ? player.playbackRate : 0,
            artwork: nowPlayingArtwork
        )
    }

    private static var artworkCache: [String: PlatformImage] = [:]
    private var nowPlayingArtwork: PlatformImage? { Self.artworkCache[item.id] }

    private func fetchAndApplyNowPlayingArtwork() async {
        guard nowPlayingArtwork == nil,
              let url = mediaRepo.imageURL(for: item, type: .primary, fillWidth: 600),
              let data = await URLSession.arcfin.imageData(from: url),
              let image = PlatformImage(data: data)
        else { return }
        // Only the current title's artwork is ever read, so a long session of back-to-back
        // episodes shouldn't keep every previous 600px poster alive in memory.
        if Self.artworkCache.count >= 8 { Self.artworkCache.removeAll() }
        Self.artworkCache[item.id] = image
        updateNowPlayingInfo()
    }

    func handleMenuVisibilityChange(_ isOpen: Bool) {
        if isOpen {
            hideControlsTask?.cancel()
        } else {
            scheduleAutoHide()
        }
    }

    // MARK: - Playback speed

    static let rateOptions: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
    static let lastRateKey = "lastPlaybackRate"

    /// Applies the last picked speed to a freshly loaded stream when Settings → Playback →
    /// Remember Playback Speed is on. The key is written on every pick so turning the
    /// setting on later starts from the speed last used.
    private func applyRememberedRate() async {
        let defaults = UserDefaults.standard
        // Otherwise Settings › Playback › Default Speed.
        let rate = defaults.bool(forKey: "rememberPlaybackSpeed")
            ? defaults.float(forKey: Self.lastRateKey)
            : Float(defaults.object(forKey: "defaultPlaybackSpeed") as? Double ?? 1)
        guard rate > 0, rate != 1 else { return }
        await player.setRate(rate)
    }

    func choosePlaybackRate(_ rate: Float) {
        UserDefaults.standard.set(rate, forKey: Self.lastRateKey)
        Task { await player.setRate(rate) }
    }

    /// One step along the speed menu's options, from whichever is closest to the current speed.
    func stepPlaybackRate(_ direction: Int) {
        let options = Self.rateOptions
        let current = options.indices.min { abs(options[$0] - player.playbackRate) < abs(options[$1] - player.playbackRate) } ?? 2
        choosePlaybackRate(options[min(max(current + direction, 0), options.count - 1)])
    }

    /// Off, or back to the last subtitle shown (the first one when none has been yet).
    func toggleSubtitles() {
        if let current = selectedSubtitleIndex {
            lastSubtitleIndex = current
            changeTrack(subtitleIndex: .some(nil))
        } else if let index = lastSubtitleIndex ?? playbackInfo?.subtitleStreams.first?.index {
            changeTrack(subtitleIndex: .some(index))
        }
    }

    func rateLabel(_ rate: Float) -> String {
        rate == 1.0 ? "Normal" : "\(rate.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", rate) : String(format: "%.2f", rate))×"
    }

    // MARK: - Setup / teardown

    var loadingStatusText: String {
        if let loadingStage { return loadingStage }
        if playbackInfo?.playMethod == .transcode { return "Waiting for the server…" }
        return "Buffering…"
    }

    private var decodesNatively: Bool { player is AetherEnginePlayer || player is VLCEnginePlayer }

    /// Aether numbers its tracks by stream index, the same numbers Jellyfin's streams carry.
    var audioDescriptionIndices: Set<Int> {
        Set(player.availableAudioTracks.filter(\.isAudioDescription).map(\.id))
    }

    /// The AVFoundation/VLC split Auto used before Aether existed — now only reached when
    /// Aether itself fails to construct or load a source (see setup()'s runtime fallback).
    private func legacyEnginePlayer(container: String?, videoStream: JellyfinMediaStream?) -> any MediaPlayerProtocol {
        switch PlaybackEngineSelector.legacyFallback(container: container, videoStream: videoStream) {
        case .vlc: return VLCEnginePlayer()
        default: return AVFoundationPlayer()
        }
    }

    func setup() async {
        guard let credential, let authHeader else {
            errorMessage = "Not signed in."
            return
        }
        guard !item.isVirtual else {
            if let premiere = item.premiereDate, premiere > Date() {
                errorMessage = "This episode airs \(premiere.formatted(.dateTime.day().month(.wide))). It'll play once it's on your server."
            } else {
                errorMessage = "This episode isn't on your server."
            }
            return
        }
        if quality == .auto {
            loadingStage = "Checking your connection…"
            await primeAutoLadder(credential: credential, authHeader: authHeader)
        }
        loadingStage = "Contacting the server…"
        do {
            // The engine is picked before asking the server how to stream, because the answer
            // depends on it: Aether and VLC take the file as is, AVFoundation needs it repackaged.
            // .choose always resolves Auto down to a concrete engine — three outcomes here.
            let engine = PlaybackEngineSelector.choose(
                preference: playbackEnginePreference, container: nil, videoStream: nil
            )
            switch engine {
            case .aether, .auto:
                if !(player is AetherEnginePlayer) {
                    // init() throws — a construction failure is just another "Aether can't
                    // serve this session" case, handled by the exact same fallback path a
                    // load() failure goes through below.
                    player = (try? AetherEnginePlayer()) ?? VLCEnginePlayer()
                }
            case .vlc:
                if !(player is VLCEnginePlayer) { player = VLCEnginePlayer() }
            case .avFoundation:
                if !(player is AVFoundationPlayer) { player = AVFoundationPlayer() }
            }
            var info = try await client.getPlaybackInfo(
                credential: credential, authHeader: authHeader, itemId: item.id, mediaSourceId: selectedMediaSourceId,
                quality: qualityCap(for: quality), nativeDecoder: decodesNatively
            )
            selectedAudioIndex = info.defaultAudioStreamIndex
            // The server only marks a subtitle default when one's flagged default/forced
            // there — most libraries don't have that set, so "Show Subtitles by Default"
            // needs its own fallback to the first available track rather than staying nil.
            if let serverDefault = info.defaultSubtitleStreamIndex {
                selectedSubtitleIndex = serverDefault
            } else if UserDefaults.standard.bool(forKey: "subtitleDefault") {
                selectedSubtitleIndex = info.subtitleStreams.first?.index
            } else {
                selectedSubtitleIndex = nil
            }
            // Settings > Playback's global language defaults only steer this very first
            // pick, and only when a track in that language actually exists — a later
            // change always goes through changeTrack()/reload() instead.
            var languagePreferenceApplied = false
            let preferredAudioLang = UserDefaults.standard.string(forKey: "preferredAudioLanguage") ?? ""
            if !preferredAudioLang.isEmpty,
               let match = info.audioStreams.first(where: { $0.language == preferredAudioLang }),
               match.index != selectedAudioIndex {
                selectedAudioIndex = match.index
                languagePreferenceApplied = true
            }
            let preferredSubtitleLang = UserDefaults.standard.string(forKey: "preferredSubtitleLanguage") ?? ""
            if !preferredSubtitleLang.isEmpty,
               let match = info.subtitleStreams.first(where: { $0.language == preferredSubtitleLang }),
               match.index != selectedSubtitleIndex {
                selectedSubtitleIndex = match.index
                languagePreferenceApplied = true
            }
            // A show's own remembered choice beats the global defaults above.
            if ShowTrackMemory.isEnabled, item.type == .episode, let seriesId = item.seriesId,
               let memory = ShowTrackMemory.load(seriesID: seriesId) {
                if let language = memory.audio,
                   let match = info.audioStreams.first(where: { $0.language == language }),
                   match.index != selectedAudioIndex {
                    selectedAudioIndex = match.index
                    languagePreferenceApplied = true
                }
                if memory.subtitlesOff {
                    if selectedSubtitleIndex != nil {
                        selectedSubtitleIndex = nil
                        languagePreferenceApplied = true
                    }
                } else if let language = memory.subtitle,
                          let match = info.subtitleStreams.first(where: { $0.language == language }),
                          match.index != selectedSubtitleIndex {
                    selectedSubtitleIndex = match.index
                    languagePreferenceApplied = true
                }
            }
            // Jellyfin negotiates audio/subtitle selection server-side (see changeTrack) —
            // a language default that actually changed the pick needs the same re-fetch
            // with explicit indices before the very first play, not just a local index change.
            if languagePreferenceApplied, let reInfo = try? await client.getPlaybackInfo(
                credential: credential, authHeader: authHeader, itemId: item.id, mediaSourceId: selectedMediaSourceId,
                quality: qualityCap(for: quality),
                audioStreamIndex: selectedAudioIndex, subtitleStreamIndex: selectedSubtitleIndex,
                nativeDecoder: decodesNatively
            ) {
                info = reInfo
            }
            playbackInfo = info
            // PlaybackInfo's own TrickplayInfo field isn't reliably populated by Jellyfin —
            // the general item-detail endpoint's Trickplay field (keyed by MediaSourceId) is
            // what the official apps actually read it from.
            let detail = try? await client.getItemDetail(credential: credential, authHeader: authHeader, itemId: item.id)
            if let trickplay = detail?.trickplay[info.mediaSourceId] ?? info.trickplay {
                trickplayLoader = TrickplayLoader(credential: credential, authHeader: authHeader, client: client, itemId: item.id, info: trickplay)
            }
            chapters = detail?.chapters ?? []
            castMembers = detail?.cast ?? []
            currentLikes = detail?.item.userData?.likes
            await loadSubtitleCues(from: info, credential: credential)
            lastLoadStartedAt = Date()
            loadingStage = info.playMethod == .transcode ? "The server is converting this video…" : "Opening the video…"
            // Auto's pre-flight pick can't catch everything — a runtime load failure on
            // Aether (the exact class of bug we spent real time on this session, where a
            // source's own structure breaks one engine but not another) falls back once to
            // the same AVFoundation/VLC split Auto used before Aether existed, rather than
            // surfacing a hard error over an engine that can't serve this specific source.
            do {
                try await player.load(url: info.playURL, startPositionTicks: resumeFrom)
            } catch where player is AetherEnginePlayer {
                player = legacyEnginePlayer(container: info.container, videoStream: info.videoStream)
                if !decodesNatively {
                    info = try await client.getPlaybackInfo(
                        credential: credential, authHeader: authHeader, itemId: item.id, mediaSourceId: selectedMediaSourceId,
                        quality: qualityCap(for: quality),
                        audioStreamIndex: selectedAudioIndex, subtitleStreamIndex: selectedSubtitleIndex
                    )
                    playbackInfo = info
                    await loadSubtitleCues(from: info, credential: credential)
                }
                try await player.load(url: info.playURL, startPositionTicks: resumeFrom)
            }
            await player.play()
            loadingStage = nil
            await applyRememberedRate()
            sharePlay.playerOpened(item)
            // The preferred or remembered audio language, which a file played as is ignores.
            if selectedAudioIndex != nil { await selectAudioInEngine() }
            // A cast that was already running when this screen opened (autoplay moved on to
            // the next episode) never produces an isConnected change to trigger this.
            if CastManager.shared.isConnected { startCasting() }
            playbackStarted()
            setUpNowPlayingCommandsIfNeeded()
            updateNowPlayingInfo()
            Task { await fetchAndApplyNowPlayingArtwork() }
            await client.reportPlaybackStart(credential: credential, authHeader: authHeader,
                                             itemId: item.id, mediaSourceId: info.mediaSourceId,
                                             positionTicks: resumeFrom)
            startProgressReporting(mediaSourceId: info.mediaSourceId)
            startAutoRecovery()
            watchForMissingPicture()
        } catch {
            errorMessage = "Couldn't start playback: \(error.localizedDescription)"
        }

        segments = await client.getSkipSegments(credential: credential, authHeader: authHeader, itemId: item.id)
        autoSkipped = []

        // A playlist or collection playing through goes by its own order; an episode by the
        // series' order. Next Up wasn't usable here: part-way through an episode it answers
        // with that same episode.
        if PlayQueue.contains(item.id) {
            nextEpisode = PlayQueue.item(after: item.id)
            previousItem = PlayQueue.item(before: item.id)
        } else if item.type == .episode, let seriesId = item.seriesId,
                  let episodes = try? await client.getEpisodes(
                    credential: credential, authHeader: authHeader, seriesId: seriesId, seasonId: nil) {
            // Specials sit outside the run of the show unless one is what's playing.
            let run = item.parentIndexNumber == 0 ? episodes : episodes.filter { $0.parentIndexNumber != 0 }
            if let index = run.firstIndex(where: { $0.id == item.id }) {
                nextEpisode = run.indices.contains(index + 1) ? run[index + 1] : nil
                previousItem = index > 0 ? run[index - 1] : nil
            }
        }

        // Anything with an Up Next card already has something to watch next; the rest (movies,
        // a series finale) get suggestions instead once the credits start. Trailers and other
        // extras don't: the last four minutes would cover most of one.
        moreLikeThis = []
        showMoreLikeThis = false
        moreLikeThisDismissed = false
        if nextEpisode == nil, item.type == .movie || item.type == .episode {
            moreLikeThis = ((try? await client.getSimilarItems(
                credential: credential, authHeader: authHeader, itemId: item.id, limit: 12)) ?? [])
                .filter { $0.id != item.id }
        }
    }

    // MARK: - SyncPlay

    /// Applies a command that came back over the WebSocket — the one and only place local
    /// playback state actually changes in response to SyncPlay, whether this client sent
    /// the original request or another group member did.
    func applySyncPlayCommand(_ command: SyncPlayCommand) {
        switch command.kind {
        case .play:
            Task { await player.play() }
        case .pause:
            Task { await player.pause() }
        case .seek, .stop:
            if let ticks = command.positionTicks {
                Task { await player.seek(to: ticks) }
            }
        }
    }

    func refreshSyncPlayGroups() async {
        guard let credential = authManager.state.credential else { return }
        let authHeader = authManager.authClient.authHeader(token: credential.accessToken)
        await syncPlayManager.refreshGroups(credential: credential, authHeader: authHeader)
    }

    func createSyncPlayGroup() {
        guard let credential = authManager.state.credential else { return }
        let authHeader = authManager.authClient.authHeader(token: credential.accessToken)
        let name = syncPlayGroupNameInput.trimmingCharacters(in: .whitespaces)
        isSyncPlayBusy = true
        Task {
            await syncPlayManager.createGroup(
                credential: credential, authHeader: authHeader, groupName: name,
                itemId: item.id, startPositionTicks: player.positionTicks
            )
            isSyncPlayBusy = false
        }
    }

    func joinSyncPlayGroup(_ group: SyncPlayGroupInfo) {
        guard let credential = authManager.state.credential else { return }
        let authHeader = authManager.authClient.authHeader(token: credential.accessToken)
        isSyncPlayBusy = true
        Task {
            await syncPlayManager.joinGroup(
                group, credential: credential, authHeader: authHeader,
                itemId: item.id, startPositionTicks: player.positionTicks
            )
            isSyncPlayBusy = false
        }
    }

    func leaveSyncPlayGroup() {
        guard let credential = authManager.state.credential else { return }
        let authHeader = authManager.authClient.authHeader(token: credential.accessToken)
        syncPlayManager.leaveGroup(credential: credential, authHeader: authHeader)
    }

    // MARK: - SharePlay

    /// A command from someone else in the call. Applied straight to the player, so it isn't
    /// sent on again.
    func applySharePlayCommand(_ command: SharePlayCommand) {
        guard command.itemId == item.id else { return }
        switch command.kind {
        case .hello:
            sharePlay.send(player.status == .playing ? .play : .pause, itemId: item.id, positionTicks: player.positionTicks)
        case .seek:
            Task { await player.seek(to: command.positionTicks) }
        case .play, .pause:
            Task {
                // Within two seconds is close enough; seeking for less only stutters.
                if abs(player.positionTicks - command.positionTicks) > 20_000_000 {
                    await player.seek(to: command.positionTicks)
                }
                if command.kind == .play { await player.play() } else { await player.pause() }
            }
        }
    }

    /// Someone in the call picked another title.
    func followSharePlay(to itemId: String) {
        guard let credential, let authHeader else { return }
        Task {
            if let next = try? await client.getItemDetail(credential: credential, authHeader: authHeader, itemId: itemId).item {
                onPlayNext(next)
            }
        }
    }

    // MARK: - Chromecast

    /// A Cast session took over — the receiver plays the stream itself, so the local
    /// player pauses rather than playing the same thing twice.
    func startCasting() {
        tracksAtCastStart = (selectedAudioIndex, selectedSubtitleIndex)
        currentSubtitleText = nil
        currentBitmapCue = nil
        Task { await player.pause() }
        // Opened from the casting bar: the receiver is already playing this, so loading it
        // again would jump it back to where the local player happens to be.
        guard CastManager.shared.nowPlayingItemID != item.id else { return }
        loadCast(startSeconds: Double(player.positionTicks) / 10_000_000)
    }

    /// (Re)loads the receiver. A newer call cancels an older in-flight one so two loads can
    /// never both reach the receiver.
    func loadCast(startSeconds: Double) {
        guard let credential, let authHeader else { return }
        castLoadTask?.cancel()
        let posterURL = mediaRepo.imageURL(for: item, type: .primary, fillWidth: 400)
        castLoadTask = Task {
            let info = try? await client.getPlaybackInfo(
                credential: credential, authHeader: authHeader, itemId: item.id, mediaSourceId: selectedMediaSourceId,
                quality: qualityCap(for: quality),
                audioStreamIndex: selectedAudioIndex, subtitleStreamIndex: selectedSubtitleIndex,
                forCast: true
            )
            guard !Task.isCancelled, let url = info?.playURL ?? playbackInfo?.playURL else { return }
            // Text subtitles go to the receiver as sidecar WebVTT tracks; image-based ones
            // have no deliveryUrl and are burned into the transcode by the server instead.
            let tracks = (info ?? playbackInfo)?.subtitleStreams.compactMap { stream -> CastManager.SubtitleTrack? in
                guard let delivery = stream.deliveryUrl,
                      let trackURL = SubtitleLoader.absoluteURL(deliveryUrl: delivery, credential: credential)
                else { return nil }
                return CastManager.SubtitleTrack(
                    id: stream.index, url: trackURL, languageCode: stream.language, name: stream.displayTitle)
            } ?? []
            castSubtitleTrackIDs = Set(tracks.map(\.id))
            CastManager.shared.loadMedia(
                itemID: item.id, streamURL: url, title: item.name, subtitle: nil, posterImageURL: posterURL,
                contentType: castContentType(for: url),
                startPositionSeconds: startSeconds,
                subtitleTracks: tracks,
                activeSubtitleTrackID: tracks.contains { $0.id == selectedSubtitleIndex } ? selectedSubtitleIndex : nil,
                isTransportStreamHLS: url.pathExtension.lowercased() == "m3u8"
            )
        }
    }

    /// Audio is baked into the transcoded stream, so a different track needs a new stream
    /// from the current live position rather than a receiver-side switch.
    func selectCastAudio(index: Int) {
        guard index != selectedAudioIndex else { return }
        selectedAudioIndex = index
        loadCast(startSeconds: CastManager.shared.lastKnownPositionSeconds ?? 0)
    }

    /// Sidecar text tracks switch instantly on the receiver; a track that isn't one (off
    /// is, image-based isn't) needs a new stream with the subtitle burned in.
    func selectCastSubtitle(index: Int?) {
        guard index != selectedSubtitleIndex else { return }
        selectedSubtitleIndex = index
        if index == nil || castSubtitleTrackIDs.contains(index!) {
            CastManager.shared.setActiveSubtitleTrack(id: index)
        } else {
            loadCast(startSeconds: CastManager.shared.lastKnownPositionSeconds ?? 0)
        }
    }

    /// The session ended — pick local playback back up from wherever the receiver had
    /// gotten to. `currentPositionSeconds()` reads the live session and is already nil by
    /// the time this runs (the session is gone), so this uses CastManager's own
    /// continuously-updated `lastKnownPositionSeconds` instead — see its doc comment.
    func resumeLocalPlaybackAfterCast() {
        castLoadTask?.cancel()
        defer { tracksAtCastStart = nil }
        // Tracks picked on the cast dashboard change selectedAudioIndex/selectedSubtitleIndex,
        // but the local player is still on the old stream — reload so it matches what the
        // viewer was just watching.
        if let before = tracksAtCastStart,
           before.audio != selectedAudioIndex || before.subtitle != selectedSubtitleIndex {
            let seconds = CastManager.shared.lastKnownPositionSeconds ?? Double(player.positionTicks) / 10_000_000
            reload(errorContext: "resume after casting", resumeTicks: Int64(seconds * 10_000_000))
            return
        }
        if let seconds = CastManager.shared.lastKnownPositionSeconds {
            Task {
                await player.seek(to: Int64(seconds * 10_000_000))
                await player.play()
            }
        } else {
            Task { await player.play() }
        }
    }

    /// Keyed off the URL, not the source container — an mkv source is served as an HLS
    /// transcode, and labelling that playlist video/mp4 leaves the receiver mis-demuxing it.
    private func castContentType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "m3u8": return "application/x-mpegurl"
        case "mov":  return "video/quicktime"
        default:     return "video/mp4"
        }
    }

    /// The first part of closing: lets SharePlay know and stops every timer.
    func stopTasks() {
        sharePlay.playerClosed(item.id)
        progressReportTask?.cancel()
        autoRecoveryTask?.cancel()
        autoSkipTask?.cancel()
        foregroundCheckTask?.cancel()
        pictureCheckTask?.cancel()
        sleepTimerTask?.cancel()
        hideControlsTask?.cancel()
        stillWatchingTimeoutTask?.cancel()
    }

    /// Closing the player closes the group too — an orphaned WebSocket connection with
    /// nobody watching isn't useful, and simpler than trying to keep it alive across
    /// whatever the user navigates to next.
    func leaveSyncPlayOnClose() {
        if syncPlayManager.isInGroup, let credential = authManager.state.credential {
            syncPlayManager.leaveGroup(credential: credential, authHeader: authManager.authClient.authHeader(token: credential.accessToken))
        }
    }

    /// The last part of closing: reports where playback stopped and stops the engine.
    func stopPlayback() async {
        nowPlayingManager.clear()
        if let stallObserver { NotificationCenter.default.removeObserver(stallObserver) }
        if let credential, let authHeader, let info = playbackInfo {
            let stoppedAt = player.positionTicks
            await client.reportPlaybackStopped(credential: credential, authHeader: authHeader,
                                               itemId: item.id, mediaSourceId: info.mediaSourceId,
                                               positionTicks: stoppedAt)
            if WatchedThreshold.current.isReached(seconds: Double(stoppedAt) / 10_000_000,
                                                  duration: Double(player.durationTicks) / 10_000_000,
                                                  creditsStart: segments.credits?.lowerBound) {
                _ = try? await client.markWatched(credential: credential, authHeader: authHeader, itemId: item.id, watched: true)
            }
            NotificationCenter.default.post(name: .arcfinPlaybackReported, object: nil)
        }
        await player.stop()
    }

    /// Lets go of the view's own steps once it's closing, since they hold on to it.
    func detachViewSteps() {
        closePlayer = {}
        playbackStarted = {}
        streamReloaded = {}
        engineReleased = {}
        replacementEngineStarting = {}
    }

    func finishPlayback() async {
        guard let credential, let authHeader else { return }
        _ = try? await client.markWatched(credential: credential, authHeader: authHeader, itemId: item.id, watched: true)
        closePlayer()
    }

    private func startProgressReporting(mediaSourceId: String) {
        progressReportTask?.cancel()
        progressReportTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled, let credential, let authHeader else { continue }
                await client.reportPlaybackProgress(
                    credential: credential, authHeader: authHeader, itemId: item.id,
                    mediaSourceId: mediaSourceId, positionTicks: player.positionTicks,
                    isPaused: player.status == .paused
                )
            }
        }
    }

    // MARK: - Quality

    private func qualityCap(for quality: VideoQuality) -> StreamQualityCap {
        // No forceTranscode — a picked quality is a cap, not a demand to re-encode.
        // If the source already qualifies for direct play under that cap, it should stay
        // direct play (forcing a transcode there was wasteful and confusing: Jellyfin's own
        // dashboard correctly said Direct Play while this app's badge said Transcoding).
        if quality == .auto { return autoCap ?? .auto }
        switch quality {
        case .max, .auto: return .auto
        case .p4k:   return StreamQualityCap(maxBitrate: 100_000_000, maxWidth: 3840)
        case .p1080: return StreamQualityCap(maxBitrate: 20_000_000, maxWidth: 1920)
        case .p720:  return StreamQualityCap(maxBitrate: 8_000_000, maxWidth: 1280)
        case .p480:  return StreamQualityCap(maxBitrate: 1_500_000, maxWidth: 854)
        }
    }

    /// Probes throughput with Jellyfin's bandwidth test and starts Auto from it, instead of
    /// starting uncapped and finding out the connection is slow only after a stall-storm.
    private func primeAutoLadder(credential: ServerCredential, authHeader: String) async {
        autoCap = AutoQuality.startingCap(measuredBps: await client.testBitrate(credential: credential, authHeader: authHeader))
    }

    func changeQuality(to newQuality: VideoQuality) {
        guard newQuality != quality else { return }
        quality = newQuality
        recentStallTimestamps.removeAll()
        lastStallHandledAt = nil
        if newQuality == .auto {
            guard let credential, let authHeader else { reload(errorContext: "switch quality"); return }
            Task {
                await primeAutoLadder(credential: credential, authHeader: authHeader)
                reload(errorContext: "switch quality")
            }
        } else {
            reload(errorContext: "switch quality")
        }
    }

    /// Only acts while on Auto — a deliberate manual pick (including "Max") is never
    /// silently overridden by this.
    ///
    /// AVPlayerItemPlaybackStalled fires for plenty of non-network reasons too (seeking,
    /// a reload's own startup buffering, backgrounding) — a single stall is not a reliable
    /// "network can't keep up" signal on its own, and reacting to one caused a reload loop
    /// twice (each reload's startup buffering looked like another stall). Now requires
    /// several stalls clustered in a short window, which normal one-off blips don't produce.
    /// While Auto is running below the source's quality, re-measures the connection after
    /// every few minutes of smooth playback and raises the cap once it has clearly recovered.
    private func startAutoRecovery() {
        autoRecoveryTask?.cancel()
        guard let credential, let authHeader else { return }
        autoRecoveryTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(180))
                guard !Task.isCancelled, quality == .auto, autoCap != nil, player.status == .playing,
                      !player.isBuffering, recentStallTimestamps.isEmpty,
                      lastStallHandledAt.map({ Date().timeIntervalSince($0) > 180 }) ?? true
                else { continue }
                let measured = await client.testBitrate(credential: credential, authHeader: authHeader)
                guard !Task.isCancelled, case .raise(let cap) = AutoQuality.afterRecovery(
                    current: autoCap, sourceBitrate: playbackInfo?.bitrate, measuredBps: measured)
                else { continue }
                autoCap = cap
                reload(errorContext: "raise quality")
                if let bitrate = cap?.maxBitrate {
                    networkToast = String(format: "Raised to %.0f Mb/s — your connection has recovered", Double(bitrate) / 1_000_000)
                } else {
                    networkToast = "Back to full quality — your connection has recovered"
                }
                try? await Task.sleep(for: .seconds(3))
                networkToast = nil
            }
        }
    }

    /// Auto only. Aether can open a source and play its sound while no frame ever reaches the
    /// screen (#269), which setup()'s load-failure fallback never sees. After several seconds of
    /// playback on screen with nothing rendered, that same AVFoundation/VLC fallback takes over
    /// at the same position.
    private func watchForMissingPicture() {
        guard playbackEnginePreference == .auto, let aether = player as? AetherEnginePlayer,
              let info = playbackInfo, info.videoStream != nil else { return }
        pictureCheckTask?.cancel()
        pictureCheckTask = Task {
            var secondsPlayed = 0
            while secondsPlayed < 8 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, player === aether else { return }
                if scenePhase == .active, aether.status == .playing, !aether.isBuffering { secondsPlayed += 1 }
            }
            guard await !aether.hasRenderedVideoFrame(), !Task.isCancelled, player === aether else { return }
            let resumeTicks = aether.positionTicks
            await aether.stop()
            engineReleased()
            player = legacyEnginePlayer(container: info.container, videoStream: info.videoStream)
            reload(errorContext: "switch player", resumeTicks: resumeTicks)
            let notice = String(localized: "This video had no picture, so Arcfin switched to another player.")
            networkToast = notice
            await replacementEngineStarting()
            try? await Task.sleep(for: .seconds(4))
            if networkToast == notice { networkToast = nil }
        }
    }

    /// Back from the background (a call, another app) still loading and not moving: the server
    /// may have ended the stream while nothing was asking for it, and the engine waits on it
    /// forever. Reopening at the same position starts a new one.
    private func checkPlaybackAfterForeground() {
        foregroundCheckTask?.cancel()
        let startTicks = player.positionTicks
        foregroundCheckTask = Task {
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled, player.status == .loading || player.isBuffering,
                  player.positionTicks == startTicks
            else { return }
            reload(errorContext: "resume playback", resumeTicks: startTicks)
        }
    }

    func handlePlaybackStall() {
        guard quality == .auto else { return }
        let now = Date()
        guard AutoQuality.countsStall(at: now, lastLoad: lastLoadStartedAt, lastSeek: lastSeekAt,
                                      isPaused: player.status == .paused) else { return }

        recentStallTimestamps.append(now)
        recentStallTimestamps.removeAll { now.timeIntervalSince($0) > 15 }
        guard recentStallTimestamps.count >= 3 else { return }
        recentStallTimestamps.removeAll()

        if let last = lastStallHandledAt, now.timeIntervalSince(last) < 30 { return }
        lastStallHandledAt = now
        guard let credential, let authHeader else { return }
        Task {
            // Measured again before acting: a stall can come from the server or the engine
            // rather than the connection, and lowering quality doesn't help with those.
            let measured = await client.testBitrate(credential: credential, authHeader: authHeader)
            switch AutoQuality.afterStalls(current: autoCap, sourceBitrate: playbackInfo?.bitrate, measuredBps: measured) {
            case .keep:
                return
            case .exhausted:
                // Still stalling at the bottom step: not a bandwidth problem a lower bitrate
                // can fix (a codec/output failure, a dead source), so say so rather than
                // leaving the video frozen on a spinner.
                errorMessage = "Playback keeps stalling and lowering quality hasn't helped — this source may not play correctly with the current playback engine. Try Settings > Playback > Playback Engine to switch to VLC."
            case .lower(let cap):
                autoCap = cap
                reload(errorContext: "adjust quality")
                let mbps = Double(cap.maxBitrate ?? 0) / 1_000_000
                networkToast = "Lowered to \(mbps >= 1 ? String(format: "%.0f Mb/s", mbps) : String(format: "%.0f Kb/s", mbps * 1000)) — your connection can't keep up"
                try? await Task.sleep(for: .seconds(3))
                networkToast = nil
            }
        }
    }

    // MARK: - Up Next

    private func checkUpNextThreshold(positionTicks: Int64) {
        guard nextEpisode != nil, !upNextDismissed, player.durationTicks > 0 else { return }
        let remainingSeconds = Double(player.durationTicks - positionTicks) / 10_000_000
        let seconds = Double(positionTicks) / 10_000_000
        // From the moment the credits start when the server knows it, else the last 30s.
        let withinWindow = remainingSeconds > 0
            && (segments.credits.map { seconds >= $0.lowerBound } ?? (remainingSeconds <= 30))
        if withinWindow, !showUpNext {
            showUpNext = true
            let defaults = UserDefaults.standard
            if defaults.bool(forKey: "autoPlayNext") || (defaults.bool(forKey: "skipCredits") && segments.credits != nil) {
                startUpNextCountdown()
            }
        } else if !withinWindow, showUpNext {
            showUpNext = false
            cancelUpNextCountdown()
        }
    }

    /// Shows the suggestions from the credits start (when the server knows it) or, failing
    /// that, the last four minutes; seeking back out of the credits hides them again.
    private func checkMoreLikeThisThreshold(positionTicks: Int64) {
        guard nextEpisode == nil, !moreLikeThis.isEmpty, !moreLikeThisDismissed, player.durationTicks > 0 else { return }
        let duration = Double(player.durationTicks) / 10_000_000
        let seconds = Double(positionTicks) / 10_000_000
        let start = segments.credits?.lowerBound ?? max(duration - 240, 0)
        let inCredits = seconds >= start && seconds < duration
        if inCredits != showMoreLikeThis {
            withAnimation(DT.Animation.fast) { showMoreLikeThis = inCredits }
        }
    }

    /// The Skip … Automatically settings: jumps past a segment once as playback enters it.
    private func autoSkipIfNeeded(positionTicks: Int64) {
        let seconds = Double(positionTicks) / 10_000_000
        let defaults = UserDefaults.standard
        for (kind, span, enabled) in [
            ("recap", segments.recap, defaults.bool(forKey: "skipRecap")),
            ("intro", segments.intro, defaults.bool(forKey: "skipIntro")),
            ("credits", segments.credits, defaults.bool(forKey: "skipCredits")),
        ] {
            guard enabled, let span, span.contains(seconds), !autoSkipped.contains(kind) else { continue }
            autoSkipped.insert(kind)
            // In the credits the Up Next card's own countdown moves on to the next title.
            if kind == "credits", showUpNext { return }
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

    /// Past the end of a segment. Credits and previews at the very end move on to the next
    /// title, or finish; credits followed by more of the film (a mid-credits scene) seek to it.
    func skip(kind: String, span: ClosedRange<Double>) {
        let duration = Double(player.durationTicks) / 10_000_000
        let endsTitle = (kind == "credits" || kind == "preview") && (duration == 0 || span.upperBound >= duration - 5)
        if endsTitle {
            if nextEpisode != nil { playNextEpisode() } else { Task { await finishPlayback() } }
        } else {
            Task { await player.seek(to: Int64(span.upperBound * 10_000_000)) }
        }
        HapticManager.impact(.light)
    }

    /// Thumbs rating for what's playing, set from the credits panel; choosing the current
    /// rating again clears it.
    func rateCurrentItem(_ value: Bool) {
        guard let credential, let authHeader else { return }
        let newValue: Bool? = currentLikes == value ? nil : value
        currentLikes = newValue
        HapticManager.impact(.light)
        let id = item.id
        Task { try? await client.setRating(credential: credential, authHeader: authHeader, itemId: id, likes: newValue) }
    }

    private func startUpNextCountdown() {
        cancelUpNextCountdown()
        let countdown = PlayerView.AutoActionCountdown(kind: "next", startedAt: Date(), seconds: PlayerView.autoActionSeconds)
        upNextCountdownState = countdown
        upNextCountdown = Task {
            try? await Task.sleep(for: .seconds(countdown.seconds))
            guard !Task.isCancelled else { return }
            playNextEpisode(isAutomatic: true)
        }
    }

    func cancelUpNextCountdown() {
        upNextCountdown?.cancel()
        upNextCountdownState = nil
    }

    /// `isAutomatic` distinguishes the countdown silently firing from the user actually
    /// tapping Play on the Up Next card — only the former counts toward the "are you still
    /// watching" streak (a manual tap is proof someone's there, and resets it).
    func playNextEpisode(isAutomatic: Bool = false) {
        guard let nextEpisode else { return }
        cancelUpNextCountdown()
        if isAutomatic, sleepAtEndOfItem {
            sleepAtEndOfItem = false
            showUpNext = false
            pauseForSleepTimer()
            return
        }
        if isAutomatic, stillWatchingPromptEnabled {
            let streak = UserDefaults.standard.integer(forKey: Self.autoplayStreakKey) + 1
            UserDefaults.standard.set(streak, forKey: Self.autoplayStreakKey)
            if streak >= Self.stillWatchingThreshold {
                pendingAutoAdvanceEpisode = nextEpisode
                showStillWatchingPrompt = true
                Task { await player.pause() }
                scheduleStillWatchingTimeout()
                return
            }
        } else {
            UserDefaults.standard.set(0, forKey: Self.autoplayStreakKey)
        }
        onPlayNext(nextEpisode)
    }

    // MARK: - Sleep timer

    /// nil minutes = "end of this video": nothing is scheduled, playNextEpisode just
    /// declines to auto-advance once. Picking again replaces whatever was set before.
    func setSleepTimer(minutes: Int?, atEndOfItem: Bool = false) {
        sleepTimerTask?.cancel()
        sleepTimerTask = nil
        sleepTimerEndsAt = nil
        sleepAtEndOfItem = atEndOfItem
        guard let minutes else { return }
        sleepTimerEndsAt = Date().addingTimeInterval(Double(minutes) * 60)
        sleepTimerTask = Task {
            try? await Task.sleep(for: .seconds(minutes * 60))
            guard !Task.isCancelled else { return }
            sleepTimerEndsAt = nil
            pauseForSleepTimer()
        }
    }

    private func pauseForSleepTimer() {
        if CastManager.shared.isConnected { CastManager.shared.pause() }
        Task { await player.pause() }
        networkToast = "Sleep timer — playback paused"
        Task {
            try? await Task.sleep(for: .seconds(3))
            networkToast = nil
        }
    }

    // MARK: - Are you still watching

    static let stillWatchingThreshold = 3
    static let autoplayStreakKey = "arcfin.autoplayStreak"

    /// No response within 60s reads the same as nobody being there — stop rather than
    /// leave a paused, forgotten stream open indefinitely.
    private func scheduleStillWatchingTimeout() {
        stillWatchingTimeoutTask?.cancel()
        stillWatchingTimeoutTask = Task {
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled else { return }
            stopAfterStillWatchingPrompt()
        }
    }

    func continueAfterStillWatchingPrompt() {
        stillWatchingTimeoutTask?.cancel()
        UserDefaults.standard.set(0, forKey: Self.autoplayStreakKey)
        showStillWatchingPrompt = false
        if let pendingAutoAdvanceEpisode {
            onPlayNext(pendingAutoAdvanceEpisode)
        }
        pendingAutoAdvanceEpisode = nil
    }

    func stopAfterStillWatchingPrompt() {
        stillWatchingTimeoutTask?.cancel()
        UserDefaults.standard.set(0, forKey: Self.autoplayStreakKey)
        showStillWatchingPrompt = false
        pendingAutoAdvanceEpisode = nil
        closePlayer()
    }

    func playPrevious() {
        guard let previousItem else { return }
        cancelUpNextCountdown()
        UserDefaults.standard.set(0, forKey: Self.autoplayStreakKey)
        onPlayNext(previousItem)
    }

    func dismissUpNext() {
        upNextDismissed = true
        showUpNext = false
        cancelUpNextCountdown()
    }

    // MARK: - Audio/subtitle tracks

    /// Jellyfin negotiates audio/subtitle selection server-side (transcoded streams often
    /// carry only one audio track, external subtitles aren't muxed into the asset at all) —
    /// AVMediaSelectionGroup on the local asset can't reflect that, so a track change reloads
    /// via a fresh PlaybackInfo call with the new stream index, same as a quality change.
    func changeTrack(audioIndex: Int? = nil, subtitleIndex: Int?? = nil) {
        let previousSubtitle = selectedSubtitleIndex
        if let audioIndex { selectedAudioIndex = audioIndex }
        if let subtitleIndex { selectedSubtitleIndex = subtitleIndex }
        rememberTracks(audioChanged: audioIndex != nil, subtitleChanged: subtitleIndex != nil)
        if audioIndex != nil, subtitleIndex == nil, !CastManager.shared.isConnected,
           playbackInfo?.playMethod == .directPlay {
            Task {
                if await !selectAudioInEngine() { reload(errorContext: "switch track") }
            }
            return
        }
        if audioIndex == nil, let subtitleIndex, !CastManager.shared.isConnected,
           drawsSubtitleHere(previousSubtitle), drawsSubtitleHere(subtitleIndex),
           let credential, let info = playbackInfo {
            Task {
                await loadSubtitleCues(from: info, credential: credential)
                updateSubtitleText(forTicks: player.positionTicks)
            }
            return
        }
        reload(errorContext: "switch track")
    }

    /// A file played as is carries every audio track: the server's audio choice only shapes a
    /// transcode, so here the engine switches tracks itself, without a new stream. Jellyfin's
    /// embedded audio streams and the engine's tracks are both in the file's order; when the
    /// counts don't line up it's left to a reload. Returns whether it was done.
    @discardableResult
    private func selectAudioInEngine() async -> Bool {
        guard let info = playbackInfo, info.playMethod == .directPlay, let index = selectedAudioIndex else { return false }
        // Aether names tracks by their stream index in the file, the same number Jellyfin uses,
        // so it needs no matching by order (which gave up whenever the two lists differed).
        if player is AetherEnginePlayer {
            for _ in 0..<20 where player.availableAudioTracks.isEmpty {
                try? await Task.sleep(for: .milliseconds(100))
            }
            if player.availableAudioTracks.contains(where: { $0.id == index }) {
                if index != player.selectedAudioTrackIndex { await player.setAudioTrack(index: index) }
                return true
            }
        }
        let embedded = info.audioStreams.filter { !$0.isExternal }.sorted { $0.index < $1.index }
        guard let ordinal = embedded.firstIndex(where: { $0.index == index }) else { return false }
        // Engines list tracks a moment after the file opens.
        for _ in 0..<20 where player.availableAudioTracks.isEmpty {
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard player.availableAudioTracks.count == embedded.count else { return false }
        let track = player.availableAudioTracks[ordinal]
        if track.id != player.selectedAudioTrackIndex { await player.setAudioTrack(index: track.id) }
        return true
    }

    /// Text subtitles come as their own file (WebVTT) the app draws over the video, so moving
    /// between them, or turning them off, leaves the stream as it is. Only one the server has
    /// to burn into the picture (an image format being transcoded) needs a new stream.
    private func drawsSubtitleHere(_ index: Int?) -> Bool {
        guard let index else { return true }
        return playbackInfo?.subtitleStreams.first(where: { $0.index == index })?.deliveryUrl != nil
    }

    func changeVersion(_ id: String) {
        guard id != playbackInfo?.mediaSourceId else { return }
        selectedMediaSourceId = id
        // Track indexes belong to a version; the new one picks its own defaults.
        selectedAudioIndex = nil
        selectedSubtitleIndex = nil
        reload(errorContext: "switch version")
    }

    /// Switches to a subtitle the server just fetched from a provider. The server adds it to
    /// the item in the background, so the new track can take a few seconds to be listed.
    func adoptDownloadedSubtitle() {
        guard let credential, let authHeader else { return }
        let known = Set(playbackInfo?.subtitleStreams.map(\.index) ?? [])
        networkToast = "Adding subtitles…"
        Task {
            for _ in 0..<5 {
                if let info = try? await client.getPlaybackInfo(
                    credential: credential, authHeader: authHeader, itemId: item.id, mediaSourceId: selectedMediaSourceId,
                    quality: qualityCap(for: quality),
                    audioStreamIndex: selectedAudioIndex, subtitleStreamIndex: selectedSubtitleIndex,
                    nativeDecoder: decodesNatively),
                   let added = info.subtitleStreams.first(where: { !known.contains($0.index) }) {
                    networkToast = nil
                    changeTrack(subtitleIndex: .some(added.index))
                    return
                }
                try? await Task.sleep(for: .seconds(2))
            }
            networkToast = "Subtitles were saved on the server. Reopen the title to use them."
            try? await Task.sleep(for: .seconds(4))
            networkToast = nil
        }
    }

    /// Stores the language of a track the viewer just picked, for the rest of the show.
    private func rememberTracks(audioChanged: Bool, subtitleChanged: Bool) {
        guard ShowTrackMemory.isEnabled, item.type == .episode, let seriesId = item.seriesId,
              let info = playbackInfo
        else { return }
        var entry = ShowTrackMemory.load(seriesID: seriesId) ?? .init()
        if audioChanged, let index = selectedAudioIndex,
           let language = info.audioStreams.first(where: { $0.index == index })?.language {
            entry.audio = language
        }
        if subtitleChanged {
            if let index = selectedSubtitleIndex {
                if let language = info.subtitleStreams.first(where: { $0.index == index })?.language {
                    entry.subtitle = language
                    entry.subtitlesOff = false
                }
            } else {
                entry.subtitlesOff = true
            }
        }
        ShowTrackMemory.save(entry, seriesID: seriesId)
    }

    private func loadSubtitleCues(from info: JellyfinPlaybackInfo, credential: ServerCredential) async {
        guard let index = selectedSubtitleIndex,
              let stream = info.subtitleStreams.first(where: { $0.index == index }),
              let deliveryUrl = stream.deliveryUrl
        else {
            subtitleCues = []
            currentSubtitleText = nil
            return
        }
        subtitleCues = await SubtitleLoader.loadCues(deliveryUrl: deliveryUrl, credential: credential)
    }

    func updateSubtitleText(forTicks ticks: Int64) {
        guard !CastManager.shared.isConnected else {
            currentSubtitleText = nil
            currentBitmapCue = nil
            return
        }
        let seconds = Double(ticks) / 10_000_000 - subtitleDelay
        if subtitleCues.isEmpty {
            currentSubtitleText = nil
        } else {
            currentSubtitleText = SubtitleLoader.cue(at: seconds, in: subtitleCues)
        }
        if let aetherPlayer = player as? AetherEnginePlayer, !aetherPlayer.nativeBitmapCues.isEmpty {
            currentBitmapCue = aetherPlayer.nativeBitmapCues.first {
                seconds >= $0.startTime && seconds < $0.endTime
            }
        } else {
            currentBitmapCue = nil
        }
    }

    private func reload(errorContext: String, resumeTicks overrideTicks: Int64? = nil) {
        guard let credential, let authHeader else { return }
        let resumeTicks = overrideTicks ?? player.positionTicks
        Task {
            do {
                let info = try await client.getPlaybackInfo(
                    credential: credential, authHeader: authHeader, itemId: item.id, mediaSourceId: selectedMediaSourceId,
                    quality: qualityCap(for: quality),
                    audioStreamIndex: selectedAudioIndex, subtitleStreamIndex: selectedSubtitleIndex,
                    nativeDecoder: decodesNatively
                )
                playbackInfo = info
                await loadSubtitleCues(from: info, credential: credential)
                lastLoadStartedAt = Date()
                try await player.load(url: info.playURL, startPositionTicks: resumeTicks)
                await player.play()
                watchForMissingPicture()
                if selectedAudioIndex != nil { await selectAudioInEngine() }
                await applyRememberedRate()
                streamReloaded()
                updateNowPlayingInfo()
                startProgressReporting(mediaSourceId: info.mediaSourceId)
            } catch {
                errorMessage = "Couldn't \(errorContext): \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Controls visibility

    func scheduleAutoHide() {
        hideControlsTask?.cancel()
        if hidesControlsByFading {
            // A genuine hide via isControlsVisible/allowsHitTesting (same mechanism the other
            // platforms use below) was tried here before and reverted — allowsHitTesting=false
            // made every control genuinely unfocusable, and tvOS's focus engine doesn't reliably
            // migrate focus to a fallback once that happens; unlike iOS there's also no tap
            // gesture on the video surface to bring a hidden overlay back. tvControlsHidden only
            // ever drives opacity, never allowsHitTesting (see body's controlsOverlay modifiers
            // and toggleControlsVisibilityOnAction) — every control stays genuinely focusable the
            // whole time even at opacity 0, so the remote can never end up with nothing reachable,
            // even though visually nothing is on screen until the next interaction.
            hideControlsTask = Task {
                try? await Task.sleep(for: .seconds(3.5))
                guard !Task.isCancelled, player.status == .playing else { return }
                withAnimation(DT.Animation.fast) { tvControlsHidden = true }
            }
        } else {
            hideControlsTask = Task {
                try? await Task.sleep(for: .seconds(3.5))
                guard !Task.isCancelled, player.status == .playing else { return }
                withAnimation(DT.Animation.fast) { isControlsVisible = false }
            }
        }
    }

    func toggleControls() {
        withAnimation(DT.Animation.fast) { isControlsVisible.toggle() }
        if isControlsVisible { scheduleAutoHide() }
    }

    func toggleControlsVisibilityOnAction() {
        if !isControlsVisible { withAnimation(DT.Animation.fast) { isControlsVisible = true } }
        if tvControlsHidden { withAnimation(DT.Animation.fast) { tvControlsHidden = false } }
        scheduleAutoHide()
    }

    // MARK: - Playback actions

    func togglePlayPause() {
        // A manual play/pause is proof someone's actually there — same signal a manual
        // Up Next tap gives, so it resets the "are you still watching" streak too.
        UserDefaults.standard.set(0, forKey: Self.autoplayStreakKey)
        if CastManager.shared.isConnected {
            // The receiver, not the local player, is the one actually playing — control
            // it instead.
            CastManager.shared.togglePlayPause()
            toggleControlsVisibilityOnAction()
            return
        }
        if routesThroughSyncPlay, syncPlayManager.isInGroup, let credential = authManager.state.credential {
            let authHeader = authManager.authClient.authHeader(token: credential.accessToken)
            if player.status == .playing {
                syncPlayManager.requestPause(credential: credential, authHeader: authHeader)
            } else {
                syncPlayManager.requestPlay(credential: credential, authHeader: authHeader)
            }
            toggleControlsVisibilityOnAction()
            return
        }
        if sharePlay.isActive {
            sharePlay.send(player.status == .playing ? .pause : .play, itemId: item.id, positionTicks: player.positionTicks)
        }
        Task {
            if player.status == .playing { await player.pause() } else { await player.play() }
        }
        toggleControlsVisibilityOnAction()
    }

    func seek(by seconds: Int) {
        let base = pendingSeekTargetTicks ?? player.positionTicks
        let newTicks = min(max(0, base + Int64(seconds) * 10_000_000), player.durationTicks)
        performSeek(to: newTicks)
        toggleControlsVisibilityOnAction()
    }

    /// Routes through SyncPlay's Seek command when in a group (applied once it echoes back
    /// over the WebSocket, same as every other group member sees it) instead of seeking the
    /// local player directly — see applySyncPlayCommand.
    func performSeek(to ticks: Int64) {
        pendingSeekTargetTicks = ticks
        if CastManager.shared.isConnected {
            CastManager.shared.seek(toSeconds: Double(ticks) / 10_000_000)
            return
        }
        if routesThroughSyncPlay, syncPlayManager.isInGroup, let credential = authManager.state.credential {
            let authHeader = authManager.authClient.authHeader(token: credential.accessToken)
            syncPlayManager.requestSeek(credential: credential, authHeader: authHeader, positionTicks: ticks)
            return
        }
        if sharePlay.isActive {
            sharePlay.send(.seek, itemId: item.id, positionTicks: ticks)
        }
        Task {
            await player.seek(to: ticks)
            if pendingSeekTargetTicks == ticks { pendingSeekTargetTicks = nil }
        }
    }

    // MARK: - Scrubbing

    func updateScrubThumbnail() {
        // 2s buckets — fetching a fresh crop on every pixel of drag would hammer the loader.
        let bucket = Int(scrubTicks / (2 * 10_000_000))
        guard bucket != lastThumbnailBucket, let loader = trickplayLoader else { return }
        lastThumbnailBucket = bucket
        let ticks = Int64(scrubTicks)
        Task {
            let image = await loader.thumbnail(forPositionTicks: ticks)
            guard isScrubbing else { return }
            scrubThumbnail = image
        }
    }

    var elapsedTicks: Int64 {
        isScrubbing ? Int64(scrubTicks) : (pendingSeekTargetTicks ?? player.positionTicks)
    }

    var remainingTicks: Int64 {
        max(player.durationTicks - (pendingSeekTargetTicks ?? player.positionTicks), 0)
    }

    var remainingLabel: String {
        "-" + timeLabel(ticks: remainingTicks)
    }

    func timeLabel(ticks: Int64) -> String {
        let totalSeconds = Int(Double(ticks) / 10_000_000)
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    // MARK: - Title

    var episodeSubtitle: String? {
        guard item.type == .episode, let series = item.seriesName else { return nil }
        let s = item.parentIndexNumber.map { "S\($0)" } ?? ""
        let e = item.indexNumber.map { "E\($0)" } ?? ""
        return [series, [s, e].joined()].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// The transcode profile only ever outputs h264/SDR (see JellyfinPlaybackClient's
    /// TranscodingProfiles) — an HDR/DV source that gets transcoded is always tone-mapped
    /// down to SDR, which is worth surfacing since it's a visible quality loss the user
    /// didn't ask for.
    var hdrIsToneMapped: Bool {
        (playbackInfo?.isHDR ?? false) && playbackInfo?.playMethod == .transcode
    }

    var hdrLabel: String? {
        guard let info = playbackInfo, info.isHDR else { return nil }
        if hdrIsToneMapped { return "HDR → SDR" }
        return info.isDolbyVision ? "DOLBY VISION" : "HDR"
    }

    // MARK: - Chapters

    var currentChapterIndex: Int? {
        var result: Int?
        for (index, chapter) in chapters.enumerated() where chapter.startPositionTicks <= player.positionTicks {
            result = index
        }
        return result
    }

    func jumpToChapter(_ chapter: MediaChapter) {
        Task { await player.seek(to: chapter.startPositionTicks) }
        HapticManager.impact(.light)
    }

    // MARK: - Skip intro/credits

    /// The segment playback is in right now, if any, with its button label.
    var currentSkippable: (kind: String, label: String, span: ClosedRange<Double>)? {
        let seconds = Double(player.positionTicks) / 10_000_000
        guard seconds > 0.5 else { return nil }
        // Recap ("previously on") is the cold open ahead of the intro, so it's checked first.
        if let span = segments.recap, span.contains(seconds) { return ("recap", "Skip Recap", span) }
        if let span = segments.intro, span.contains(seconds) { return ("intro", "Skip Intro", span) }
        if let span = segments.credits, span.contains(seconds) {
            // Up Next and the suggestions panel already offer a way on from the credits,
            // unless an automatic skip is counting down and needs to be seen.
            guard !showUpNext, !showMoreLikeThis || autoSkipCountdown?.kind == "credits" else { return nil }
            return ("credits", "Skip Credits", span)
        }
        if let span = segments.preview, span.contains(seconds) { return ("preview", "Skip Preview", span) }
        return nil
    }

    var skipButtonLabel: String? { currentSkippable?.label }

    func skipToSegmentEnd() {
        guard let current = currentSkippable else { return }
        skip(kind: current.kind, span: current.span)
    }

    /// Past the credits: to the scene after them, or the end when they run to it.
    func skipCredits() {
        guard let credits = segments.credits else { return }
        skip(kind: "credits", span: credits)
    }

    // MARK: - More Like This

    /// Closes the panel before handing over, since this view can outlive the item it was
    /// showing suggestions for.
    func playSuggestion(_ suggestion: MediaItem) {
        moreLikeThisDismissed = true
        withAnimation(DT.Animation.fast) { showMoreLikeThis = false }
        onPlayNext(suggestion)
    }

    // MARK: - Media info

    var currentAudioStream: JellyfinMediaStream? {
        playbackInfo?.audioStreams.first(where: { $0.index == selectedAudioIndex })
    }

    var currentSubtitleStream: JellyfinMediaStream? {
        guard let selectedSubtitleIndex else { return nil }
        return playbackInfo?.subtitleStreams.first(where: { $0.index == selectedSubtitleIndex })
    }
}
