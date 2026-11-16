// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// What one device plays, laid out like the iPhone remote at watch size: where and what, the
/// position, skip and play or pause, and the Digital Crown for volume. Previous, next, the
/// tracks, mute and stop are in the bar along the bottom.
struct NowPlayingView: View {
    let sessionID: String
    @Environment(WatchRemote.self) private var remote
    @State private var crownVolume = 100.0
    @State private var showsVolume = false
    @State private var volumeTask: Task<Void, Never>?
    @State private var showsMore = false
    /// The crown only turns a view that has focus.
    @FocusState private var crownFocused: Bool

    var body: some View {
        if let session = remote.session(sessionID) {
            content(session)
                .background { artwork(session) }
                .toolbar { bottomBar(session) }
                .sheet(isPresented: $showsMore) { MoreView(sessionID: sessionID) }
                .focusable()
                .focused($crownFocused)
                .digitalCrownRotation($crownVolume, from: 0, through: 100, by: 5, sensitivity: .medium,
                                      isContinuous: false, isHapticFeedbackEnabled: true)
                .onChange(of: crownVolume) { _, volume in turned(to: volume, on: session) }
                .onAppear {
                    crownVolume = Double(session.volumeLevel ?? 100)
                    crownFocused = true
                }
                .onChange(of: showsMore) { _, shown in if !shown { crownFocused = true } }
                .onChange(of: session.volumeLevel) { _, level in
                    // The device's own level, unless the crown is being turned.
                    if volumeTask == nil { crownVolume = Double(level ?? 100) }
                }
        } else {
            ContentUnavailableView("Nothing Playing", systemImage: "av.remote")
        }
    }

    private func content(_ session: WatchSession) -> some View {
        VStack(spacing: 8) {
            VStack(spacing: 2) {
                Text("Playing on \(session.deviceName)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tint)
                    .lineLimit(1)
                Text(session.title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                if let subtitle = session.subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            if showsVolume {
                Gauge(value: crownVolume, in: 0...100) {
                    Image(systemName: "speaker.wave.2.fill")
                }
                .gaugeStyle(.accessoryLinearCapacity)
                .tint(.accentColor)
                .accessibilityHidden(true)
            } else {
                ProgressView(value: Double(remote.position(of: session)), total: Double(max(session.runTimeTicks, 1)))
                    .tint(.accentColor)
                    .accessibilityHidden(true)
            }
            // What the crown is turning.
            Label {
                Text(verbatim: "\(Int(crownVolume))%")
            } icon: {
                Image(systemName: session.isMuted || crownVolume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Volume")
            .accessibilityValue(Text(verbatim: "\(Int(crownVolume))%"))
            HStack {
                Button { remote.skip(session, seconds: -10) } label: {
                    Image(systemName: "gobackward.10")
                }
                .accessibilityLabel("Skip Back")
                Button { remote.playPause(session) } label: {
                    Image(systemName: session.isPaused ? "play.fill" : "pause.fill")
                        .font(.title2)
                }
                .accessibilityLabel(session.isPaused ? "Play" : "Pause")
                Button { remote.skip(session, seconds: 10) } label: {
                    Image(systemName: "goforward.10")
                }
                .accessibilityLabel("Skip Forward")
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
        }
        .padding(.horizontal, 4)
    }

    private func artwork(_ session: WatchSession) -> some View {
        AsyncImage(url: remote.artworkURL(for: session)) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Color.clear
        }
        .overlay(.black.opacity(0.7))
        .blur(radius: 12)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    @ToolbarContentBuilder
    private func bottomBar(_ session: WatchSession) -> some ToolbarContent {
        ToolbarItemGroup(placement: .bottomBar) {
            Button { remote.previous(session) } label: { Image(systemName: "backward.end.fill") }
                .accessibilityLabel("Previous")
            Button { showsMore = true } label: { Image(systemName: "ellipsis") }
                .accessibilityLabel("More")
            Button { remote.next(session) } label: { Image(systemName: "forward.end.fill") }
                .accessibilityLabel("Next")
        }
    }

    /// Sent once the crown rests, so a turn is one change on the device, not twenty.
    private func turned(to volume: Double, on session: WatchSession) {
        guard Int(volume) != session.volumeLevel ?? 100 || volumeTask != nil else { return }
        showsVolume = true
        volumeTask?.cancel()
        volumeTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            remote.setVolume(session, to: Int(volume))
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            showsVolume = false
            volumeTask = nil
        }
    }
}

/// Mute, the audio and subtitle tracks, and stop.
private struct MoreView: View {
    let sessionID: String
    @Environment(WatchRemote.self) private var remote
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            if let session = remote.session(sessionID) {
                List {
                    Button { remote.toggleMute(session) } label: {
                        Label(session.isMuted ? "Unmute" : "Mute",
                              systemImage: session.isMuted ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    }
                    if session.audioTracks.count > 1 {
                        NavigationLink {
                            TrackList(tracks: session.audioTracks, selected: session.audioIndex, allowsOff: false) {
                                if let index = $0 { remote.selectAudio(session, index: index) }
                            }
                            .navigationTitle("Audio")
                        } label: {
                            Label("Audio", systemImage: "speaker.wave.2")
                        }
                    }
                    if !session.subtitleTracks.isEmpty {
                        NavigationLink {
                            TrackList(tracks: session.subtitleTracks, selected: session.subtitleIndex.flatMap { $0 < 0 ? nil : $0 },
                                      allowsOff: true) {
                                remote.selectSubtitle(session, index: $0)
                            }
                            .navigationTitle("Subtitles")
                        } label: {
                            Label("Subtitles", systemImage: "captions.bubble")
                        }
                    }
                    Button(role: .destructive) {
                        remote.stopPlayback(session)
                        dismiss()
                    } label: {
                        Label("Stop Playback", systemImage: "stop.fill")
                    }
                }
            } else {
                ContentUnavailableView("Nothing Playing", systemImage: "av.remote")
            }
        }
    }
}

private struct TrackList: View {
    let tracks: [WatchSession.Track]
    let selected: Int?
    let allowsOff: Bool
    let choose: (Int?) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if allowsOff {
                row(Text("Off"), isSelected: selected == nil) { choose(nil) }
            }
            ForEach(tracks) { track in
                row(Text(verbatim: track.title), isSelected: track.index == selected) { choose(track.index) }
            }
        }
    }

    private func row(_ title: Text, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            dismiss()
        } label: {
            HStack {
                title
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                }
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
