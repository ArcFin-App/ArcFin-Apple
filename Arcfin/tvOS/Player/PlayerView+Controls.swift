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
                TVPlayerControlLabel(systemImage: "chevron.down", size: 15, diameter: 34)
            }
            .accessibilityLabel("Close Player")
            .buttonStyle(TVCardButtonStyle())
            .focusEffectDisabled()

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

            // Everything the touch and Mac players' moreMenu holds (Subtitles & Audio, Speed,
            // Quality, Chapters, Info) lives as its own reachable button in bottomBar's
            // leftSecondaryActions/rightSecondaryActions instead — a remote shouldn't need
            // to open a menu just to find them.
        }
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.top, 8)
        .focusSection()
    }

    private var subtitleTimingEntry: TVMenuEntry {
        let title = model.subtitleDelay == 0
            ? String(localized: "Subtitle Timing")
            : String(localized: "Subtitle Timing (\(model.subtitleDelay.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always()))) s)")
        return TVMenuEntry(title: title, systemImage: "clock.arrow.2.circlepath", children: [
            TVMenuEntry(title: String(localized: "Later by 0.5 s")) { model.subtitleDelay += 0.5 },
            TVMenuEntry(title: String(localized: "Earlier by 0.5 s")) { model.subtitleDelay -= 0.5 },
            TVMenuEntry(title: String(localized: "Later by 0.1 s")) { model.subtitleDelay += 0.1 },
            TVMenuEntry(title: String(localized: "Earlier by 0.1 s")) { model.subtitleDelay -= 0.1 },
            TVMenuEntry(title: String(localized: "Reset"), isDestructive: true, isDisabled: model.subtitleDelay == 0) {
                model.subtitleDelay = 0
            },
        ])
    }

    private var sleepTimerEntry: TVMenuEntry {
        var choices = [TVMenuEntry(title: String(localized: "Off")) { model.setSleepTimer(minutes: nil) }]
        choices += [15, 30, 45, 60].map { (minutes: Int) in
            TVMenuEntry(title: String(localized: "\(minutes) minutes")) { model.setSleepTimer(minutes: minutes) }
        }
        if item.type == .episode {
            choices.append(TVMenuEntry(title: String(localized: "End of Episode")) {
                model.setSleepTimer(minutes: nil, atEndOfItem: true)
            })
        }
        let isOn = model.sleepTimerEndsAt != nil || model.sleepAtEndOfItem
        return TVMenuEntry(title: isOn ? String(localized: "Sleep Timer (On)") : String(localized: "Sleep Timer"),
                           systemImage: "moon.zzz", children: choices)
    }

    /// Every button already has a 44 pt target; the gaps keep thumbs off the neighbouring one.
    /// A phone held upright with Previous and Next too is the one layout short on room.
    private var transportSpacing: CGFloat {
        let crowded = model.previousItem != nil || model.nextEpisode != nil
        return crowded ? 12 : 20
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            if model.isLive {
                // Nothing to scrub on a channel, so nothing here to focus either.
                HStack(spacing: 16) {
                    LivePositionBadge(behindSeconds: model.secondsBehindLive) { model.jumpToLive() }
                    LiveProgramBar(program: model.liveProgram)
                }
            } else {
                scrubber

                // Time labels moved off the buttons row when that row's left/right slots became
                // leftSecondaryActions/rightSecondaryActions — they belong at the scrubber's own
                // two ends regardless of what's in the row below it.
                HStack {
                    PlayerTimeLabel(model: model, remaining: false)
                        .scaledFont(size: 12, weight: .medium, design: .monospaced)
                        .foregroundStyle(.white.opacity(0.8))
                    Spacer()
                    PlayerTimeLabel(model: model, remaining: true)
                        .scaledFont(size: 12, weight: .medium, design: .monospaced)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }

            HStack {
                leftSecondaryActions
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: transportSpacing) {
                    if model.previousItem != nil {
                        Button { model.playPrevious() } label: {
                            TVPlayerControlLabel(systemImage: "backward.end.fill", size: 16, diameter: 38)
                        }
                        .accessibilityLabel(previousLabel)
                    }
                    if !model.isLive || model.canRewindLive {
                        Button { model.seek(by: -skipBackwardSeconds) } label: {
                            TVPlayerControlLabel(systemImage: skipIconName(seconds: skipBackwardSeconds, forward: false), size: 16, diameter: 38)
                        }
                        .accessibilityLabel("Skip Back")
                    }
                    Button { model.togglePlayPause() } label: {
                        TVPlayerControlLabel(systemImage: playPauseIconIsPlaying ? "pause.fill" : "play.fill", size: 22, diameter: 48)
                    }
                    .accessibilityLabel(playPauseIconIsPlaying ? "Pause" : "Play")
                    .prefersDefaultFocus(!model.tvControlsHidden, in: tvFocusNamespace)
                    if !model.isLive || model.canRewindLive {
                        Button { model.seek(by: skipForwardSeconds) } label: {
                            TVPlayerControlLabel(systemImage: skipIconName(seconds: skipForwardSeconds, forward: true), size: 16, diameter: 38)
                        }
                        .accessibilityLabel("Skip Forward")
                    }
                    if let nextEpisode = model.nextEpisode {
                        Button { model.playNextEpisode() } label: {
                            TVPlayerControlLabel(systemImage: "forward.end.fill", size: 16, diameter: 38)
                        }
                        .accessibilityLabel(model.isLive ? "Next channel: \(nextEpisode.name)" : "Next: \(nextEpisode.name)")
                    }
                }
                .buttonStyle(TVCardButtonStyle())
                .focusEffectDisabled()
                .focusSection()

                rightSecondaryActions
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.bottom, 24)
    }

    // Everything that used to live inside moreMenu on tvOS, promoted to its own reachable
    // button, split across both sides of the transport controls in the same row rather than
    // a separate row of its own. Both side groups are pinned to an equal-width .infinity
    // frame (leading/trailing aligned) rather than plain Spacers, so the transport controls
    // in the middle land at the true center regardless of the two sides holding a different
    // number of buttons (left has 2, right has 3) — a Spacer-only layout would have skewed
    // the transport group off-center toward whichever side was narrower.
    private var leftSecondaryActions: some View {
        HStack(spacing: 12) {
            Button { showTrackMenu = true } label: {
                TVPlayerControlLabel(systemImage: "captions.bubble", size: 14, diameter: 32)
            }
            .accessibilityLabel("Subtitles & Audio")
            if !model.isLive {
                Button { showRateMenu = true } label: {
                    TVPlayerControlLabel(systemImage: "gauge.with.dots.needle.67percent", size: 14, diameter: 32)
                }
                .accessibilityLabel("Playback Speed")
            }
        }
        .buttonStyle(TVCardButtonStyle())
        .focusEffectDisabled()
        .focusSection()
    }

    private var rightSecondaryActions: some View {
        HStack(spacing: 12) {
            if model.hasChannelList {
                Button { withAnimation(DT.Animation.fast) { model.showChannelList = true } } label: {
                    TVPlayerControlLabel(systemImage: "list.bullet.rectangle", size: 14, diameter: 32)
                }
                .accessibilityLabel("Channels")
            }
            Button { showQualityMenu = true } label: {
                TVPlayerControlLabel(systemImage: "slider.horizontal.3", size: 14, diameter: 32)
            }
            .accessibilityLabel("Quality")
            if chapterListEnabled, !model.chapters.isEmpty {
                Button { showChapterMenu = true } label: {
                    TVPlayerControlLabel(systemImage: "list.bullet", size: 14, diameter: 32)
                }
                .accessibilityLabel("Chapters")
            }
            Button { showInfoSheet = true } label: {
                TVPlayerControlLabel(systemImage: "info.circle", size: 14, diameter: 32)
            }
            .accessibilityLabel("Media Info")
            TVMenuButton(systemImage: "ellipsis", accessibilityLabel: String(localized: "More options"),
                         entries: moreMenuEntries) { model.handleMenuVisibilityChange($0) }
        }
        .buttonStyle(TVCardButtonStyle())
        .focusEffectDisabled()
        .focusSection()
    }

    private var previousLabel: String {
        guard let previous = model.previousItem else { return String(localized: "Previous") }
        return model.isLive ? String(localized: "Previous channel: \(previous.name)") : String(localized: "Previous: \(previous.name)")
    }

    /// Something besides the transport controls that the remote should land on.
    private var tvOverlayHasFocusTarget: Bool {
        model.showStillWatchingPrompt || (model.showUpNext && model.nextEpisode != nil)
            || (model.showMoreLikeThis && !model.moreLikeThis.isEmpty) || showCastPanel
    }

    /// With the controls hidden, an invisible catcher holds focus, so a click never presses a
    /// button nobody can see.
    var tvCatcherActive: Bool {
        model.tvControlsHidden && !tvOverlayHasFocusTarget && model.skipButtonLabel == nil && model.errorMessage == nil
            && !model.showChannelList
    }

    /// Changes whenever a different control should hold focus.
    var tvFocusContext: String {
        "\(model.tvControlsHidden)-\(tvCatcherActive)-\(model.skipButtonLabel ?? "")-\(tvOverlayHasFocusTarget)-\(model.errorMessage != nil)-\(model.showChannelList)"
    }

    /// The remote while the controls are hidden, as in the system player: a click or a swipe
    /// up shows them, down opens subtitles and audio, left and right skip back and forward,
    /// or on a channel change to the one before or after it.
    var tvRemoteCatcher: some View {
        Button { model.toggleControlsVisibilityOnAction() } label: {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(TVCardButtonStyle())
        .focusEffectDisabled()
        .prefersDefaultFocus(true, in: tvFocusNamespace)
        // Press and hold the clickpad to play faster until it's let go.
        .onLongPressGesture(minimumDuration: 0.5) {
            model.beginSpeedBoost()
        } onPressingChanged: { pressing in
            if !pressing { model.endSpeedBoost() }
        }
        .onMoveCommand { direction in
            switch direction {
            case .left where model.isLive: model.playPrevious()
            case .right where model.isLive: model.playNextEpisode()
            case .left: tvQuickSeek(forward: false)
            case .right: tvQuickSeek(forward: true)
            // Down opens subtitles and audio, as the system player's info panel does, or on a
            // channel the channel list.
            case .down where model.hasChannelList:
                withAnimation(DT.Animation.fast) { model.showChannelList = true }
            case .down: showTrackMenu = true
            default: model.toggleControlsVisibilityOnAction()
            }
        }
        .accessibilityLabel("Show playback controls")
        .ignoresSafeArea()
    }

    private func tvQuickSeek(forward: Bool) {
        let seconds = forward ? skipForwardSeconds : skipBackwardSeconds
        let base = model.pendingSeekTargetTicks ?? model.player.positionTicks
        model.performSeek(to: min(max(0, base + Int64(forward ? seconds : -seconds) * 10_000_000), model.player.durationTicks))
        let feedback = SeekFeedback(forward: forward, onRight: forward, seconds: seconds)
        model.seekFeedback = feedback
        Task {
            try? await Task.sleep(for: .seconds(0.6))
            if model.seekFeedback == feedback { model.seekFeedback = nil }
        }
    }

    /// Menu steps back one layer at a time: out of a scrub, then hides the controls, then
    /// leaves the player.
    func handleTVExit() {
        if model.showChannelList {
            withAnimation(DT.Animation.fast) { model.showChannelList = false }
        } else if model.isScrubbing {
            model.isScrubbing = false
            model.scrubThumbnail = nil
            model.scheduleAutoHide()
        } else if !model.tvControlsHidden {
            model.hideControlsTask?.cancel()
            withAnimation(DT.Animation.fast) { model.tvControlsHidden = true }
        } else {
            closePlayer()
        }
    }

    /// What the touch and Mac players keep in their More menu and have no button of their own here.
    private var moreMenuEntries: [TVMenuEntry] {
        var entries: [TVMenuEntry] = []
        if !model.castMembers.isEmpty {
            entries.append(TVMenuEntry(title: String(localized: "Cast & Characters"), systemImage: "person.2") { openCastPanel() })
        }
        // SyncPlay keeps everyone at the same position; a channel has none to share.
        if syncPlayEnabled && ProfileRules.shared.canUseSyncPlay && !model.isLive {
            entries.append(TVMenuEntry(title: String(localized: "SyncPlay"),
                                       systemImage: syncPlayManager.isInGroup ? "person.2.wave.2.fill" : "person.2.wave.2") {
                showSyncPlayMenu = true
            })
        }
        if !model.isLive, let sharePlayEntry { entries.append(sharePlayEntry) }
        entries.append(TVMenuEntry(title: audioOnly ? String(localized: "Show Video") : String(localized: "Audio Only"),
                                   systemImage: audioOnly ? "video" : "waveform") {
            withAnimation { audioOnly.toggle() }
        })
        if let info = model.playbackInfo, info.versions.count > 1 {
            entries.append(TVMenuEntry(title: String(localized: "Version"), systemImage: "square.stack",
                                       children: info.versions.map { version in
                TVMenuEntry(title: version.name, isSelected: version.id == info.mediaSourceId) { model.changeVersion(version.id) }
            }))
        }
        if !model.subtitleCues.isEmpty { entries.append(subtitleTimingEntry) }
        entries.append(sleepTimerEntry)
        return entries
    }

    private var scrubber: some View {
        // tvOS has no drag-to-scrub (see the remote handling below) so the bar
        // itself is the only feedback a remote-driven seek gets — thicker here than the
        // touch/mouse platforms, where the gesture itself is the primary feedback.
        GeometryReader { proxy in
            TVScrubberTrack(model: model, width: proxy.size.width)
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                // No drag surface on tvOS — focus the bar and swipe the remote's touch surface
                // left/right to nudge the pending position (with the same trickplay preview),
                // then click to commit. Matches how Apple's own tvOS video player scrubber works.
                .focusable(true)
                .focused($isScrubberFocused)
                .onChange(of: isScrubberFocused) { _, focused in
                    if focused { startRemoteScrub() } else { remoteScrub.stop() }
                }
                .onDisappear { remoteScrub.stop() }
                .onMoveCommand { direction in
                    guard direction == .left || direction == .right, !remoteScrub.suppressesMoveCommands else { return }
                    beginTVScrub()
                    let stepTicks: Double = 10 * 10_000_000
                    model.scrubTicks = direction == .right
                        ? min(model.scrubTicks + stepTicks, Double(model.player.durationTicks))
                        : max(model.scrubTicks - stepTicks, 0)
                    model.updateScrubThumbnail()
                }
                .onTapGesture {
                    guard model.isScrubbing else { return }
                    commitTVScrub()
                }
        }
        .frame(height: 20)
        // The value comes from the track, which reads the position in a view of its own.
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Playback position")
        .accessibilityAdjustableAction { direction in
            model.seek(by: direction == .increment ? skipForwardSeconds : -skipBackwardSeconds)
        }
    }

    /// Clicking or pressing Play/Pause on a scrubbed position plays from there, as Apple's
    /// player does, even if playback was paused.
    func commitTVScrub() {
        let ticks = Int64(model.scrubTicks)
        model.isScrubbing = false
        model.scrubThumbnail = nil
        model.performSeek(to: ticks)
        model.playAfterScrub(at: ticks)
        model.scheduleAutoHide()
    }

    private func beginTVScrub() {
        guard !model.isScrubbing else { return }
        model.isScrubbing = true
        model.scrubTicks = Double(model.pendingSeekTargetTicks ?? model.player.positionTicks)
        model.hideControlsTask?.cancel()
    }

    /// A slide across the whole touch surface covers a tenth of the runtime, kept between one
    /// and ten minutes so short episodes stay precise and long films stay quick to cross.
    private func startRemoteScrub() {
        remoteScrub.start(
            began: {
                beginTVScrub()
                remoteScrubStartTicks = model.scrubTicks
            },
            moved: { travel in
                let duration = Double(model.player.durationTicks)
                let span = min(max(duration * 0.1, 60 * 10_000_000), 600 * 10_000_000)
                model.scrubTicks = min(max(remoteScrubStartTicks + travel * span, 0), duration)
                model.updateScrubThumbnail()
            },
            selected: {
                if model.isScrubbing { commitTVScrub() }
            }
        )
    }

    // Viewed from across a room, the preview needs to be much larger on a TV.
    static let trickplaySize = CGSize(width: 400, height: 225)

    /// `player.status` alone stays `.paused` for the whole duration of a Cast session (see
    /// startCasting) — on platforms that support Cast, the icon needs to reflect the
    /// receiver's actual state instead, or it reads as "stuck paused" while casting.
    var playPauseIconIsPlaying: Bool {
        model.player.status == .playing
    }

    // MARK: - Cast & Characters

    /// Hides the controls the Apple TV way, by fading: isControlsVisible drives their hit
    /// testing, and left false it kept them unfocusable after the panel closed, so nothing on
    /// screen could take focus. Faded, the remote catcher takes it once the panel closes.
    func openCastPanel() {
        model.hideControlsTask?.cancel()
        withAnimation(DT.Animation.fast) {
            showCastPanel = true
            model.tvControlsHidden = true
        }
    }

    func openCastPanelPerson(_ person: MediaPerson) {
        Task { await model.player.pause() }
        castPanelPerson = person
    }

    // MARK: - SharePlay

    /// In a FaceTime call SharePlay starts straight away; otherwise the share sheet offers it.
    /// Apple TV has no share sheet, so there it only shows during a call.
    var sharePlayEntry: TVMenuEntry? {
        if sharePlay.isActive {
            let title = sharePlay.participantCount > 1
                ? String(localized: "Leave SharePlay (\(sharePlay.participantCount))") : String(localized: "Leave SharePlay")
            return TVMenuEntry(title: title, systemImage: "shareplay.slash", isDestructive: true) { sharePlay.leave() }
        } else if groupState.isEligibleForGroupSession {
            return TVMenuEntry(title: String(localized: "SharePlay"), systemImage: "shareplay") { sharePlay.start(item) }
        }
        return nil
    }
}

/// The scrubber's bar, thumb and preview: the parts that move with the position, in a view of
/// their own so the player screen isn't rebuilt on every tick.
private struct TVScrubberTrack: View {
    let model: PlayerModel
    let width: CGFloat
    private let trackHeight: CGFloat = 8

    var body: some View {
        let duration = max(model.player.durationTicks, 1)
        let fraction = Double(model.isScrubbing ? Int64(model.scrubTicks) : (model.pendingSeekTargetTicks ?? model.player.positionTicks)) / Double(duration)
        let thumbX = width * min(max(fraction, 0), 1)
        let previewSize = PlayerView.trickplaySize

        ZStack(alignment: .leading) {
            Capsule().fill(.white.opacity(0.25)).frame(height: trackHeight)
            Capsule().fill(DT.Color.accent)
                .frame(width: thumbX, height: trackHeight)

            // Some sources report duplicate chapter start times — id'd by array offset
            // rather than startPositionTicks so SwiftUI never sees a colliding identity.
            ForEach(Array(model.chapters.dropFirst().enumerated()), id: \.offset) { _, chapter in
                let x = width * min(max(Double(chapter.startPositionTicks) / Double(duration), 0), 1)
                Rectangle()
                    .fill(.black.opacity(0.5))
                    .frame(width: 2, height: trackHeight)
                    .offset(x: x - 1)
            }

            Circle().fill(.white)
                .frame(width: model.isScrubbing ? 16 : 10, height: model.isScrubbing ? 16 : 10)
                .offset(x: thumbX - (model.isScrubbing ? 8 : 5))
        }
        // An overlay, so the preview floats above the track. Inside the stack its height
        // made the stack taller and pushed the centred track down the screen.
        .overlay(alignment: .leading) {
            if model.isScrubbing, model.trickplayLoader != nil {
                TrickplayPreview(image: model.scrubThumbnail, size: previewSize)
                    .offset(x: min(max(thumbX - previewSize.width / 2, 0), width - previewSize.width),
                            y: -(previewSize.height / 2 + 21))
            }
        }
        .accessibilityValue("\(model.timeLabel(ticks: model.elapsedTicks)) of \(model.timeLabel(ticks: model.player.durationTicks))")
    }
}
