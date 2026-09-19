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
    public private(set) var deviceName: String?

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

    public func loadMedia(
        streamURL: URL, title: String, subtitle: String?, posterImageURL: URL?,
        contentType: String, startPositionSeconds: TimeInterval
    ) {
        #if canImport(GoogleCast)
        guard let client = GCKCastContext.sharedInstance().sessionManager.currentSession?.remoteMediaClient else { return }

        let metadata = GCKMediaMetadata(metadataType: .movie)
        metadata.setString(title, forKey: kGCKMetadataKeyTitle)
        if let subtitle { metadata.setString(subtitle, forKey: kGCKMetadataKeySubtitle) }
        if let posterImageURL { metadata.addImage(GCKImage(url: posterImageURL, width: 480, height: 720)) }

        let infoBuilder = GCKMediaInformationBuilder(contentURL: streamURL)
        infoBuilder.contentType = contentType
        infoBuilder.streamType = .buffered
        infoBuilder.metadata = metadata

        let requestBuilder = GCKMediaLoadRequestDataBuilder()
        requestBuilder.mediaInformation = infoBuilder.build()
        requestBuilder.startTime = startPositionSeconds
        requestBuilder.autoplay = true
        client.loadMedia(with: requestBuilder.build())
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
    public nonisolated func sessionManager(_ sessionManager: GCKSessionManager, willStart session: GCKSession) {
        MainActor.assumeIsolated { isConnecting = true }
    }

    public nonisolated func sessionManager(_ sessionManager: GCKSessionManager, didStart session: GCKSession) {
        MainActor.assumeIsolated {
            isConnecting = false
            isConnected = true
            deviceName = session.device.friendlyName
            (session as? GCKCastSession)?.remoteMediaClient?.add(self)
        }
    }

    public nonisolated func sessionManager(_ sessionManager: GCKSessionManager, didResumeSession session: GCKSession) {
        MainActor.assumeIsolated {
            isConnecting = false
            isConnected = true
            deviceName = session.device.friendlyName
            (session as? GCKCastSession)?.remoteMediaClient?.add(self)
        }
    }

    public nonisolated func sessionManager(_ sessionManager: GCKSessionManager, didEnd session: GCKSession, withError error: Error?) {
        MainActor.assumeIsolated {
            isConnecting = false
            isConnected = false
            isPaused = false
            deviceName = nil
            (session as? GCKCastSession)?.remoteMediaClient?.remove(self)
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
        MainActor.assumeIsolated {
            isPaused = mediaStatus?.playerState == .paused
        }
    }
}
#endif
