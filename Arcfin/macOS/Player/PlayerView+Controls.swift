// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import JellyfinAPI
import MediaEngine
import CastKit
import GroupActivities

extension PlayerView {

    // MARK: - Controls overlay

    var controlsOverlay: some View {
        // GeometryReader here does NOT ignoresSafeArea() itself, so proxy.size reports the
        // safe-area-inset region — topBar/bottomBar still position exactly as before, only
        // the background below bleeds past it. Needed for the width tapGesture takes, and
        // to give the middle gap below an actual frame to fill.
        GeometryReader { proxy in
            VStack(spacing: 0) {
                topBar
                // A plain Spacer() here left the whole middle of the screen hit-testable
                // (via the background below) but with nothing wired to handle a touch that
                // landed on it — once controls were visible, double-tapping to seek again or
                // tapping to dismiss them early just silently did nothing, since the tap
                // never reached videoSurface's gesture underneath. Giving this region the
                // exact same gesture lets it behave like the video surface whenever it's the
                // one actually receiving the touch.
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(macTapGesture(width: proxy.size.width))
                bottomBar
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background(
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
            )
        }
    }

    private var topBar: some View {
        HStack(spacing: 16) {
            Button { closePlayer() } label: {
                Image(systemName: "chevron.down")
                    .font(.system(.title3, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .scaledFont(size: 15, weight: .semibold)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let hdrLabel = model.hdrLabel {
                        Text(hdrLabel)
                            .font(.system(.caption2, design: .default, weight: .bold))
                            .tracking(0.5)
                            .foregroundStyle(model.hdrIsToneMapped ? .black : .white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(
                                model.hdrIsToneMapped ? DT.Color.palette("F59E0B") : Color.clear,
                                in: Capsule()
                            )
                            .overlay(
                                Capsule().stroke(.white.opacity(model.hdrIsToneMapped ? 0 : 0.4), lineWidth: 1)
                            )
                    }
                }
                if let subtitle = model.episodeSubtitle {
                    Text(subtitle)
                        .scaledFont(size: 12)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }

            Spacer()

            if !model.castMembers.isEmpty { castPanelButton }

            macQuickActionIcons

            moreMenu
        }
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.top, 8)
    }

    // MARK: - Quick-access controls

    private struct QuickAction: Identifiable {
        let id: String
        let icon: String
        let perform: () -> Void

        var label: LocalizedStringKey {
            switch id {
            case "rotate": "Rotate"
            case "fill": "Fill screen"
            case "fullscreen": "Toggle full screen"
            case "chapters": "Chapters"
            case "tracks": "Subtitles and audio"
            case "channels": "Channels"
            default: "Playback speed"
            }
        }
    }

    /// No rotate button (nothing to rotate on a windowed player) — Fill Screen and window
    /// Fullscreen are two distinct concepts here, so both get their own icon: Fill Screen
    /// changes how the video scales within the player view, Fullscreen changes the window
    /// itself (see toggleMacWindowFullScreen). AirPlay is a plain visible button instead of
    /// hidden/triggered — see AirPlayButton's macOS variant for why.
    private var macQuickActionItems: [QuickAction] {
        var items: [QuickAction] = [
            QuickAction(
                id: "fill",
                icon: model.isFillScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
            ) { model.isFillScreen.toggle() },
            QuickAction(
                id: "fullscreen",
                icon: isMacFullScreen ? "arrow.down.right.and.arrow.up.left.circle" : "arrow.up.left.and.arrow.down.right.circle"
            ) { toggleMacWindowFullScreen(macWindow) },
        ]
        if chapterListEnabled, !model.chapters.isEmpty {
            items.append(QuickAction(id: "chapters", icon: "list.bullet") { showChapterMenu = true })
        }
        if !model.liveChannels.isEmpty {
            items.append(QuickAction(id: "channels", icon: "list.bullet.rectangle") {
                withAnimation(DT.Animation.fast) { model.showChannelList = true }
            })
        }
        items.append(QuickAction(id: "tracks", icon: "captions.bubble") { showTrackMenu = true })
        if !model.isLive {
            items.append(QuickAction(id: "speed", icon: "gauge.with.dots.needle.67percent") { showRateMenu = true })
        }
        return items
    }

    private var macQuickActionIcons: some View {
        HStack(spacing: 14) {
            ForEach(macQuickActionItems) { action in
                Button(action: action.perform) {
                    Image(systemName: action.icon)
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                }
                .accessibilityLabel(action.label)
                .buttonStyle(.plain)
            }
            AirPlayButton(player: (model.player as? AVFoundationPlayer)?.player)
                .frame(width: 22, height: 22)
        }
    }

    private var moreMenu: some View {
        Menu {
            if canPictureInPicture {
                Button { togglePiP() } label: {
                    Label("Picture in Picture", systemImage: "pip.enter")
                }
            }
            if supportsMultipleWindows, !isPlayerWindow {
                Button { openInNewWindow() } label: {
                    Label("Open in New Window", systemImage: "macwindow.badge.plus")
                }
            }

            // SyncPlay keeps everyone at the same position; a channel has none to share.
            if syncPlayEnabled && ProfileRules.shared.canUseSyncPlay && !model.isLive {
                Button { showSyncPlayMenu = true } label: {
                    Label("SyncPlay", systemImage: syncPlayManager.isInGroup ? "person.2.wave.2.fill" : "person.2.wave.2")
                }
            }
            if !model.isLive { sharePlayMenuItem }

            if !model.castMembers.isEmpty {
                Button { openCastPanel() } label: {
                    Label("Cast & Characters", systemImage: "person.2")
                }
            }

            Button { withAnimation { audioOnly.toggle() } } label: {
                Label(audioOnly ? "Show Video" : "Audio Only", systemImage: audioOnly ? "video" : "waveform")
            }
            Button { showTrackMenu = true } label: {
                Label("Subtitles & Audio", systemImage: "captions.bubble")
            }
            if let info = model.playbackInfo, info.versions.count > 1 {
                Picker(selection: Binding(get: { info.mediaSourceId }, set: { model.changeVersion($0) })) {
                    ForEach(info.versions) { Text($0.name).tag($0.id) }
                } label: {
                    Label("Version", systemImage: "square.stack")
                }
                .pickerStyle(.menu)
            }
            if !model.isLive {
                Button { showRateMenu = true } label: {
                    Label("Playback Speed", systemImage: "gauge.with.dots.needle.67percent")
                }
            }
            subtitleTimingMenu
            Button { showQualityMenu = true } label: {
                Label("Quality", systemImage: "slider.horizontal.3")
            }
            sleepTimerMenu
            Button { showInfoSheet = true } label: {
                Label("Media Info", systemImage: "info.circle")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(.title3, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("More options")
    }

    @ViewBuilder
    private var subtitleTimingMenu: some View {
        if !model.subtitleCues.isEmpty {
            Menu {
                Button("Later by 0.5 s") { model.subtitleDelay += 0.5 }
                Button("Earlier by 0.5 s") { model.subtitleDelay -= 0.5 }
                Button("Later by 0.1 s") { model.subtitleDelay += 0.1 }
                Button("Earlier by 0.1 s") { model.subtitleDelay -= 0.1 }
                Button("Reset", role: .destructive) { model.subtitleDelay = 0 }
                    .disabled(model.subtitleDelay == 0)
            } label: {
                Label(
                    model.subtitleDelay == 0 ? "Subtitle Timing" : "Subtitle Timing (\(String(format: "%+.1f", model.subtitleDelay)) s)",
                    systemImage: "clock.arrow.2.circlepath")
            }
        }
    }

    private var sleepTimerMenu: some View {
        Menu {
            Button("Off") { model.setSleepTimer(minutes: nil) }
            ForEach([15, 30, 45, 60], id: \.self) { minutes in
                Button("\(minutes) minutes") { model.setSleepTimer(minutes: minutes) }
            }
            if item.type == .episode {
                Button("End of Episode") { model.setSleepTimer(minutes: nil, atEndOfItem: true) }
            }
        } label: {
            Label(
                model.sleepTimerEndsAt != nil || model.sleepAtEndOfItem ? "Sleep Timer (On)" : "Sleep Timer",
                systemImage: "moon.zzz")
        }
    }

    /// Every button already has a 44 pt target; the gaps keep the pointer off the neighbouring one.
    private var transportSpacing: CGFloat {
        32
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            if model.isLive {
                LiveProgramBar(program: model.liveProgram)
            } else {
                PlayerScrubber(model: model)
            }

            HStack {
                if model.isLive {
                    LivePositionBadge(behindSeconds: model.secondsBehindLive) { model.jumpToLive() }
                } else {
                    Text(model.timeLabel(ticks: model.elapsedTicks))
                        .font(.system(.caption, design: .monospaced, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .contentTransition(.numericText())
                        .animation(model.isScrubbing ? nil : .default, value: model.elapsedTicks)
                }

                Spacer()

                HStack(spacing: transportSpacing) {
                    if model.previousItem != nil {
                        Button { model.playPrevious() } label: {
                            Image(systemName: "backward.end.fill")
                                .font(.system(.title3)).foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel(previousLabel)
                        .help(model.isLive ? "Previous Channel" : "Previous")
                    }
                    if !model.isLive || model.canRewindLive {
                        Button { model.seek(by: -skipBackwardSeconds) } label: {
                            Image(systemName: skipIconName(seconds: skipBackwardSeconds, forward: false))
                                .font(.system(.title3)).foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                    }
                    Button { model.togglePlayPause() } label: {
                        Image(systemName: playPauseIconIsPlaying ? "pause.fill" : "play.fill")
                            .font(.system(.largeTitle))
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .contentShape(Rectangle())
                    }
                    if !model.isLive || model.canRewindLive {
                        Button { model.seek(by: skipForwardSeconds) } label: {
                            Image(systemName: skipIconName(seconds: skipForwardSeconds, forward: true))
                                .font(.system(.title3)).foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                    }
                    if let nextEpisode = model.nextEpisode {
                        Button { model.playNextEpisode() } label: {
                            Image(systemName: "forward.end.fill")
                                .font(.system(.title3)).foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel(model.isLive ? "Next channel: \(nextEpisode.name)" : "Next: \(nextEpisode.name)")
                        .help(model.isLive ? "Next Channel" : "Next")
                    }
                }

                Spacer()

                if model.isLive {
                    // Balances the badge so the transport stays centred.
                    LiveBadge().hidden()
                } else {
                    Text(model.remainingLabel)
                        .font(.system(.caption, design: .monospaced, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .contentTransition(.numericText())
                        .animation(.default, value: model.remainingTicks)
                }
            }
        }
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.bottom, 24)
    }

    private var previousLabel: String {
        guard let previous = model.previousItem else { return String(localized: "Previous") }
        return model.isLive ? String(localized: "Previous channel: \(previous.name)") : String(localized: "Previous: \(previous.name)")
    }

    /// `player.status` alone stays `.paused` for the whole duration of a Cast session (see
    /// startCasting) — on platforms that support Cast, the icon needs to reflect the
    /// receiver's actual state instead, or it reads as "stuck paused" while casting.
    var playPauseIconIsPlaying: Bool {
        model.isEffectivelyPlaying
    }

    // MARK: - Cast & Characters

    func openCastPanel() {
        withAnimation(DT.Animation.fast) {
            showCastPanel = true
            model.isControlsVisible = false
        }
    }

    private var castPanelButton: some View {
        Button { openCastPanel() } label: {
            Label("Cast & Characters", systemImage: "person.2.fill")
                .labelStyle(.titleAndIcon)
                .font(.system(.caption, weight: .bold))
                .lineLimit(1)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(Color.white.opacity(0.15), in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 1))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    func openCastPanelPerson(_ person: MediaPerson) {
        Task { await model.player.pause() }
        castPanelPerson = person
    }

    /// Carries on from here in a window of its own, so the app stays usable beside it.
    func openInNewWindow() {
        openWindow(value: PlayerWindowRequest(itemId: item.id, startTicks: model.player.positionTicks))
        closePlayer()
    }

    // MARK: - SharePlay

    /// In a FaceTime call SharePlay starts straight away; otherwise the share sheet offers it.
    /// Apple TV has no share sheet, so there it only shows during a call.
    @ViewBuilder
    var sharePlayMenuItem: some View {
        if sharePlay.isActive {
            Button(role: .destructive) { sharePlay.leave() } label: {
                Label(sharePlay.participantCount > 1 ? "Leave SharePlay (\(sharePlay.participantCount))" : "Leave SharePlay",
                      systemImage: "shareplay.slash")
            }
        } else if groupState.isEligibleForGroupSession {
            Button { sharePlay.start(item) } label: {
                Label("SharePlay", systemImage: "shareplay")
            }
        } else {
            ShareLink(item: WatchTogetherItem(activity: sharePlay.activity(for: item)),
                      preview: SharePreview(item.type == .episode ? (item.seriesName ?? item.name) : item.name)) {
                Label("SharePlay", systemImage: "shareplay")
            }
        }
    }

    /// Same visual language as the iPhone and iPad player's dragAxisIndicator (there's no brightness axis to show on
    /// macOS — no touch-drag gesture, and no public per-app brightness control either — so
    /// this is volume-only), triggered by the Up/Down arrow key shortcuts instead of a drag.
    func macVolumeIndicator(_ volume: Double) -> some View {
        HStack {
            Spacer()
            VStack(spacing: 10) {
                Image(systemName: volume < 0.01 ? "speaker.slash.fill" : volume < 0.5 ? "speaker.wave.1.fill" : "speaker.wave.3.fill")
                    .font(.system(.title3))
                    .foregroundStyle(.white)
                ZStack(alignment: .bottom) {
                    Capsule().fill(.white.opacity(0.2)).frame(width: 6, height: 90)
                    Capsule().fill(.white).frame(width: 6, height: 90 * volume)
                }
                Text(Double(volume), format: .percent.precision(.fractionLength(0)).rounded(rule: .down))
                    .font(.system(.caption2, design: .monospaced, weight: .semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .animation(.default, value: volume)
            }
            .padding(14)
            .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: DT.Radius.lg))
        }
        .padding(.horizontal, 32)
        .transition(.opacity)
        .allowsHitTesting(false)
    }

    // MARK: - macOS menu panels
    // .sheet doesn't reliably present from PlayerView on macOS — see the note where these
    // are used in the body. Rendered as plain in-place overlay panels instead, reusing the
    // same content views the iOS/tvOS .sheet presentations already use.

    func macMenuBackdrop(dismiss: @escaping () -> Void) -> some View {
        Color.black.opacity(0.35)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture { dismiss() }
            .accessibilityHidden(true)
            .transition(.opacity)
    }

    func macMenuPanel<Content: View>(title: String, onDone: @escaping () -> Void, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(.subheadline, design: .default, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Button("Done", action: onDone)
                    .buttonStyle(.plain)
                    .foregroundStyle(DT.Color.accent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Divider().overlay(.white.opacity(0.1))
            content()
        }
        .frame(width: 380, height: 420)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.1), lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 30)
        .transition(.scale(scale: 0.95).combined(with: .opacity))
    }

    var macTrackSelectionPanel: some View {
        macMenuPanel(title: "Subtitles & Audio", onDone: { showTrackMenu = false }) {
            TrackSelectionSheet(
                audioStreams: model.playbackInfo?.audioStreams ?? [],
                subtitleStreams: model.playbackInfo?.subtitleStreams ?? [],
                selectedAudioIndex: model.selectedAudioIndex,
                selectedSubtitleIndex: model.selectedSubtitleIndex,
                onSelectAudio: { index in
                    showTrackMenu = false
                    model.changeTrack(audioIndex: index)
                },
                onSelectSubtitle: { index in
                    showTrackMenu = false
                    model.changeTrack(subtitleIndex: .some(index))
                },
                audioDescriptionIndices: model.audioDescriptionIndices
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    var macChapterListPanel: some View {
        macMenuPanel(title: "Chapters", onDone: { showChapterMenu = false }) {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(model.chapters.enumerated()), id: \.offset) { index, chapter in
                        let isCurrent = model.currentChapterIndex == index
                        Button {
                            showChapterMenu = false
                            model.jumpToChapter(chapter)
                        } label: {
                            HStack(spacing: 12) {
                                ChapterThumbnailView(loader: model.trickplayLoader, positionTicks: chapter.startPositionTicks)
                                Text(chapter.name ?? "Chapter \(index + 1)")
                                    .font(.system(.footnote, design: .default, weight: isCurrent ? .semibold : .regular))
                                    .foregroundStyle(isCurrent ? DT.Color.accent : DT.Color.textPrimary)
                                Spacer()
                                Text(model.timeLabel(ticks: chapter.startPositionTicks))
                                    .font(.system(.footnote, design: .monospaced))
                                    .foregroundStyle(DT.Color.textSecondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Menus

    @ViewBuilder
    var qualityMenuButtons: some View {
        // Don't offer a resolution the source can't actually supply (e.g. 4K for a 1080p
        // source) — Jellyfin would just upscale into a bigger, pointless transcode.
        let sourceHeight = model.playbackInfo?.videoStream?.height
        ForEach(VideoQuality.allCases.filter { q in
            guard let minHeight = q.minSourceHeight, let sourceHeight else { return true }
            return sourceHeight >= minHeight
        }) { q in
            Button(q.label + (q == model.quality ? " ✓" : "")) { model.changeQuality(to: q) }
        }
        Button("Cancel", role: .cancel) {}
    }

    @ViewBuilder
    var rateMenuButtons: some View {
        ForEach(PlayerModel.rateOptions, id: \.self) { rate in
            Button(model.rateLabel(rate) + (rate == model.player.playbackRate ? " ✓" : "")) {
                model.choosePlaybackRate(rate)
            }
        }
        Button("Cancel", role: .cancel) {}
    }
}
