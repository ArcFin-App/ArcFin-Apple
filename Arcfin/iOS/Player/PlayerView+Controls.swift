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
                    .gesture(tapGesture(width: proxy.size.width))
                    .simultaneousGesture(dragGesture(width: proxy.size.width))
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

            // Portrait has no room beside the title; Cast & Characters is in the More menu there.
            if !model.castMembers.isEmpty, isLandscape { castPanelButton }

            quickActionIcons

            moreMenu
        }
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.top, 8)
        .background(routeButtonHost)
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

    /// Rotate/Fill/Chapters used to live in the overflow menu — moved out here since
    /// they're used far more often than the menu's other contents. Portrait only has room
    /// for 3; landscape has room for 5, so Subtitles/Speed join as quick shortcuts there
    /// too (they stay reachable from the menu either way).
    private var quickActionItems: [QuickAction] {
        var items: [QuickAction] = [
            QuickAction(id: "rotate", icon: "rotate.right") { toggleOrientation() },
            QuickAction(
                id: "fill",
                icon: model.isFillScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
            ) { model.isFillScreen.toggle() },
        ]
        if chapterListEnabled, !model.chapters.isEmpty {
            items.append(QuickAction(id: "chapters", icon: "list.bullet") { showChapterMenu = true })
        }
        // First on a channel, so it's there in portrait as well.
        if !model.liveChannels.isEmpty {
            items.insert(QuickAction(id: "channels", icon: "list.bullet.rectangle") {
                withAnimation(DT.Animation.fast) { model.showChannelList = true }
            }, at: 0)
        }
        items.append(QuickAction(id: "tracks", icon: "captions.bubble") { showTrackMenu = true })
        if !model.isLive {
            items.append(QuickAction(id: "speed", icon: "gauge.with.dots.needle.67percent") { showRateMenu = true })
        }
        return items
    }

    private var quickActionIcons: some View {
        HStack(spacing: 14) {
            ForEach(quickActionItems.prefix(isLandscape ? 5 : 3)) { action in
                Button(action: action.perform) {
                    Image(systemName: action.icon)
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(action.label)
            }
        }
    }

    /// AVRoutePickerView/GCKUICastButton mounted off-screen so their real tap targets can
    /// be fired from the overflow menu instead of showing as their own top-bar icons — see
    /// RouteButtonBridge's doc comment.
    private var routeButtonHost: some View {
        ZStack {
            AirPlayButton(bridge: routeBridge)
            if castEnabled, CastManager.shared.isCastAvailable {
                CastButton(bridge: routeBridge)
            }
        }
        .frame(width: 1, height: 1)
        .opacity(0.02)
        .allowsHitTesting(false)
    }

    private var moreMenu: some View {
        PlayerMoreMenu(
            model: model, item: item, routeBridge: routeBridge, groupState: groupState,
            canPictureInPicture: canPictureInPicture,
            canOpenInNewWindow: supportsMultipleWindows && !isPlayerWindow,
            canCast: castEnabled && CastManager.shared.isCastAvailable,
            // SyncPlay keeps everyone at the same position; a channel has none to share.
            canSyncPlay: syncPlayEnabled && ProfileRules.shared.canUseSyncPlay && !model.isLive,
            isAudioOnly: audioOnly,
            togglePiP: togglePiP,
            openInNewWindow: openInNewWindow,
            openCastPanel: openCastPanel,
            toggleAudioOnly: { withAnimation { audioOnly.toggle() } },
            showSyncPlayMenu: $showSyncPlayMenu,
            showTrackMenu: $showTrackMenu,
            showRateMenu: $showRateMenu,
            showQualityMenu: $showQualityMenu,
            showInfoSheet: $showInfoSheet
        )
        .equatable()
    }

    /// Every button already has a 44 pt target; the gaps keep thumbs off the neighbouring one.
    /// A phone held upright with Previous and Next too is the one layout short on room.
    private var transportSpacing: CGFloat {
        let crowded = model.previousItem != nil || model.nextEpisode != nil
        let roomy = isLandscape || UIDevice.current.userInterfaceIdiom == .pad
        return roomy ? 40 : (crowded ? 4 : 24)
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
                    LiveBadge()
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
                    }
                    if !model.isLive {
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
                    if !model.isLive {
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


    // MARK: - Casting

    /// Replaces the live video surface entirely while a Cast session is active (see
    /// PlayerView.body) — a frozen last frame behind a small banner read as "stuck paused"
    /// rather than "playing somewhere else". Position and seek math read CastManager's live
    /// position directly, never player.positionTicks / seek(by:): the local player is only
    /// paused during a cast, so its position is frozen and would make skips relative to a
    /// stale base.
    var castingPlaceholder: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            ScrollView {
                VStack(spacing: 0) {
                    HStack {
                        Button { closePlayer() } label: {
                            Image(systemName: "chevron.down")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close player")
                        Spacer()
                    }

                    if landscape {
                        HStack(spacing: 32) {
                            castInfo.frame(maxWidth: .infinity)
                            castControls.frame(maxWidth: .infinity)
                        }
                        .frame(maxHeight: .infinity)
                    } else {
                        Spacer(minLength: 16)
                        castInfo
                        Spacer(minLength: 24)
                        castControls
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .frame(minHeight: geo.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background {
            ZStack {
                Color.black
                if let url = mediaRepo.imageURL(for: item, type: .backdrop, fillWidth: 800) {
                    CachedAsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFill()
                        default: Color.clear
                        }
                    }
                    .overlay(.black.opacity(0.75))
                    .blur(radius: 40)
                }
            }
            .ignoresSafeArea()
        }
        .transition(.opacity)
    }

    private func castTrackLabel(_ title: LocalizedStringKey, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(.footnote, design: .default, weight: .semibold))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(Color.white.opacity(0.15), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.2), lineWidth: 1))
    }

    private var castInfo: some View {
        VStack(spacing: 14) {
            Image(systemName: "tv")
                .font(.largeTitle.weight(.medium))
                .foregroundStyle(DT.Color.accent)
                .accessibilityHidden(true)
            VStack(spacing: 6) {
                Text("Casting to \(CastManager.shared.deviceName ?? "TV")")
                    .font(.system(.body, design: .default, weight: .semibold))
                    .foregroundStyle(.white)
                Text(item.name)
                    .font(.system(.footnote))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(2)
            }
            .multilineTextAlignment(.center)
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    private var castControls: some View {
        let cast = CastManager.shared
        let durationSeconds = Double(model.player.durationTicks) / 10_000_000
        let liveSeconds = cast.lastKnownPositionSeconds ?? 0
        let shownSeconds = isCastScrubbing ? castScrubTicks / 10_000_000 : liveSeconds
        let fraction = durationSeconds > 0 ? min(max(shownSeconds / durationSeconds, 0), 1) : 0

        return VStack(spacing: 16) {
            if model.isLive {
                VStack(spacing: 8) {
                    LiveBadge()
                    LiveProgramBar(program: model.liveProgram)
                }
            } else {
                VStack(spacing: 4) {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.25)).frame(height: 4)
                            Capsule().fill(DT.Color.accent)
                                .frame(width: proxy.size.width * fraction, height: 4)
                            Circle().fill(.white)
                                .frame(width: isCastScrubbing ? 18 : 12, height: isCastScrubbing ? 18 : 12)
                                .offset(x: proxy.size.width * fraction - (isCastScrubbing ? 9 : 6))
                        }
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let f = min(max(value.location.x / max(proxy.size.width, 1), 0), 1)
                                    isCastScrubbing = true
                                    castScrubTicks = Double(model.player.durationTicks) * f
                                }
                                .onEnded { _ in
                                    cast.seek(toSeconds: castScrubTicks / 10_000_000)
                                    isCastScrubbing = false
                                }
                        )
                    }
                    .frame(height: 28)
                    .accessibilityElement()
                    .accessibilityLabel("Playback position")
                    .accessibilityValue("\(model.timeLabel(ticks: Int64(shownSeconds * 10_000_000))) of \(model.timeLabel(ticks: model.player.durationTicks))")
                    .accessibilityAdjustableAction { direction in
                        let step = Double(direction == .increment ? skipForwardSeconds : -skipBackwardSeconds)
                        cast.seek(toSeconds: min(max(liveSeconds + step, 0), durationSeconds))
                    }

                    HStack {
                        Text(model.timeLabel(ticks: Int64(shownSeconds * 10_000_000)))
                        Spacer()
                        Text("-" + model.timeLabel(ticks: Int64(max(durationSeconds - shownSeconds, 0) * 10_000_000)))
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.7))
                    .accessibilityHidden(true)
                }
            }

            HStack(spacing: 24) {
                if !model.isLive {
                    Button {
                        cast.seek(toSeconds: max(liveSeconds - Double(skipBackwardSeconds), 0))
                    } label: {
                        Image(systemName: skipIconName(seconds: skipBackwardSeconds, forward: false))
                            .font(.title)
                            .foregroundStyle(.white)
                            .frame(minWidth: 52, minHeight: 52)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Skip back \(skipBackwardSeconds) seconds")
                }

                Button { cast.togglePlayPause() } label: {
                    Image(systemName: cast.isPaused ? "play.fill" : "pause.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.white)
                        .frame(minWidth: 64, minHeight: 64)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(cast.isPaused ? "Play" : "Pause")

                if !model.isLive {
                    Button {
                        cast.seek(toSeconds: min(liveSeconds + Double(skipForwardSeconds), durationSeconds))
                    } label: {
                        Image(systemName: skipIconName(seconds: skipForwardSeconds, forward: true))
                            .font(.title)
                            .foregroundStyle(.white)
                            .frame(minWidth: 52, minHeight: 52)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Skip forward \(skipForwardSeconds) seconds")
                }
            }
            .buttonStyle(.plain)
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)

            HStack(spacing: 10) {
                Image(systemName: "speaker.fill")
                    .font(.system(.footnote))
                    .foregroundStyle(.white.opacity(0.7))
                    .accessibilityHidden(true)
                Slider(
                    value: Binding(get: { Double(cast.volume) }, set: { cast.setVolume(Float($0)) }),
                    in: 0...1
                )
                .tint(DT.Color.accent)
                .accessibilityLabel("TV volume")
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(.footnote))
                    .foregroundStyle(.white.opacity(0.7))
                    .accessibilityHidden(true)
            }
            .dynamicTypeSize(...DynamicTypeSize.accessibility1)

            HStack(spacing: 12) {
                if let audio = model.playbackInfo?.audioStreams, audio.count > 1 {
                    Menu {
                        Picker("Audio", selection: Binding(
                            get: { model.selectedAudioIndex ?? model.playbackInfo?.defaultAudioStreamIndex ?? audio[0].index },
                            set: { model.selectCastAudio(index: $0) }
                        )) {
                            ForEach(audio, id: \.index) { Text($0.displayTitle ?? $0.language ?? "Track \($0.index)").tag($0.index) }
                        }
                    } label: {
                        castTrackLabel("Audio", systemImage: "speaker.wave.2")
                    }
                }
                if let subs = model.playbackInfo?.subtitleStreams, !subs.isEmpty {
                    Menu {
                        Picker("Subtitles", selection: Binding(
                            get: { model.selectedSubtitleIndex ?? -1 },
                            set: { model.selectCastSubtitle(index: $0 < 0 ? nil : $0) }
                        )) {
                            Text("Off").tag(-1)
                            ForEach(subs, id: \.index) { Text($0.displayTitle ?? $0.language ?? "Track \($0.index)").tag($0.index) }
                        }
                    } label: {
                        castTrackLabel("Subtitles", systemImage: "captions.bubble")
                    }
                }
            }

            Button {
                cast.endSession()
            } label: {
                Text("Stop Casting")
                    .font(.system(.footnote, design: .default, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 18).padding(.vertical, 9)
                    .background(Color.white.opacity(0.15), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.2), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: 480)
    }

    @ViewBuilder
    var dragAxisIndicator: some View {
        if dragAxis == .seek {
            swipeSeekIndicator
        } else if let dragAxis {
            let isBrightness = dragAxis == .brightness
            HStack {
                if !isBrightness { Spacer() }
                VStack(spacing: 10) {
                    Image(systemName: isBrightness
                        ? (dragValue < 0.5 ? "sun.min.fill" : "sun.max.fill")
                        : (dragValue < 0.01 ? "speaker.slash.fill" : dragValue < 0.5 ? "speaker.wave.1.fill" : "speaker.wave.3.fill"))
                        .font(.system(.title3))
                        .foregroundStyle(.white)
                    ZStack(alignment: .bottom) {
                        Capsule().fill(.white.opacity(0.2)).frame(width: 6, height: 90)
                        Capsule().fill(.white).frame(width: 6, height: 90 * dragValue)
                    }
                    Text(Double(dragValue), format: .percent.precision(.fractionLength(0)).rounded(rule: .down))
                        .font(.system(.caption2, design: .monospaced, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .padding(14)
                .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: DT.Radius.lg))
                if isBrightness { Spacer() }
            }
            .padding(.horizontal, 32)
            .transition(.opacity)
            .allowsHitTesting(false)
        }
    }

    /// How far a sideways swipe has moved and where it will land, in the middle of the screen.
    private var swipeSeekIndicator: some View {
        let deltaTicks = Int64(model.scrubTicks) - Int64(dragBaseline)
        let forward = deltaTicks >= 0
        return VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: forward ? "forward.fill" : "backward.fill")
                    .font(.system(.title3))
                Text("\(forward ? "+" : "−")\(model.timeLabel(ticks: abs(deltaTicks)))")
                    .font(.system(.title2, design: .monospaced, weight: .semibold))
                    .contentTransition(.numericText())
            }
            Text("\(model.timeLabel(ticks: Int64(model.scrubTicks))) / \(model.timeLabel(ticks: model.player.durationTicks))")
                .font(.system(.caption, design: .monospaced, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 22).padding(.vertical, 14)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: DT.Radius.lg))
        .transition(.opacity)
        .allowsHitTesting(false)
    }

    // MARK: - Menus

    @ViewBuilder
    var trackSelectionSheet: some View {
        NavigationStack {
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
                subtitleSearchItemId: ProfileRules.shared.canManageSubtitles ? item.id : nil,
                onSubtitleDownloaded: {
                    showTrackMenu = false
                    model.adoptDownloadedSubtitle()
                },
                audioDescriptionIndices: model.audioDescriptionIndices
            )
            .navigationTitle("Subtitles & Audio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showTrackMenu = false }
                }
            }
        }
        // Landscape sheets in .medium can render narrow enough that the drag indicator is
        // the only way to dismiss and hard to grab — an explicit Done button always works.
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(.ultraThinMaterial)
    }

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

/// The player's More menu in a view of its own. Inside PlayerView it was rebuilt on every
/// playback tick, and each rebuild reset the open menu: in landscape, where it's taller than
/// the screen and scrolls, it jumped back and dropped taps. Equality ignores the actions and
/// bindings, so only a change to what the menu shows redraws it; what it reads from the
/// model is tracked on its own.
struct PlayerMoreMenu: View, Equatable {
    let model: PlayerModel
    let item: MediaItem
    let routeBridge: RouteButtonBridge
    @ObservedObject var groupState: GroupStateObserver
    let canPictureInPicture: Bool
    let canOpenInNewWindow: Bool
    let canCast: Bool
    let canSyncPlay: Bool
    let isAudioOnly: Bool
    let togglePiP: () -> Void
    let openInNewWindow: () -> Void
    let openCastPanel: () -> Void
    let toggleAudioOnly: () -> Void
    @Binding var showSyncPlayMenu: Bool
    @Binding var showTrackMenu: Bool
    @Binding var showRateMenu: Bool
    @Binding var showQualityMenu: Bool
    @Binding var showInfoSheet: Bool

    @Environment(SyncPlayManager.self) private var syncPlayManager
    @Environment(SharePlayManager.self) private var sharePlay

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.model === rhs.model && lhs.item.id == rhs.item.id
            && lhs.canPictureInPicture == rhs.canPictureInPicture
            && lhs.canOpenInNewWindow == rhs.canOpenInNewWindow
            && lhs.canCast == rhs.canCast && lhs.canSyncPlay == rhs.canSyncPlay
            && lhs.isAudioOnly == rhs.isAudioOnly
    }

    var body: some View {
        Menu {
            if canPictureInPicture {
                Button { togglePiP() } label: {
                    Label("Picture in Picture", systemImage: "pip.enter")
                }
            }
            if canOpenInNewWindow {
                Button { openInNewWindow() } label: {
                    Label("Open in New Window", systemImage: "macwindow.badge.plus")
                }
            }

            if canCast {
                Button { routeBridge.fireCast() } label: {
                    Label("Cast", systemImage: "tv")
                }
            }
            Button { routeBridge.fireAirPlay() } label: {
                Label("AirPlay", systemImage: "airplayvideo")
            }
            // The menu's items appear while it's open, so this keeps the controls (and the
            // menu with them) from auto-hiding under a finger still scrolling it.
            .onAppear { model.handleMenuVisibilityChange(true) }
            .onDisappear {
                // After the item's action runs, so a sheet it opened keeps the controls up.
                Task {
                    guard !(showTrackMenu || showRateMenu || showQualityMenu || showInfoSheet || showSyncPlayMenu) else { return }
                    model.handleMenuVisibilityChange(false)
                }
            }

            if canSyncPlay {
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

            Button { toggleAudioOnly() } label: {
                Label(isAudioOnly ? "Show Video" : "Audio Only", systemImage: isAudioOnly ? "video" : "waveform")
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

    /// In a FaceTime call SharePlay starts straight away; otherwise the share sheet offers it.
    /// Apple TV has no share sheet, so there it only shows during a call.
    @ViewBuilder
    private var sharePlayMenuItem: some View {
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
}
