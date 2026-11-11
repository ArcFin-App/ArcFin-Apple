// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Observation
#if canImport(GoogleCast)
import GoogleCast
#endif

/// Chromecast sender wrapper. Compiles on every platform this package targets, but is only
/// functional on iOS — GoogleCast has no tvOS/macOS SDK at all, so everything below
/// `#if canImport(GoogleCast)` no-ops on other platforms rather than needing every call
/// site in the app to wrap itself in its own platform check.
///
/// Scope: casts to Google's default styled media receiver (no custom receiver app
/// registered for Arcfin) via a direct, pre-authenticated stream URL — the receiver plays
/// the URL itself, it isn't handed Arcfin's own Authorization header, so a URL with the
/// token already embedded as a query parameter is required (JellyfinMediaClient's direct
/// stream URLs already support this).
@MainActor
@Observable
public final class CastManager: NSObject {
    public static let shared = CastManager()

    public private(set) var isCastAvailable = false
    public private(set) var isConnected = false
    public private(set) var isConnecting = false
    public private(set) var isPaused = false
    public private(set) var volume: Float = 1
    /// Title of whatever this app last loaded onto the receiver, for UI that outlives the
    /// player screen (the mini controller). Cleared when the session ends.
    public private(set) var nowPlayingTitle: String?
    /// The Jellyfin item on the receiver, so the mini controller can reopen its player. Sent
    /// along as the media's customData, so a session resumed after a relaunch still has it.
    public private(set) var nowPlayingItemID: String?
    /// Bumps each time the receiver reports the loaded item played to its end — observers
    /// use the change as an event (e.g. to cast the next episode); the value itself is
    /// meaningless.
    public private(set) var playbackFinishedCount = 0
    @ObservationIgnored private var lastStatusWasFinished = false
    public private(set) var deviceName: String?
    /// Updated on every GCKRemoteMediaClient status tick (at least once/second while
    /// playing) rather than read on demand — by the time a session actually ends,
    /// `currentSession` is already nil, so `currentPositionSeconds()` can no longer see
    /// where playback left off. This is what local playback resumes from after a cast
    /// session ends. Cleared at the start of the next session so a stale value never leaks
    /// into it.
    public private(set) var lastKnownPositionSeconds: TimeInterval?

    private var didStart = false

    private override init() { super.init() }

    /// Call once, as early as possible at app launch (see AppDelegate) — Google's own
    /// documented requirement is that GCKCastContext exists before any Cast UI/session code
    /// runs.
    public func start() {
        #if canImport(GoogleCast)
        guard !didStart else { return }
        didStart = true
        let criteria = GCKDiscoveryCriteria(applicationID: kGCKDefaultMediaReceiverApplicationID)
        let options = GCKCastOptions(discoveryCriteria: criteria)
        GCKCastContext.setSharedInstanceWith(options)
        GCKCastContext.sharedInstance().sessionManager.add(self)
        isCastAvailable = true
        #endif
    }

    // MARK: - Media control

    public struct SubtitleTrack: Sendable {
        public let id: Int
        public let url: URL
        public let languageCode: String?
        public let name: String?

        public init(id: Int, url: URL, languageCode: String?, name: String?) {
            self.id = id
            self.url = url
            self.languageCode = languageCode
            self.name = name
        }
    }

    public func loadMedia(
        itemID: String, streamURL: URL, title: String, subtitle: String?, posterImageURL: URL?,
        contentType: String, startPositionSeconds: TimeInterval,
        subtitleTracks: [SubtitleTrack] = [], activeSubtitleTrackID: Int? = nil,
        isTransportStreamHLS: Bool = false, isLive: Bool = false
    ) {
        #if canImport(GoogleCast)
        guard let client = GCKCastContext.sharedInstance().sessionManager.currentSession?.remoteMediaClient else { return }
        nowPlayingTitle = title
        nowPlayingItemID = itemID

        let metadata = GCKMediaMetadata(metadataType: .movie)
        metadata.setString(title, forKey: kGCKMetadataKeyTitle)
        if let subtitle { metadata.setString(subtitle, forKey: kGCKMetadataKeySubtitle) }
        if let posterImageURL { metadata.addImage(GCKImage(url: posterImageURL, width: 480, height: 720)) }

        let infoBuilder = GCKMediaInformationBuilder(contentURL: streamURL)
        infoBuilder.contentType = contentType
        infoBuilder.streamType = isLive ? .live : .buffered
        infoBuilder.metadata = metadata
        infoBuilder.customData = [Self.itemIDKey: itemID]
        if isTransportStreamHLS {
            // Left undefined the receiver guesses the segment layout, and the guess for
            // Jellyfin's TS+AAC output is what produced doubled, offset audio.
            infoBuilder.hlsSegmentFormat = .TS_AAC
            infoBuilder.hlsVideoSegmentFormat = .MPEG2_TS
        }
        infoBuilder.mediaTracks = subtitleTracks.compactMap {
            GCKMediaTrack(
                identifier: $0.id, contentIdentifier: $0.url.absoluteString, contentType: "text/vtt",
                type: .text, textSubtype: .subtitles, name: $0.name, languageCode: $0.languageCode,
                customData: nil)
        }

        let requestBuilder = GCKMediaLoadRequestDataBuilder()
        requestBuilder.mediaInformation = infoBuilder.build()
        // A live stream with no start time starts at the live edge.
        if !isLive { requestBuilder.startTime = startPositionSeconds }
        requestBuilder.autoplay = true
        if let activeSubtitleTrackID { requestBuilder.activeTrackIDs = [NSNumber(value: activeSubtitleTrackID)] }
        client.loadMedia(with: requestBuilder.build())
        #endif
    }

    private nonisolated static let itemIDKey = "arcfinItemId"

    public func setActiveSubtitleTrack(id: Int?) {
        #if canImport(GoogleCast)
        GCKCastContext.sharedInstance().sessionManager.currentSession?.remoteMediaClient?
            .setActiveTrackIDs(id.map { [NSNumber(value: $0)] } ?? [])
        #endif
    }

    public func setVolume(_ volume: Float) {
        let clamped = min(max(volume, 0), 1)
        self.volume = clamped
        #if canImport(GoogleCast)
        GCKCastContext.sharedInstance().sessionManager.currentSession?.remoteMediaClient?
            .setStreamVolume(clamped)
        #endif
    }

    public func play() {
        #if canImport(GoogleCast)
        GCKCastContext.sharedInstance().sessionManager.currentSession?.remoteMediaClient?.play()
        #endif
    }

    public func pause() {
        #if canImport(GoogleCast)
        GCKCastContext.sharedInstance().sessionManager.currentSession?.remoteMediaClient?.pause()
        #endif
    }

    public func togglePlayPause() {
        if isPaused { play() } else { pause() }
    }

    public func seek(toSeconds seconds: TimeInterval) {
        #if canImport(GoogleCast)
        guard let client = GCKCastContext.sharedInstance().sessionManager.currentSession?.remoteMediaClient else { return }
        let options = GCKMediaSeekOptions()
        options.interval = seconds
        client.seek(with: options)
        #endif
    }

    /// Seconds into the currently-cast item — nil when nothing's loaded on the receiver.
    public func currentPositionSeconds() -> TimeInterval? {
        #if canImport(GoogleCast)
        GCKCastContext.sharedInstance().sessionManager.currentSession?.remoteMediaClient?.approximateStreamPosition()
        #else
        nil
        #endif
    }

    public func endSession() {
        #if canImport(GoogleCast)
        GCKCastContext.sharedInstance().sessionManager.endSessionAndStopCasting(true)
        #endif
    }
}

#if canImport(GoogleCast)
extension CastManager: GCKSessionManagerListener {
    // GCK's listener callbacks are documented as always delivered on the main thread, but
    // the protocol itself carries no Swift concurrency annotation — Swift 6 strict
    // concurrency flags a @MainActor class conforming to it as crossing isolation, so each
    // requirement is nonisolated here and hops back in with assumeIsolated (safe given
    // that documented guarantee), same pattern as DownloadManager's background-task handler.
    // GCKSession/GCKMediaStatus aren't Sendable, so all the actual work touching them
    // (reading friendlyName, add/remove listener) happens out here in the nonisolated
    // scope, before assumeIsolated — only plain Sendable values (String?, Bool) cross into
    // the closure that actually writes the @Observable properties.
    public nonisolated func sessionManager(_ sessionManager: GCKSessionManager, willStart session: GCKSession) {
        MainActor.assumeIsolated { isConnecting = true }
    }

    public nonisolated func sessionManager(_ sessionManager: GCKSessionManager, didStart session: GCKSession) {
        let name = session.device.friendlyName
        (session as? GCKCastSession)?.remoteMediaClient?.add(self)
        MainActor.assumeIsolated {
            isConnecting = false
            isConnected = true
            deviceName = name
            lastKnownPositionSeconds = nil
        }
    }

    public nonisolated func sessionManager(_ sessionManager: GCKSessionManager, didResumeSession session: GCKSession) {
        let name = session.device.friendlyName
        let client = (session as? GCKCastSession)?.remoteMediaClient
        client?.add(self)
        // After a relaunch nothing here knows what the receiver is playing until it says so.
        client?.requestStatus()
        MainActor.assumeIsolated {
            isConnecting = false
            isConnected = true
            deviceName = name
            lastKnownPositionSeconds = nil
        }
    }

    public nonisolated func sessionManager(_ sessionManager: GCKSessionManager, didEnd session: GCKSession, withError error: Error?) {
        (session as? GCKCastSession)?.remoteMediaClient?.remove(self)
        MainActor.assumeIsolated {
            isConnecting = false
            isConnected = false
            isPaused = false
            deviceName = nil
            nowPlayingTitle = nil
            nowPlayingItemID = nil
        }
    }

    public nonisolated func sessionManager(_ sessionManager: GCKSessionManager, didFailToStart session: GCKSession, withError error: Error) {
        MainActor.assumeIsolated {
            isConnecting = false
            isConnected = false
        }
    }
}

extension CastManager: GCKRemoteMediaClientListener {
    public nonisolated func remoteMediaClient(_ client: GCKRemoteMediaClient, didUpdate mediaStatus: GCKMediaStatus?) {
        let paused = mediaStatus?.playerState == .paused
        let finished = mediaStatus?.playerState == .idle && mediaStatus?.idleReason == .finished
        let position = mediaStatus?.streamPosition
        let receiverVolume = mediaStatus?.volume
        let info = mediaStatus?.mediaInformation
        let title = info?.metadata?.string(forKey: kGCKMetadataKeyTitle)
        let itemID = (info?.customData as? [String: Any])?[Self.itemIDKey] as? String
        MainActor.assumeIsolated {
            // Fills in what a resumed session doesn't know; a load from here already set both.
            if nowPlayingTitle == nil, let title { nowPlayingTitle = title }
            if nowPlayingItemID == nil, let itemID { nowPlayingItemID = itemID }
            // Idle statuses can repeat; only the transition into "finished" is an event.
            if finished, !lastStatusWasFinished { playbackFinishedCount += 1 }
            lastStatusWasFinished = finished
            isPaused = paused
            if let receiverVolume { volume = receiverVolume }
            if let position { lastKnownPositionSeconds = position }
        }
    }
}
#endif
