// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AVFoundation
import CastKit
import JellyfinAPI

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
                if !editing, let volume {
                    remote.setVolume(Int(volume))
                    self.volume = nil
                }
            }
            .tint(DT.Color.accent)
            .accessibilityLabel("Volume")
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
/// open. The buttons only reach the app as changes to the phone's own volume, so a press at
/// either end of its range would go unheard: the volume is moved back to the middle there.
/// The phone's volume is put back as it was when the remote closes.
@MainActor
final class RemoteVolumeButtons {
    private var observation: NSKeyValueObservation?
    private var hiddenSlider: SystemVolumeController?
    private var originalVolume: Float?
    private var settingTo: Float?

    func start(onPress: @escaping @MainActor (Bool) -> Void) {
        guard observation == nil else { return }
        let session = AVAudioSession.sharedInstance()
        // Mixes, so music playing on the phone carries on. Active, or the buttons change the
        // ringer and the app hears nothing.
        try? session.setCategory(.playback, options: .mixWithOthers)
        try? session.setActive(true)
        hiddenSlider = SystemVolumeController()
        originalVolume = session.outputVolume
        recentre(session.outputVolume)
        observation = session.observe(\.outputVolume, options: [.old, .new]) { [weak self] _, change in
            guard let new = change.newValue, let old = change.oldValue else { return }
            Task { @MainActor in self?.changed(from: old, to: new, onPress: onPress) }
        }
    }

    func stop() {
        observation?.invalidate()
        observation = nil
        if let originalVolume, abs(AVAudioSession.sharedInstance().outputVolume - originalVolume) > 0.001 {
            hiddenSlider?.setVolume(originalVolume)
        }
        originalVolume = nil
        hiddenSlider?.teardown()
        hiddenSlider = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func changed(from old: Float, to new: Float, onPress: @MainActor (Bool) -> Void) {
        if let settingTo, abs(new - settingTo) < 0.01 {
            self.settingTo = nil
            return
        }
        guard abs(new - old) > 0.001 else { return }
        onPress(new > old)
        recentre(new)
    }

    private func recentre(_ volume: Float) {
        guard volume > 0.95 || volume < 0.05 else { return }
        settingTo = 0.5
        hiddenSlider?.setVolume(0.5)
    }
}
