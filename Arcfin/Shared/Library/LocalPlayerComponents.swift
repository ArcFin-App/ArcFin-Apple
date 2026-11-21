// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import MediaEngine

/// Darkens the top and bottom of the picture under the local player's controls.
struct LocalPlayerScrim: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.55), location: 0),
                .init(color: .clear, location: 0.22),
                .init(color: .clear, location: 0.7),
                .init(color: .black.opacity(0.65), location: 1),
            ],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

/// The scrubber, times and play, pause and skip buttons along the local player's bottom edge.
struct LocalPlayerBottomBar: View {
    let model: LocalPlayerModel

    private var player: VLCEnginePlayer { model.player }

    var body: some View {
        VStack(spacing: 10) {
            scrubber
            HStack {
                Text(LocalPlayerModel.timeLabel(ticks: model.shownTicks))
                    .font(.system(.caption, design: .monospaced, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                HStack(spacing: 28) {
                    Button { model.seek(by: -10) } label: {
                        Image(systemName: "gobackward.10").font(.system(.title3)).foregroundStyle(.white)
                    }
                    .accessibilityLabel("Skip back 10 seconds")
                    Button { model.togglePlayPause() } label: {
                        Image(systemName: player.status == .playing ? "pause.fill" : "play.fill")
                            .font(.system(.largeTitle))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(player.status == .playing ? "Pause" : "Play")
                    Button { model.seek(by: 10) } label: {
                        Image(systemName: "goforward.10").font(.system(.title3)).foregroundStyle(.white)
                    }
                    .accessibilityLabel("Skip forward 10 seconds")
                }
                Spacer()
                Text(model.remainingLabel)
                    .font(.system(.caption, design: .monospaced, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.bottom, 24)
    }

    private var scrubber: some View {
        GeometryReader { proxy in
            let duration = max(player.durationTicks, 1)
            let fraction = Double(model.shownTicks) / Double(duration)
            let thumbX = proxy.size.width * min(max(fraction, 0), 1)

            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.25)).frame(height: 4)
                Capsule().fill(DT.Color.accent).frame(width: thumbX, height: 4)
                Circle().fill(.white)
                    .frame(width: model.isScrubbing ? 16 : 10, height: model.isScrubbing ? 16 : 10)
                    .offset(x: thumbX - (model.isScrubbing ? 8 : 5))
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .onScrub(width: proxy.size.width, changed: { model.scrub(to: $0) }, ended: { model.endScrub() })
        }
        .frame(height: 20)
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(LocalPlayerModel.timeLabel(ticks: model.shownTicks)) of \(LocalPlayerModel.timeLabel(ticks: player.durationTicks))")
        .accessibilityAdjustableAction { direction in
            model.seek(by: direction == .increment ? 10 : -10)
        }
    }
}

struct LocalPlayerTrackSheet: View {
    let model: LocalPlayerModel

    private var player: VLCEnginePlayer { model.player }

    var body: some View {
        NavigationStack {
            List {
                Button {
                    Task { await player.setSubtitleTrack(index: nil) }
                    model.showTrackMenu = false
                } label: {
                    HStack {
                        Text("Off")
                        Spacer()
                        if player.selectedSubtitleTrackIndex == nil { Image(systemName: "checkmark").accessibilityHidden(true) }
                    }
                }
                .accessibilityAddTraits(player.selectedSubtitleTrackIndex == nil ? .isSelected : [])
                ForEach(player.availableSubtitleTracks) { track in
                    Button {
                        Task { await player.setSubtitleTrack(index: track.id) }
                        model.showTrackMenu = false
                    } label: {
                        HStack {
                            Text(track.displayName)
                            Spacer()
                            if player.selectedSubtitleTrackIndex == track.id { Image(systemName: "checkmark").accessibilityHidden(true) }
                        }
                    }
                    .accessibilityAddTraits(player.selectedSubtitleTrackIndex == track.id ? .isSelected : [])
                }
            }
            .navigationTitle("Subtitles")
            .inlineNavigationTitle()
        }
        .presentationDetents([.medium])
    }
}
