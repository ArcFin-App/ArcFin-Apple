// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import MediaEngine
import Persistence

/// The chosen subtitle line, over the picture and clear of the controls.
struct OfflineSubtitleOverlay: View {
    let text: String
    let isControlsVisible: Bool

    @AppStorage("subtitleTextSize") private var subtitleTextSize = SubtitleTextSize.medium
    @AppStorage("subtitleTextColor") private var subtitleTextColor = SubtitleTextColorOption.white
    @AppStorage("subtitleBackgroundStyle") private var subtitleBackgroundStyle = SubtitleBackgroundStyle.outline

    var body: some View {
        // See PlayerView+Controls.subtitleOverlay — the fixed bottom padding alone
        // isn't a substitute for the safe area; reading the real inset via
        // GeometryReader and adding it explicitly guarantees clearance from the
        // home indicator regardless of what the rest of the hierarchy is doing
        // with safe areas.
        GeometryReader { proxy in
            VStack {
                Spacer()
                SubtitleText(text: text, size: subtitleTextSize, color: subtitleTextColor, background: subtitleBackgroundStyle)
                    .padding(.horizontal, 24)
                    .padding(.bottom, (isControlsVisible ? 110 : 32) + proxy.safeAreaInsets.bottom)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Skip Recap, Intro, Credits or Preview while one is playing, filling up while it counts down
/// to skipping by itself.
struct OfflinePlayerSkipButton: View {
    let model: OfflinePlayerModel

    var body: some View {
        if let current = model.currentSkippable {
            HStack {
                Spacer()
                Button {
                    model.skipNow(kind: current.kind, span: current.span)
                } label: {
                    HStack(spacing: 6) {
                        Text(current.label).font(.system(.footnote, design: .default, weight: .semibold))
                        Image(systemName: "forward.fill").font(.system(.caption))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background {
                        if let autoSkipCountdown = model.autoSkipCountdown, autoSkipCountdown.kind == current.kind {
                            CountdownFill(countdown: autoSkipCountdown, color: .white.opacity(0.25))
                        }
                    }
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: DT.Radius.lg))
                }
                .buttonStyle(.plain)
                .padding(.trailing, DT.Spacing.pagePad)
                .padding(.bottom, 100)
            }
        }
    }
}

/// The scrubber, with trickplay while dragging, the times and play, pause and skip buttons
/// along the offline player's bottom edge.
struct OfflinePlayerBottomBar: View {
    let model: OfflinePlayerModel

    @AppStorage("skipForwardSeconds") private var skipForwardSeconds = 10
    @AppStorage("skipBackwardSeconds") private var skipBackwardSeconds = 10

    private var player: any MediaPlayerProtocol { model.player }

    var body: some View {
        VStack(spacing: 10) {
            scrubber
            HStack {
                Text(OfflinePlayerModel.timeLabel(ticks: model.shownTicks))
                    .font(.system(.caption, design: .monospaced, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                HStack(spacing: 28) {
                    Button { model.seek(by: -skipBackwardSeconds) } label: {
                        Image(systemName: skipIconName(seconds: skipBackwardSeconds, forward: false))
                            .font(.system(.title3)).foregroundStyle(.white)
                    }
                    .accessibilityLabel("Skip back \(skipBackwardSeconds) seconds")
                    Button { model.togglePlayPause() } label: {
                        Image(systemName: player.status == .playing ? "pause.fill" : "play.fill")
                            .font(.system(.largeTitle))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(player.status == .playing ? "Pause" : "Play")
                    Button { model.seek(by: skipForwardSeconds) } label: {
                        Image(systemName: skipIconName(seconds: skipForwardSeconds, forward: true))
                            .font(.system(.title3)).foregroundStyle(.white)
                    }
                    .accessibilityLabel("Skip forward \(skipForwardSeconds) seconds")
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

                if model.isScrubbing, !model.downloadedItem.trickplayFileNames.isEmpty {
                    trickplayPreview
                        .offset(x: min(max(thumbX - 70, 0), proxy.size.width - 140), y: -100)
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .onScrub(width: proxy.size.width, changed: { model.scrub(to: $0) }, ended: { model.endScrub() })
        }
        .frame(height: 20)
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(OfflinePlayerModel.timeLabel(ticks: model.shownTicks)) of \(OfflinePlayerModel.timeLabel(ticks: player.durationTicks))")
        .accessibilityAdjustableAction { direction in
            model.seek(by: direction == .increment ? skipForwardSeconds : -skipBackwardSeconds)
        }
    }

    private var trickplayPreview: some View {
        Group {
            if let image = model.trickplayImage(forTicks: Int64(model.scrubTicks)) {
                Image(platformImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Color.black
            }
        }
        .frame(width: 140, height: 79)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.3), lineWidth: 1))
        .shadow(radius: 8)
        .allowsHitTesting(false)
    }
}

/// The download's audio tracks, when it has more than one, and off or one of the subtitle
/// files saved with it.
struct OfflineSubtitleSheet: View {
    let model: OfflinePlayerModel

    var body: some View {
        NavigationStack {
            List {
                if model.player.availableAudioTracks.count > 1 {
                    Section("Audio") {
                        ForEach(model.player.availableAudioTracks) { track in
                            Button {
                                Task { await model.player.setAudioTrack(index: track.id) }
                                model.showTrackMenu = false
                            } label: {
                                HStack {
                                    Text(verbatim: Self.audioName(track))
                                    Spacer()
                                    if model.player.selectedAudioTrackIndex == track.id {
                                        Image(systemName: "checkmark").accessibilityHidden(true)
                                    }
                                }
                            }
                            .accessibilityAddTraits(model.player.selectedAudioTrackIndex == track.id ? .isSelected : [])
                        }
                    }
                }
                if !model.downloadedItem.subtitleFileNames.isEmpty {
                    Section("Subtitles") { subtitleRows }
                }
            }
            .navigationTitle(model.downloadedItem.subtitleFileNames.isEmpty ? "Audio" : "Audio & Subtitles")
            .inlineNavigationTitle()
        }
        .presentationDetents([.medium])
    }

    /// A track added to a converted download has no title, only its language.
    private static func audioName(_ track: AudioTrack) -> String {
        guard track.displayName.isEmpty || track.displayName.lowercased().hasPrefix("track"),
              let language = track.language, let name = Locale.current.localizedString(forLanguageCode: language)
        else { return track.displayName }
        return name
    }

    @ViewBuilder
    private var subtitleRows: some View {
                Button {
                    model.loadSubtitles(index: nil)
                    model.showTrackMenu = false
                } label: {
                    HStack {
                        Text("Off")
                        Spacer()
                        if model.selectedSubtitleIndex == nil { Image(systemName: "checkmark").accessibilityHidden(true) }
                    }
                }
                .accessibilityAddTraits(model.selectedSubtitleIndex == nil ? .isSelected : [])
                ForEach(model.downloadedItem.subtitleLanguages.indices, id: \.self) { index in
                    Button {
                        model.loadSubtitles(index: index)
                        model.showTrackMenu = false
                    } label: {
                        HStack {
                            Text(model.downloadedItem.subtitleLanguages[index])
                            Spacer()
                            if model.selectedSubtitleIndex == index { Image(systemName: "checkmark").accessibilityHidden(true) }
                        }
                    }
                    .accessibilityAddTraits(model.selectedSubtitleIndex == index ? .isSelected : [])
                }
    }
}
