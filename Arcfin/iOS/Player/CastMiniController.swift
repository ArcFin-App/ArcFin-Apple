// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import ActivityKit
import AuthCore
import AVFoundation
import CastKit
import JellyfinAPI
import LiveActivityKit
import WatchConnectivity

/// The compact "now casting" bar shown above the tab bar (via tabViewBottomAccessory) while a
/// Cast session has something loaded and the player screen isn't open — so playback on the
/// TV can be paused or stopped without reopening a title, and a tap opens its player again.
struct CastMiniController: View {
    private var cast: CastManager { CastManager.shared }

    var body: some View {
        HStack(spacing: 12) {
            Button { openPlayer() } label: {
                HStack(spacing: 12) {
                    Image(systemName: "tv")
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(DT.Color.accent)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(cast.nowPlayingTitle ?? "Casting")
                            .font(.system(.footnote, design: .default, weight: .semibold))
                            .lineLimit(1)
                        Text("Casting to \(cast.deviceName ?? "TV")")
                            .font(.system(.caption2))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .disabled(cast.nowPlayingItemID == nil)
            .accessibilityHint("Opens the player")

            Button { cast.togglePlayPause() } label: {
                Image(systemName: cast.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(.title3))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(cast.isPaused ? "Play" : "Pause")

            Button { cast.endSession() } label: {
                Image(systemName: "xmark")
                    .font(.system(.body, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Stop casting")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        // Up opens the player, as on the music pill.
        .simultaneousGesture(DragGesture(minimumDistance: 12).onEnded { drag in
            if drag.translation.height < -20, abs(drag.translation.height) > abs(drag.translation.width) { openPlayer() }
        })
        .accessibilityElement(children: .contain)
    }

    /// Something another device cast has no item ID, so there's no player to open for it.
    private func openPlayer() {
        guard let id = cast.nowPlayingItemID else { return }
        WatchRoute.open(id: id)
    }
}

// MARK: - Mini bar

/// Above the tab bar while another device plays: what, where, play/pause, and a tap opens
/// the remote. Laid out like the cast mini controller.
struct RemoteMiniController: View {
    private var remote: RemoteSessions { AppServices.remoteSessions }

    var body: some View {
        if let session = remote.selected {
            HStack(spacing: 12) {
                Button { remote.open(session) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "av.remote")
                            .font(.system(.body, weight: .semibold))
                            .foregroundStyle(DT.Color.accent)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: session.nowPlayingItemName ?? "")
                                .font(.system(.footnote, weight: .semibold))
                                .lineLimit(1)
                            Text("Playing on \(session.deviceName)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                    }
                    .contentShape(Rectangle())
                }
                .accessibilityHint("Opens the remote")

                Button { remote.playPause() } label: {
                    Image(systemName: session.isPaused ? "play.fill" : "pause.fill")
                        .font(.title3)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(session.isPaused ? "Play" : "Pause")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
            // Up opens the remote, as on the music pill.
            .simultaneousGesture(DragGesture(minimumDistance: 12).onEnded { drag in
                if drag.translation.height < -20, abs(drag.translation.height) > abs(drag.translation.width) { remote.open(session) }
            })
            .accessibilityElement(children: .contain)
        }
    }
}

// MARK: - Remote screen

/// The remote for another device, in the cast controller's style: artwork behind, what's
/// playing and where, a scrubber, the transport, volume and tracks.
struct RemoteControllerView: View {
    private var remote: RemoteSessions { AppServices.remoteSessions }
    @AppStorage("skipForwardSeconds") private var skipForwardSeconds = 10
    @AppStorage("skipBackwardSeconds") private var skipBackwardSeconds = 10
    @State private var scrubbing: Double?
    @State private var volume: Double?
    @State private var volumeButtons = RemoteVolumeButtons()

    var body: some View {
        Group {
            if let session = remote.selected {
                GeometryReader { geo in
                    let landscape = geo.size.width > geo.size.height
                    ScrollView {
                        VStack(spacing: 0) {
                            header
                            if landscape {
                                HStack(spacing: 32) {
                                    info(session, artworkHeight: max(geo.size.height - 150, 120))
                                        .frame(maxWidth: .infinity)
                                    controls(session).frame(maxWidth: .infinity)
                                }
                                .frame(maxHeight: .infinity)
                            } else {
                                Spacer(minLength: 12)
                                info(session, artworkHeight: min(280, geo.size.height * 0.34))
                                Spacer(minLength: 20)
                                controls(session)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                        .frame(minHeight: geo.size.height)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
                .foregroundStyle(.white)
                .buttonStyle(.plain)
                .background { background(session) }
                // Down closes it, as on the music player.
                .simultaneousGesture(DragGesture(minimumDistance: 20).onEnded { drag in
                    if drag.translation.height > 80, drag.translation.height > abs(drag.translation.width) { remote.isShowingRemote = false }
                })
            } else {
                VStack(spacing: 12) {
                    Text("Nothing Playing")
                        .font(.headline)
                    Button("Close") { remote.isShowingRemote = false }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.ignoresSafeArea())
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { volumeButtons.start { remote.stepVolume(up: $0) } }
        .onDisappear { volumeButtons.stop() }
    }

    private func background(_ session: JellyfinSession) -> some View {
        Color.black
            .overlay {
                CachedAsyncImage(url: remote.artworkURL(for: session)) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    default: Color.clear
                    }
                }
                .overlay(.black.opacity(0.75))
                .blur(radius: 40)
            }
            .clipped()
            .ignoresSafeArea()
    }

    private var header: some View {
        HStack {
            Button { remote.isShowingRemote = false } label: {
                Image(systemName: "chevron.down")
                    .font(.title3.weight(.semibold))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Close remote")
            Spacer()
            if remote.playing.count > 1 {
                Menu {
                    ForEach(remote.playing) { other in
                        Button(other.deviceName) { remote.open(other) }
                    }
                } label: {
                    Label("Devices", systemImage: "rectangle.on.rectangle")
                        .labelStyle(.iconOnly)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Choose a device")
            }
        }
    }

    private func info(_ session: JellyfinSession, artworkHeight: CGFloat) -> some View {
        VStack(spacing: 18) {
            CachedAsyncImage(url: remote.artworkURL(for: session, type: "Primary")) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFit()
                default: RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.08)).aspectRatio(2 / 3, contentMode: .fit)
                }
            }
            .frame(maxHeight: artworkHeight)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text(verbatim: session.nowPlayingItemName ?? "")
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                if let series = session.nowPlayingSeriesName {
                    Text(verbatim: [series, session.nowPlayingEpisodeCode].compactMap { $0 }.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                Label {
                    Text("Playing on \(session.deviceName)")
                } icon: {
                    Image(systemName: "av.remote")
                }
                .font(.footnote)
                .foregroundStyle(DT.Color.accent)
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    private func controls(_ session: JellyfinSession) -> some View {
        VStack(spacing: 18) {
            scrubber(session)
            transport(session)
            volumeRow(session)
            trackMenus(session)
            Button(role: .destructive) { remote.stopPlayback() } label: {
                Text("Stop Playback")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 18).padding(.vertical, 9)
                    .background(Color.white.opacity(0.15), in: Capsule())
            }
        }
        .frame(maxWidth: 480)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    private func scrubber(_ session: JellyfinSession) -> some View {
        let duration = Double(max(session.runTimeTicks ?? 0, 1))
        let shown = scrubbing ?? Double(remote.estimatedTicks)
        return VStack(spacing: 4) {
            Slider(value: Binding(get: { shown / duration }, set: { scrubbing = $0 * duration }), in: 0...1) { editing in
                if !editing, let scrubbing {
                    remote.seek(to: Int64(scrubbing))
                    self.scrubbing = nil
                }
            }
            .tint(DT.Color.accent)
            .accessibilityLabel("Playback position")
            HStack {
                Text(Self.time(Int64(shown)))
                Spacer()
                Text("-" + Self.time(Int64(max(duration - shown, 0))))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white.opacity(0.7))
            .accessibilityHidden(true)
        }
    }

    private func transport(_ session: JellyfinSession) -> some View {
        HStack(spacing: 12) {
            control("backward.end.fill", label: "Previous") { remote.previous() }
            control(skipIconName(seconds: skipBackwardSeconds, forward: false), label: "Skip back \(skipBackwardSeconds) seconds") {
                remote.skip(seconds: -skipBackwardSeconds)
            }
            Button { remote.playPause() } label: {
                Image(systemName: session.isPaused ? "play.fill" : "pause.fill")
                    .font(.largeTitle)
                    .frame(minWidth: 64, minHeight: 64)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(session.isPaused ? "Play" : "Pause")
            control(skipIconName(seconds: skipForwardSeconds, forward: true), label: "Skip forward \(skipForwardSeconds) seconds") {
                remote.skip(seconds: skipForwardSeconds)
            }
            control("forward.end.fill", label: "Next") { remote.next() }
        }
    }

    private func control(_ symbol: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title2)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }

    private func volumeRow(_ session: JellyfinSession) -> some View {
        HStack(spacing: 10) {
            Button { remote.toggleMute() } label: {
                Image(systemName: session.isMuted ? "speaker.slash.fill" : "speaker.fill")
                    .font(.footnote)
                    .frame(minWidth: 32, minHeight: 32)
            }
            .accessibilityLabel(session.isMuted ? "Unmute" : "Mute")
            Slider(value: Binding(get: { volume ?? Double(session.volumeLevel ?? 100) },
                                  set: { volume = $0 }),
                   in: 0...100) { editing in
                // Held until the device reports the new level, or the old one shows meanwhile.
                if !editing, let volume { remote.setVolume(Int(volume)) }
            }
            .tint(DT.Color.accent)
            .accessibilityLabel("Volume")
            .onChange(of: session.volumeLevel) { volume = nil }
            Image(systemName: "speaker.wave.3.fill")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.7))
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private func trackMenus(_ session: JellyfinSession) -> some View {
        if session.audioTracks.count > 1 || !session.subtitleTracks.isEmpty {
            HStack(spacing: 12) {
                if session.audioTracks.count > 1 {
                    Menu {
                        ForEach(session.audioTracks) { track in
                            Button { remote.selectAudio(track.index) } label: {
                                if track.index == session.audioStreamIndex {
                                    Label(track.title, systemImage: "checkmark")
                                } else {
                                    Text(verbatim: track.title)
                                }
                            }
                        }
                    } label: {
                        trackLabel("Audio", systemImage: "speaker.wave.2")
                    }
                }
                if !session.subtitleTracks.isEmpty {
                    Menu {
                        Button { remote.selectSubtitle(nil) } label: {
                            if (session.subtitleStreamIndex ?? -1) < 0 { Label("Off", systemImage: "checkmark") } else { Text("Off") }
                        }
                        ForEach(session.subtitleTracks) { track in
                            Button { remote.selectSubtitle(track.index) } label: {
                                if track.index == session.subtitleStreamIndex {
                                    Label(track.title, systemImage: "checkmark")
                                } else {
                                    Text(verbatim: track.title)
                                }
                            }
                        }
                    } label: {
                        trackLabel("Subtitles", systemImage: "captions.bubble")
                    }
                }
            }
        }
    }

    private func trackLabel(_ title: LocalizedStringKey, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(Color.white.opacity(0.15), in: Capsule())
    }

    private static func time(_ ticks: Int64) -> String {
        let total = Int(ticks / 10_000_000)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

// MARK: - Volume buttons

/// The phone's volume buttons turn the other device's volume up and down while the remote is
/// open, and leave the phone's own volume alone. The buttons only reach the app as changes to
/// the phone's volume, so each press is put straight back. At either end of the phone's range
/// a press would go unheard, so there it rests in the middle until the remote closes.
@MainActor
final class RemoteVolumeButtons {
    private var observation: NSKeyValueObservation?
    private var hiddenSlider: SystemVolumeController?
    private var originalVolume: Float = 0.5
    private var restingVolume: Float = 0.5
    private var settingTo: Float?

    func start(onPress: @escaping @MainActor (Bool) -> Void) {
        guard observation == nil else { return }
        hiddenSlider = SystemVolumeController()
        Task {
            // Mixes, so music playing on the phone carries on. Active, or the buttons change
            // the ringer and the app hears nothing. Off the main thread: these calls block.
            await Task.detached {
                let session = AVAudioSession.sharedInstance()
                try? session.setCategory(.playback, options: .mixWithOthers)
                try? session.setActive(true)
            }.value
            guard hiddenSlider != nil else { return }
            let volume = AVAudioSession.sharedInstance().outputVolume
            originalVolume = volume
            restingVolume = volume > 0.95 || volume < 0.05 ? 0.5 : volume
            if restingVolume != volume { put(restingVolume) }
            // Strong: stop() invalidates the observation, which lets go of it.
            observation = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.new]) { [self] _, change in
                guard let new = change.newValue else { return }
                Task { @MainActor in self.changed(to: new, onPress: onPress) }
            }
        }
    }

    func stop() {
        observation?.invalidate()
        observation = nil
        if abs(AVAudioSession.sharedInstance().outputVolume - originalVolume) > 0.001 {
            hiddenSlider?.setVolume(originalVolume)
        }
        hiddenSlider?.teardown()
        hiddenSlider = nil
        Task.detached {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private func changed(to new: Float, onPress: @MainActor (Bool) -> Void) {
        if let settingTo, abs(new - settingTo) < 0.01 {
            self.settingTo = nil
            return
        }
        guard abs(new - restingVolume) > 0.001 else { return }
        onPress(new > restingVolume)
        put(restingVolume)
    }

    private func put(_ volume: Float) {
        settingTo = volume
        hiddenSlider?.setVolume(volume)
    }
}

// MARK: - Live Activity

/// Another device playing, on the Lock Screen and in the Dynamic Island, with play and pause,
/// skip and volume. iOS only gives the system Now Playing card to an app playing audio
/// itself, so this is a Live Activity instead. It's updated whenever the list comes back from
/// the server, and after each of its buttons; while the app is suspended its bar keeps moving
/// on its own.
@MainActor
final class RemotePlaybackActivity {
    static let shared = RemotePlaybackActivity()

    private typealias Attributes = RemotePlaybackActivityAttributes
    private var activity: Activity<Attributes>?
    private var shown: Attributes.ContentState?
    private var artworkItemID: String?
    private var artwork: Data?
    private static let pausedStaleAfter: TimeInterval = 5 * 60

    func install() {
        activity = Activity<Attributes>.activities.first
        RemotePlaybackCommands.handler = { action, sessionID in
            await RemotePlaybackActivity.shared.perform(action, sessionID: sessionID)
        }
    }

    private func perform(_ action: RemotePlaybackAction, sessionID: String) async {
        let remote = AppServices.remoteSessions
        remote.attach(AppServices.authManager)
        remote.selectedID = sessionID
        if remote.selected?.id != sessionID { await remote.refresh() }
        guard remote.selected?.id == sessionID else { return }
        let defaults = UserDefaults.standard
        switch action {
        case .playPause: remote.playPause()
        case .skipBackward: remote.skip(seconds: -((defaults.object(forKey: "skipBackwardSeconds") as? Int) ?? 10))
        case .skipForward: remote.skip(seconds: (defaults.object(forKey: "skipForwardSeconds") as? Int) ?? 10)
        case .volumeDown: remote.stepVolume(up: false)
        case .volumeUp: remote.stepVolume(up: true)
        }
        try? await Task.sleep(for: .milliseconds(800))
        await remote.refresh()
        await sync()
    }

    /// Matches the activity to what the list says: started, updated, or ended.
    func sync() async {
        guard let session = AppServices.remoteSessions.selected else {
            await end()
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if let activity, activity.attributes.sessionID != session.id { await end() }
        if artworkItemID != session.nowPlayingItemId {
            artworkItemID = session.nowPlayingItemId
            artwork = await thumbnail(for: session)
        }
        let state = Attributes.ContentState(
            title: session.nowPlayingItemName ?? "",
            subtitle: session.nowPlayingSeriesName.map { [$0, session.nowPlayingEpisodeCode].compactMap { $0 }.joined(separator: " · ") },
            deviceName: session.deviceName,
            isPaused: session.isPaused,
            positionSeconds: Double(session.positionTicks ?? 0) / 10_000_000,
            durationSeconds: Double(session.runTimeTicks ?? 0) / 10_000_000,
            updatedAt: .now,
            artwork: artwork
        )
        // Paused (or no runtime) has no end to go stale after, so it goes stale a few minutes
        // after the last word from the server: once the app stops refreshing, a session that
        // since stopped is marked stale instead of looking current for hours.
        let content = ActivityContent(state: state, staleDate: state.playbackSpan?.upperBound.addingTimeInterval(60)
                                                    ?? state.updatedAt.addingTimeInterval(Self.pausedStaleAfter))
        if let activity {
            guard needsUpdate(state) else { return }
            await activity.update(content)
        } else {
            activity = try? Activity.request(attributes: Attributes(sessionID: session.id), content: content)
        }
        shown = state
    }

    private func end() async {
        guard let activity else { return }
        self.activity = nil
        shown = nil
        await activity.end(nil, dismissalPolicy: .immediate)
    }

    /// The bar moves by itself, so a new position only counts when it's drifted from it.
    private func needsUpdate(_ state: Attributes.ContentState) -> Bool {
        guard let shown else { return true }
        if shown.title != state.title || shown.subtitle != state.subtitle || shown.deviceName != state.deviceName
            || shown.isPaused != state.isPaused || shown.durationSeconds != state.durationSeconds || shown.artwork != state.artwork {
            return true
        }
        // Pushes the paused stale date on while the list keeps coming back.
        if shown.playbackSpan == nil, state.updatedAt.timeIntervalSince(shown.updatedAt) > Self.pausedStaleAfter / 2 {
            return true
        }
        let expected = shown.isPaused ? shown.positionSeconds
            : shown.positionSeconds + state.updatedAt.timeIntervalSince(shown.updatedAt)
        return abs(expected - state.positionSeconds) > 3
    }

    private func thumbnail(for session: JellyfinSession) async -> Data? {
        guard let url = AppServices.remoteSessions.artworkURL(for: session, type: "Primary", width: 160),
              let response = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: response.0),
              let small = await image.byPreparingThumbnail(ofSize: CGSize(width: 64, height: 64 * image.size.height / max(image.size.width, 1)))
        else { return nil }
        for quality in [0.6, 0.4, 0.25] {
            if let jpeg = small.jpegData(compressionQuality: quality), jpeg.count < 2_500 { return jpeg }
        }
        return nil
    }
}

// MARK: - Apple Watch

/// Signs the watch's remote (#458) in as this iPhone: every address of the active profile's
/// server (home, away and the one in use, as the watch may be on either network) and the
/// header the phone signs its own requests with. Sent again whenever the profile changes, and
/// "signed out" on sign-out. The latest one waits in the application context for the watch.
@MainActor
final class WatchLink: NSObject, WCSessionDelegate {
    static let shared = WatchLink()

    func install() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
        followSignIn()
    }

    private func followSignIn() {
        withObservationTracking {
            _ = AppServices.authManager.state.credential
        } onChange: {
            Task { @MainActor in
                WatchLink.shared.send()
                WatchLink.shared.followSignIn()
            }
        }
    }

    private func send() {
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        let context: [String: Any]
        if let credential = AppServices.authManager.state.credential {
            context = [
                "serverURLs": Self.addresses(for: credential),
                "authHeader": AppServices.authManager.authClient.authHeader(token: credential.accessToken),
                "userID": credential.userID,
                "accessToken": credential.accessToken,
            ]
        } else {
            context = ["signedOut": true]
        }
        try? session.updateApplicationContext(context)
    }

    private static func addresses(for credential: ServerCredential) -> [String] {
        let defaults = UserDefaults.standard
        let id = credential.id.uuidString
        let all = [defaults.string(forKey: "serverLocalURL.\(id)"), defaults.string(forKey: "serverRemoteURL.\(id)"),
                   credential.baseURL.absoluteString].compactMap { $0 }.filter { !$0.isEmpty }
        var seen = Set<String>()
        return all.filter { seen.insert($0).inserted }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        Task { @MainActor in WatchLink.shared.send() }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in WatchLink.shared.send() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    /// After switching to another watch: activate again for the new one.
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
