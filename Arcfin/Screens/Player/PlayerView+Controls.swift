// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import JellyfinAPI
import MediaEngine
import CastKit

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
                    #if canImport(UIKit) && !os(tvOS)
                    .gesture(tapGesture(width: proxy.size.width))
                    #elseif os(macOS)
                    .gesture(macTapGesture(width: proxy.size.width))
                    #endif
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
                #if os(tvOS)
                TVPlayerControlLabel(systemImage: "chevron.down", size: 15, diameter: 34)
                #else
                Image(systemName: "chevron.down")
                    .font(.system(.title3, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                #endif
            }
            #if os(tvOS)
            .buttonStyle(TVCardButtonStyle())
            .focusEffectDisabled()
            #endif

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .scaledFont(size: 15, weight: .semibold)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let hdrLabel {
                        Text(hdrLabel)
                            .font(.system(.caption2, design: .default, weight: .bold))
                            .tracking(0.5)
                            .foregroundStyle(hdrIsToneMapped ? .black : .white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(
                                hdrIsToneMapped ? Color(hex: "F59E0B") : Color.clear,
                                in: Capsule()
                            )
                            .overlay(
                                Capsule().stroke(.white.opacity(hdrIsToneMapped ? 0 : 0.4), lineWidth: 1)
                            )
                    }
                }
                if let subtitle = episodeSubtitle {
                    Text(subtitle)
                        .scaledFont(size: 12)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }

            Spacer()

            // Portrait has no room beside the title; X-Ray is in the More menu there.
            #if os(macOS)
            if !castMembers.isEmpty { xRayButton }
            #elseif !os(tvOS)
            if !castMembers.isEmpty, isLandscape { xRayButton }
            #endif

            #if canImport(UIKit) && !os(tvOS)
            quickActionIcons
            #elseif os(macOS)
            macQuickActionIcons
            #endif

            // Everything moreMenu ever held on tvOS (Subtitles & Audio, Speed, Quality,
            // Chapters, Info) now lives as its own reachable button in bottomBar's
            // leftSecondaryActions/rightSecondaryActions instead — a remote shouldn't need
            // to open a menu just to find them.
            #if !os(tvOS)
            moreMenu
            #endif
        }
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.top, 8)
        #if canImport(UIKit) && !os(tvOS)
        .background(routeButtonHost)
        #endif
        #if os(tvOS)
        .focusSection()
        #endif
    }

    // MARK: - Quick-access controls

    #if canImport(UIKit) && !os(tvOS)
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
                icon: isFillScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
            ) { isFillScreen.toggle() },
        ]
        if chapterListEnabled, !chapters.isEmpty {
            items.append(QuickAction(id: "chapters", icon: "list.bullet") { showChapterMenu = true })
        }
        items.append(QuickAction(id: "tracks", icon: "captions.bubble") { showTrackMenu = true })
        items.append(QuickAction(id: "speed", icon: "gauge.with.dots.needle.67percent") { showRateMenu = true })
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
            #if canImport(GoogleCast)
            if castEnabled, CastManager.shared.isCastAvailable {
                CastButton(bridge: routeBridge)
            }
            #endif
        }
        .frame(width: 1, height: 1)
        .opacity(0.02)
        .allowsHitTesting(false)
    }
    #elseif os(macOS)
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
                icon: isFillScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right"
            ) { isFillScreen.toggle() },
            QuickAction(
                id: "fullscreen",
                icon: isMacFullScreen ? "arrow.down.right.and.arrow.up.left.circle" : "arrow.up.left.and.arrow.down.right.circle"
            ) { toggleMacWindowFullScreen(macWindow) },
        ]
        if chapterListEnabled, !chapters.isEmpty {
            items.append(QuickAction(id: "chapters", icon: "list.bullet") { showChapterMenu = true })
        }
        items.append(QuickAction(id: "tracks", icon: "captions.bubble") { showTrackMenu = true })
        items.append(QuickAction(id: "speed", icon: "gauge.with.dots.needle.67percent") { showRateMenu = true })
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
            AirPlayButton(player: (player as? AVFoundationPlayer)?.player)
                .frame(width: 22, height: 22)
        }
    }
    #endif

    private var moreMenu: some View {
        Menu {
            #if !os(tvOS)
            if isPiPSupported {
                Button { togglePiP() } label: {
                    Label("Picture in Picture", systemImage: "pip.enter")
                }
            }
            #endif

            #if canImport(GoogleCast)
            if castEnabled, CastManager.shared.isCastAvailable {
                Button { routeBridge.fireCast() } label: {
                    Label("Cast", systemImage: "tv")
                }
            }
            #endif
            #if canImport(UIKit) && !os(tvOS)
            Button { routeBridge.fireAirPlay() } label: {
                Label("AirPlay", systemImage: "airplayvideo")
            }
            #endif

            #if !os(tvOS)
            if syncPlayEnabled && ProfileRules.shared.canUseSyncPlay {
                Button { showSyncPlayMenu = true } label: {
                    Label("SyncPlay", systemImage: syncPlayManager.isInGroup ? "person.2.wave.2.fill" : "person.2.wave.2")
                }
            }
            #endif

            #if !os(tvOS)
            if !castMembers.isEmpty {
                Button { openXRay() } label: {
                    Label("X-Ray: Cast", systemImage: "person.2")
                }
            }
            #endif

            Button { withAnimation { audioOnly.toggle() } } label: {
                Label(audioOnly ? "Show Video" : "Audio Only", systemImage: audioOnly ? "video" : "waveform")
            }
            Button { showTrackMenu = true } label: {
                Label("Subtitles & Audio", systemImage: "captions.bubble")
            }
            if let info = playbackInfo, info.versions.count > 1 {
                Picker(selection: Binding(get: { info.mediaSourceId }, set: { changeVersion($0) })) {
                    ForEach(info.versions) { Text($0.name).tag($0.id) }
                } label: {
                    Label("Version", systemImage: "square.stack")
                }
                .pickerStyle(.menu)
            }
            Button { showRateMenu = true } label: {
                Label("Playback Speed", systemImage: "gauge.with.dots.needle.67percent")
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
        #if os(tvOS)
        .buttonStyle(TVCardButtonStyle())
        .focusEffectDisabled()
        .tvFocusRing(cornerRadius: 16)
        #endif
    }

    @ViewBuilder
    private var subtitleTimingMenu: some View {
        if !subtitleCues.isEmpty {
            Menu {
                Button("Later by 0.5 s") { subtitleDelay += 0.5 }
                Button("Earlier by 0.5 s") { subtitleDelay -= 0.5 }
                Button("Later by 0.1 s") { subtitleDelay += 0.1 }
                Button("Earlier by 0.1 s") { subtitleDelay -= 0.1 }
                Button("Reset", role: .destructive) { subtitleDelay = 0 }
                    .disabled(subtitleDelay == 0)
            } label: {
                Label(
                    subtitleDelay == 0 ? "Subtitle Timing" : "Subtitle Timing (\(String(format: "%+.1f", subtitleDelay)) s)",
                    systemImage: "clock.arrow.2.circlepath")
            }
        }
    }

    private var sleepTimerMenu: some View {
        Menu {
            Button("Off") { setSleepTimer(minutes: nil) }
            ForEach([15, 30, 45, 60], id: \.self) { minutes in
                Button("\(minutes) minutes") { setSleepTimer(minutes: minutes) }
            }
            if item.type == .episode {
                Button("End of episode") { setSleepTimer(minutes: nil, atEndOfItem: true) }
            }
        } label: {
            Label(
                sleepTimerEndsAt != nil || sleepAtEndOfItem ? "Sleep Timer (On)" : "Sleep Timer",
                systemImage: "moon.zzz")
        }
    }

    var episodeSubtitle: String? {
        guard item.type == .episode, let series = item.seriesName else { return nil }
        let s = item.parentIndexNumber.map { "S\($0)" } ?? ""
        let e = item.indexNumber.map { "E\($0)" } ?? ""
        return [series, [s, e].joined()].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    // MARK: - HDR / Dolby Vision badge

    /// The transcode profile only ever outputs h264/SDR (see JellyfinPlaybackClient's
    /// TranscodingProfiles) — an HDR/DV source that gets transcoded is always tone-mapped
    /// down to SDR, which is worth surfacing since it's a visible quality loss the user
    /// didn't ask for.
    private var hdrIsToneMapped: Bool {
        (playbackInfo?.isHDR ?? false) && playbackInfo?.playMethod == .transcode
    }

    private var hdrLabel: String? {
        guard let info = playbackInfo, info.isHDR else { return nil }
        if hdrIsToneMapped { return "HDR → SDR" }
        return info.isDolbyVision ? "DOLBY VISION" : "HDR"
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            scrubber

            // Time labels moved off the buttons row when that row's left/right slots became
            // leftSecondaryActions/rightSecondaryActions — they belong at the scrubber's own
            // two ends regardless of what's in the row below it.
            #if os(tvOS)
            HStack {
                Text(timeLabel(ticks: elapsedTicks))
                    .scaledFont(size: 12, weight: .medium, design: .monospaced)
                    .foregroundStyle(.white.opacity(0.8))
                    .contentTransition(.numericText())
                    .animation(isScrubbing ? nil : .default, value: elapsedTicks)
                Spacer()
                Text(remainingLabel)
                    .scaledFont(size: 12, weight: .medium, design: .monospaced)
                    .foregroundStyle(.white.opacity(0.8))
                    .contentTransition(.numericText())
                    .animation(.default, value: remainingTicks)
            }
            #endif

            HStack {
                #if os(tvOS)
                leftSecondaryActions
                    .frame(maxWidth: .infinity, alignment: .leading)
                #else
                Text(timeLabel(ticks: elapsedTicks))
                    .font(.system(.caption, design: .monospaced, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .contentTransition(.numericText())
                    .animation(isScrubbing ? nil : .default, value: elapsedTicks)

                Spacer()
                #endif

                HStack(spacing: 20) {
                    Button { seek(by: -skipBackwardSeconds) } label: {
                        #if os(tvOS)
                        TVPlayerControlLabel(systemImage: skipIconName(seconds: skipBackwardSeconds, forward: false), size: 16, diameter: 38)
                        #else
                        Image(systemName: skipIconName(seconds: skipBackwardSeconds, forward: false))
                            .font(.system(.title3)).foregroundStyle(.white)
                        #endif
                    }
                    Button { togglePlayPause() } label: {
                        #if os(tvOS)
                        TVPlayerControlLabel(systemImage: playPauseIconIsPlaying ? "pause.fill" : "play.fill", size: 22, diameter: 48)
                        #else
                        Image(systemName: playPauseIconIsPlaying ? "pause.fill" : "play.fill")
                            .font(.system(.largeTitle))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                        #endif
                    }
                    #if os(tvOS)
                    .prefersDefaultFocus(!tvControlsHidden, in: tvFocusNamespace)
                    #endif
                    Button { seek(by: skipForwardSeconds) } label: {
                        #if os(tvOS)
                        TVPlayerControlLabel(systemImage: skipIconName(seconds: skipForwardSeconds, forward: true), size: 16, diameter: 38)
                        #else
                        Image(systemName: skipIconName(seconds: skipForwardSeconds, forward: true))
                            .font(.system(.title3)).foregroundStyle(.white)
                        #endif
                    }
                }
                #if os(tvOS)
                .buttonStyle(TVCardButtonStyle())
                .focusEffectDisabled()
                .focusSection()
                #endif

                #if os(tvOS)
                rightSecondaryActions
                    .frame(maxWidth: .infinity, alignment: .trailing)
                #else
                Spacer()

                Text(remainingLabel)
                    .font(.system(.caption, design: .monospaced, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .contentTransition(.numericText())
                    .animation(.default, value: remainingTicks)
                #endif
            }
        }
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.bottom, 24)
    }

    #if os(tvOS)
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
            Button { showRateMenu = true } label: {
                TVPlayerControlLabel(systemImage: "gauge.with.dots.needle.67percent", size: 14, diameter: 32)
            }
        }
        .buttonStyle(TVCardButtonStyle())
        .focusEffectDisabled()
        .focusSection()
    }

    private var rightSecondaryActions: some View {
        HStack(spacing: 12) {
            Button { showQualityMenu = true } label: {
                TVPlayerControlLabel(systemImage: "slider.horizontal.3", size: 14, diameter: 32)
            }
            if chapterListEnabled, !chapters.isEmpty {
                Button { showChapterMenu = true } label: {
                    TVPlayerControlLabel(systemImage: "list.bullet", size: 14, diameter: 32)
                }
            }
            Button { showInfoSheet = true } label: {
                TVPlayerControlLabel(systemImage: "info.circle", size: 14, diameter: 32)
            }
            Menu {
                tvMoreMenuContent
            } label: {
                TVPlayerControlLabel(systemImage: "ellipsis", size: 14, diameter: 32)
            }
            .accessibilityLabel("More options")
        }
        .buttonStyle(TVCardButtonStyle())
        .focusEffectDisabled()
        .focusSection()
    }

    /// Something besides the transport controls that the remote should land on.
    private var tvOverlayHasFocusTarget: Bool {
        showStillWatchingPrompt || (showUpNext && nextEpisode != nil)
            || (showMoreLikeThis && !moreLikeThis.isEmpty) || showXRay
    }

    /// With the controls hidden, an invisible catcher holds focus, so a click never presses a
    /// button nobody can see.
    var tvCatcherActive: Bool {
        tvControlsHidden && !tvOverlayHasFocusTarget && skipButtonLabel == nil
    }

    /// Changes whenever a different control should hold focus.
    var tvFocusContext: String {
        "\(tvControlsHidden)-\(tvCatcherActive)-\(skipButtonLabel ?? "")-\(tvOverlayHasFocusTarget)"
    }

    /// The remote while the controls are hidden, as in the system player: a click or a swipe
    /// up shows them, down opens subtitles and audio, left and right skip back and forward.
    var tvRemoteCatcher: some View {
        Button { toggleControlsVisibilityOnAction() } label: {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(TVCardButtonStyle())
        .focusEffectDisabled()
        .prefersDefaultFocus(true, in: tvFocusNamespace)
        .onMoveCommand { direction in
            switch direction {
            case .left: tvQuickSeek(forward: false)
            case .right: tvQuickSeek(forward: true)
            // Down opens subtitles and audio, as the system player's info panel does.
            case .down: showTrackMenu = true
            default: toggleControlsVisibilityOnAction()
            }
        }
        .accessibilityLabel("Show playback controls")
        .ignoresSafeArea()
    }

    private func tvQuickSeek(forward: Bool) {
        let seconds = forward ? skipForwardSeconds : skipBackwardSeconds
        let base = pendingSeekTargetTicks ?? player.positionTicks
        performSeek(to: min(max(0, base + Int64(forward ? seconds : -seconds) * 10_000_000), player.durationTicks))
        let feedback = SeekFeedback(forward: forward, onRight: forward, seconds: seconds)
        seekFeedback = feedback
        Task {
            try? await Task.sleep(for: .seconds(0.6))
            if seekFeedback == feedback { seekFeedback = nil }
        }
    }

    /// Menu steps back one layer at a time: out of a scrub, then hides the controls, then
    /// leaves the player.
    func handleTVExit() {
        if isScrubbing {
            isScrubbing = false
            scrubThumbnail = nil
            scheduleAutoHide()
        } else if !tvControlsHidden {
            hideControlsTask?.cancel()
            withAnimation(DT.Animation.fast) { tvControlsHidden = true }
        } else {
            closePlayer()
        }
    }

    /// What the touch and Mac players keep in their More menu and have no button of their own here.
    @ViewBuilder
    private var tvMoreMenuContent: some View {
        if !castMembers.isEmpty {
            Button { openXRay() } label: {
                Label("X-Ray: Cast", systemImage: "person.2")
            }
        }
        if syncPlayEnabled && ProfileRules.shared.canUseSyncPlay {
            Button { showSyncPlayMenu = true } label: {
                Label("SyncPlay", systemImage: syncPlayManager.isInGroup ? "person.2.wave.2.fill" : "person.2.wave.2")
            }
        }
        Button { withAnimation { audioOnly.toggle() } } label: {
            Label(audioOnly ? "Show Video" : "Audio Only", systemImage: audioOnly ? "video" : "waveform")
        }
        if let info = playbackInfo, info.versions.count > 1 {
            Picker(selection: Binding(get: { info.mediaSourceId }, set: { changeVersion($0) })) {
                ForEach(info.versions) { Text($0.name).tag($0.id) }
            } label: {
                Label("Version", systemImage: "square.stack")
            }
            .pickerStyle(.menu)
        }
        subtitleTimingMenu
        sleepTimerMenu
    }
    #endif

    private var scrubber: some View {
        // tvOS has no drag-to-scrub (see the DragGesture platform split below) so the bar
        // itself is the only feedback a remote-driven seek gets — thicker here than the
        // touch/mouse platforms, where the gesture itself is the primary feedback.
        #if os(tvOS)
        let trackHeight: CGFloat = 8
        #else
        let trackHeight: CGFloat = 4
        #endif
        return GeometryReader { proxy in
            let duration = max(player.durationTicks, 1)
            let fraction = Double(isScrubbing ? Int64(scrubTicks) : (pendingSeekTargetTicks ?? player.positionTicks)) / Double(duration)
            let thumbX = proxy.size.width * min(max(fraction, 0), 1)

            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.25)).frame(height: trackHeight)
                Capsule().fill(DT.Color.accent)
                    .frame(width: thumbX, height: trackHeight)

                // Some sources report duplicate chapter start times — id'd by array offset
                // rather than startPositionTicks so SwiftUI never sees a colliding identity.
                ForEach(Array(chapters.dropFirst().enumerated()), id: \.offset) { _, chapter in
                    let x = proxy.size.width * min(max(Double(chapter.startPositionTicks) / Double(duration), 0), 1)
                    Rectangle()
                        .fill(.black.opacity(0.5))
                        .frame(width: 2, height: trackHeight)
                        .offset(x: x - 1)
                }

                Circle().fill(.white)
                    .frame(width: isScrubbing ? 16 : 10, height: isScrubbing ? 16 : 10)
                    .offset(x: thumbX - (isScrubbing ? 8 : 5))

                if isScrubbing, trickplayLoader != nil {
                    trickplayPreview
                        .offset(x: min(max(thumbX - 70, 0), proxy.size.width - 140), y: -100)
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            // DragGesture tracks a mouse drag on macOS the same way it tracks a touch drag on
            // iOS — no platform split needed for the gesture itself, only for what's iOS-only
            // inside it (HapticManager already safely no-ops off iOS on its own).
            #if !os(tvOS)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isScrubbing { HapticManager.impact(.light) }
                        isScrubbing = true
                        hideControlsTask?.cancel()
                        let fraction = min(max(value.location.x / proxy.size.width, 0), 1)
                        scrubTicks = Double(player.durationTicks) * fraction
                        updateScrubThumbnail()
                    }
                    .onEnded { _ in
                        performSeek(to: Int64(scrubTicks))
                        isScrubbing = false
                        scrubThumbnail = nil
                        scheduleAutoHide()
                    }
            )
            #else
            // No drag surface on tvOS — focus the bar and swipe the remote's touch surface
            // left/right to nudge the pending position (with the same trickplay preview),
            // then click to commit. Matches how Apple's own tvOS video player scrubber works.
            .focusable(true)
            .onMoveCommand { direction in
                guard direction == .left || direction == .right else { return }
                if !isScrubbing {
                    isScrubbing = true
                    scrubTicks = Double(pendingSeekTargetTicks ?? player.positionTicks)
                    hideControlsTask?.cancel()
                }
                let stepTicks: Double = 10 * 10_000_000
                scrubTicks = direction == .right
                    ? min(scrubTicks + stepTicks, Double(player.durationTicks))
                    : max(scrubTicks - stepTicks, 0)
                updateScrubThumbnail()
            }
            .onTapGesture {
                guard isScrubbing else { return }
                performSeek(to: Int64(scrubTicks))
                isScrubbing = false
                scrubThumbnail = nil
                scheduleAutoHide()
            }
            #endif
        }
        .frame(height: 20)
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(timeLabel(ticks: elapsedTicks)) of \(timeLabel(ticks: player.durationTicks))")
        .accessibilityAdjustableAction { direction in
            seek(by: direction == .increment ? skipForwardSeconds : -skipBackwardSeconds)
        }
    }

    private var trickplayPreview: some View {
        Group {
            if let scrubThumbnail {
                Image(platformImage: scrubThumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
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

    private func updateScrubThumbnail() {
        // 2s buckets — fetching a fresh crop on every pixel of drag would hammer the loader.
        let bucket = Int(scrubTicks / (2 * 10_000_000))
        guard bucket != lastThumbnailBucket, let loader = trickplayLoader else { return }
        lastThumbnailBucket = bucket
        let ticks = Int64(scrubTicks)
        Task {
            let image = await loader.thumbnail(forPositionTicks: ticks)
            guard isScrubbing else { return }
            scrubThumbnail = image
        }
    }

    /// `player.status` alone stays `.paused` for the whole duration of a Cast session (see
    /// startCasting) — on platforms that support Cast, the icon needs to reflect the
    /// receiver's actual state instead, or it reads as "stuck paused" while casting.
    var playPauseIconIsPlaying: Bool {
        #if !os(tvOS)
        return isEffectivelyPlaying
        #else
        return player.status == .playing
        #endif
    }

    private var elapsedTicks: Int64 {
        isScrubbing ? Int64(scrubTicks) : (pendingSeekTargetTicks ?? player.positionTicks)
    }

    private var remainingTicks: Int64 {
        max(player.durationTicks - (pendingSeekTargetTicks ?? player.positionTicks), 0)
    }

    private var remainingLabel: String {
        "-" + timeLabel(ticks: remainingTicks)
    }

    private func timeLabel(ticks: Int64) -> String {
        let totalSeconds = Int(Double(ticks) / 10_000_000)
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    // MARK: - Chapters

    /// Reuses the scrubber's own TrickplayLoader so the chapter list doesn't need a separate
    /// image source — Jellyfin's dedicated per-chapter image endpoint isn't wired into
    /// MediaChapter at all today, and every title with trickplay already has frames at every
    /// chapter's start time anyway.
    private struct ChapterThumbnailView: View {
        let loader: TrickplayLoader?
        let positionTicks: Int64
        @State private var image: PlatformImage?

        var body: some View {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(DT.Color.backgroundTertiary)
                if let image {
                    Image(platformImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
            }
            .frame(width: 80, height: 45)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .task(id: positionTicks) {
                image = await loader?.thumbnail(forPositionTicks: positionTicks)
            }
        }
    }

    var chapterListSheet: some View {
        NavigationStack {
            List {
                ForEach(Array(chapters.enumerated()), id: \.offset) { index, chapter in
                    let isCurrent = currentChapterIndex == index
                    Button {
                        showChapterMenu = false
                        jumpToChapter(chapter)
                    } label: {
                        HStack(spacing: 12) {
                            ChapterThumbnailView(loader: trickplayLoader, positionTicks: chapter.startPositionTicks)
                            Text(chapter.name ?? "Chapter \(index + 1)")
                                .font(.system(.footnote, design: .default, weight: isCurrent ? .semibold : .regular))
                                .foregroundStyle(isCurrent ? DT.Color.accent : DT.Color.textPrimary)
                            Spacer()
                            Text(timeLabel(ticks: chapter.startPositionTicks))
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(DT.Color.textSecondary)
                        }
                    }
                    .arcfinPlainButton()
                }
            }
            .navigationTitle("Chapters")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showChapterMenu = false }
                }
            }
        }
        // Landscape sheets in .medium can render narrow enough that the drag indicator is
        // the only way to dismiss and hard to grab — an explicit Done button always works.
        // presentationDetents is an iPhone/iPad card-sheet concept sized for a portrait
        // screen — tvOS has no drag-to-dismiss and forcing .medium/.large onto its
        // differently shaped modal container clipped the content at both edges. Letting
        // tvOS use its own default sheet presentation instead.
        #if !os(tvOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.ultraThinMaterial)
        #endif
    }

    private var currentChapterIndex: Int? {
        var result: Int?
        for (index, chapter) in chapters.enumerated() where chapter.startPositionTicks <= player.positionTicks {
            result = index
        }
        return result
    }

    private func jumpToChapter(_ chapter: MediaChapter) {
        Task { await player.seek(to: chapter.startPositionTicks) }
        HapticManager.impact(.light)
    }

    // MARK: - X-Ray

    func openXRay() {
        withAnimation(DT.Animation.fast) {
            showXRay = true
            isControlsVisible = false
        }
    }

    private var xRayButton: some View {
        Button { openXRay() } label: {
            Label("X-Ray", systemImage: "person.2.fill")
                .labelStyle(.titleAndIcon)
                .font(.system(.caption, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(Color.white.opacity(0.15), in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 1))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("X-Ray: cast")
    }

    /// Who's in this, beside the picture: a panel on the trailing edge in landscape, along the
    /// bottom in portrait. Playback carries on; picking someone pauses and opens their page.
    @ViewBuilder
    var xRayOverlay: some View {
        if showXRay {
            GeometryReader { proxy in
                let landscape = proxy.size.width > proxy.size.height
                ZStack(alignment: landscape ? .trailing : .bottom) {
                    Color.black.opacity(0.25)
                        .ignoresSafeArea()
                        #if !os(tvOS)
                        .onTapGesture { withAnimation(DT.Animation.fast) { showXRay = false } }
                        #endif

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("X-Ray")
                                    .font(.system(.headline, weight: .bold))
                                    .foregroundStyle(.white)
                                Text("In \(item.type == .episode ? (item.seriesName ?? item.name) : item.name)")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.6))
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button {
                                withAnimation(DT.Animation.fast) { showXRay = false }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(.footnote, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 30, height: 30)
                                    .background(Color.white.opacity(0.15), in: Circle())
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .playerOverlayButton(cornerRadius: 22)
                            .accessibilityLabel("Close X-Ray")
                        }
                        ScrollView(landscape ? .vertical : .horizontal, showsIndicators: false) {
                            let layout = landscape
                                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                                : AnyLayout(HStackLayout(alignment: .top, spacing: 14))
                            layout {
                                ForEach(castMembers) { person in
                                    Button { openXRayPerson(person) } label: {
                                        xRayRow(person, compact: !landscape)
                                    }
                                    .playerOverlayButton(cornerRadius: DT.Radius.md)
                                }
                            }
                        }
                    }
                    .padding(16)
                    .frame(width: landscape ? min(340, proxy.size.width * 0.42) : nil)
                    .frame(maxWidth: landscape ? nil : .infinity)
                    .frame(maxHeight: landscape ? .infinity : 230)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DT.Radius.lg))
                    .padding(landscape ? 12 : 10)
                    .transition(.move(edge: landscape ? .trailing : .bottom).combined(with: .opacity))
                    #if os(tvOS)
                    .focusSection()
                    #endif
                }
            }
            #if os(tvOS)
            .onExitCommand { withAnimation(DT.Animation.fast) { showXRay = false } }
            #endif
        }
    }

    private func xRayRow(_ person: MediaPerson, compact: Bool) -> some View {
        let photo = CachedAsyncImage(url: person.primaryImageTag.flatMap {
            mediaRepo.personImageURL(personId: person.id, tag: $0, fillWidth: 160)
        }) { phase in
            switch phase {
            case .success(let image): image.resizable().scaledToFill()
            default:
                ZStack {
                    Color.white.opacity(0.1)
                    Image(systemName: "person.fill").foregroundStyle(.white.opacity(0.4))
                }
            }
        }
        return Group {
            if compact {
                VStack(spacing: 6) {
                    photo.frame(width: 72, height: 72).clipShape(Circle())
                    Text(person.name)
                        .font(.system(.caption, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    if let role = person.role, !role.isEmpty {
                        Text(role)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                }
                .frame(width: 88)
            } else {
                HStack(spacing: 12) {
                    photo.frame(width: 48, height: 48).clipShape(Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(person.name)
                            .font(.system(.subheadline, weight: .semibold))
                            .foregroundStyle(.white)
                        if let role = person.role, !role.isEmpty {
                            Text(role)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.4))
                }
                .contentShape(Rectangle())
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens their page")
    }

    private func openXRayPerson(_ person: MediaPerson) {
        Task { await player.pause() }
        xRayPerson = person
    }

    // MARK: - Media info

    var mediaInfoSheet: some View {
        NavigationStack {
        List {
            if let info = playbackInfo {
                Section("Video") {
                    if let codec = info.videoStream?.codec {
                        LabeledContent("Codec", value: codec.uppercased())
                    }
                    if let width = info.videoStream?.width, let height = info.videoStream?.height {
                        LabeledContent("Resolution", value: "\(width)×\(height)")
                    }
                    if let range = info.videoStream?.videoRange {
                        LabeledContent("Video Range", value: range)
                    }
                }
                Section("Audio") {
                    if let stream = currentAudioStream {
                        if let codec = stream.codec {
                            LabeledContent("Codec", value: codec.uppercased())
                        }
                        LabeledContent("Track", value: mediaInfoTrackLabel(stream))
                    } else {
                        Text("No audio track selected.")
                            .foregroundStyle(DT.Color.textSecondary)
                    }
                }
                Section("Subtitle") {
                    if let stream = currentSubtitleStream {
                        LabeledContent("Track", value: mediaInfoTrackLabel(stream))
                    } else {
                        Text("Off")
                            .foregroundStyle(DT.Color.textSecondary)
                    }
                }
                Section("Stream") {
                    if let container = info.container {
                        LabeledContent("Container", value: container.uppercased())
                    }
                    LabeledContent("Play Method", value: info.playMethod.rawValue)
                    if let bitrate = info.bitrate {
                        LabeledContent("Bitrate", value: mediaInfoBitrateLabel(bitrate))
                    }
                }
            } else {
                Text("No playback info available.")
                    .foregroundStyle(DT.Color.textSecondary)
            }
        }
        #if canImport(UIKit) && !os(tvOS)
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        #endif
        .screenBackground()
        .navigationTitle("Media Info")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { showInfoSheet = false }
            }
        }
        }
        // See chapterListSheet above — presentationDetents doesn't fit tvOS's sheet shape.
        #if !os(tvOS)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(.ultraThinMaterial)
        #endif
    }

    private var currentAudioStream: JellyfinMediaStream? {
        playbackInfo?.audioStreams.first(where: { $0.index == selectedAudioIndex })
    }

    private var currentSubtitleStream: JellyfinMediaStream? {
        guard let selectedSubtitleIndex else { return nil }
        return playbackInfo?.subtitleStreams.first(where: { $0.index == selectedSubtitleIndex })
    }

    private func mediaInfoTrackLabel(_ stream: JellyfinMediaStream) -> String {
        if let title = stream.displayTitle, !title.isEmpty { return title }
        let parts = [stream.language, stream.codec?.uppercased()].compactMap { $0 }
        return parts.isEmpty ? "Track \(stream.index)" : parts.joined(separator: " · ")
    }

    private func mediaInfoBitrateLabel(_ bitrate: Int) -> String {
        let mbps = Double(bitrate) / 1_000_000
        return mbps >= 1 ? String(format: "%.1f Mb/s", mbps) : String(format: "%.0f Kb/s", Double(bitrate) / 1000)
    }

    // MARK: - SyncPlay

    var syncPlaySheet: some View {
        NavigationStack {
            Group {
                if syncPlayManager.isInGroup {
                    List {
                        Section("Group") {
                            LabeledContent("Name", value: syncPlayManager.groupName ?? "—")
                        }
                        Section {
                            Button(role: .destructive) {
                                leaveSyncPlayGroup()
                            } label: {
                                Text("Leave Group")
                            }
                        }
                    }
                } else {
                    List {
                        Section("Create a Group") {
                            TextField("Group name", text: $syncPlayGroupNameInput)
                            Button {
                                createSyncPlayGroup()
                            } label: {
                                if isSyncPlayBusy { ProgressView() } else { Text("Create") }
                            }
                            .disabled(syncPlayGroupNameInput.trimmingCharacters(in: .whitespaces).isEmpty || isSyncPlayBusy)
                        }
                        Section {
                            if syncPlayManager.availableGroups.isEmpty {
                                Text(syncPlayManager.isRefreshingGroups ? "Looking for groups…" : "No joinable groups right now.")
                                    .font(.system(.footnote))
                                    .foregroundStyle(DT.Color.textSecondary)
                            } else {
                                ForEach(syncPlayManager.availableGroups) { group in
                                    Button {
                                        joinSyncPlayGroup(group)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(group.groupName).foregroundStyle(DT.Color.textPrimary)
                                            Text("\(group.participants.count) watching" + (group.playingItemName.map { " · \($0)" } ?? ""))
                                                .font(.system(.caption2))
                                                .foregroundStyle(DT.Color.textSecondary)
                                        }
                                    }
                                }
                            }
                        } header: {
                            Text("Join a Group")
                        } footer: {
                            Text("Everyone in a group needs \(item.name) already open in their own player — SyncPlay keeps play, pause, and seek in sync from there.")
                        }
                    }
                    .task { await refreshSyncPlayGroups() }
                    .refreshable { await refreshSyncPlayGroups() }
                }
            }
            .navigationTitle("SyncPlay")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showSyncPlayMenu = false }
                }
            }
            .alert("SyncPlay", isPresented: Binding(
                get: { syncPlayManager.lastError != nil }, set: { if !$0 { syncPlayManager.lastError = nil } }
            )) {
                Button("OK") {}
            } message: {
                Text(syncPlayManager.lastError ?? "")
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func refreshSyncPlayGroups() async {
        guard let credential = authManager.state.credential else { return }
        let authHeader = authManager.authClient.authHeader(token: credential.accessToken)
        await syncPlayManager.refreshGroups(credential: credential, authHeader: authHeader)
    }

    private func createSyncPlayGroup() {
        guard let credential = authManager.state.credential else { return }
        let authHeader = authManager.authClient.authHeader(token: credential.accessToken)
        let name = syncPlayGroupNameInput.trimmingCharacters(in: .whitespaces)
        isSyncPlayBusy = true
        Task {
            await syncPlayManager.createGroup(
                credential: credential, authHeader: authHeader, groupName: name,
                itemId: item.id, startPositionTicks: player.positionTicks
            )
            isSyncPlayBusy = false
        }
    }

    private func joinSyncPlayGroup(_ group: SyncPlayGroupInfo) {
        guard let credential = authManager.state.credential else { return }
        let authHeader = authManager.authClient.authHeader(token: credential.accessToken)
        isSyncPlayBusy = true
        Task {
            await syncPlayManager.joinGroup(
                group, credential: credential, authHeader: authHeader,
                itemId: item.id, startPositionTicks: player.positionTicks
            )
            isSyncPlayBusy = false
        }
    }

    private func leaveSyncPlayGroup() {
        guard let credential = authManager.state.credential else { return }
        let authHeader = authManager.authClient.authHeader(token: credential.accessToken)
        syncPlayManager.leaveGroup(credential: credential, authHeader: authHeader)
    }

    // MARK: - Skip intro/credits

    var skipButton: some View {
        Group {
            if let label = skipButtonLabel {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button { skipToSegmentEnd() } label: {
                            HStack(spacing: 6) {
                                Text(label).font(.system(.footnote, design: .default, weight: .semibold))
                                Image(systemName: "forward.fill").font(.system(.caption))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DT.Radius.lg))
                            .overlay(RoundedRectangle(cornerRadius: DT.Radius.lg).stroke(.white.opacity(0.15), lineWidth: 1))
                        }
                        #if os(tvOS)
                        .buttonStyle(TVCardButtonStyle())
                        .focusEffectDisabled()
                        .tvFocusRing(cornerRadius: DT.Radius.lg, prominent: true)
                        // With the controls hidden, a click skips.
                        .prefersDefaultFocus(tvControlsHidden, in: tvFocusNamespace)
                        #endif
                        .padding(.trailing, DT.Spacing.pagePad)
                        .padding(.bottom, 100)
                    }
                }
            }
        }
    }

    /// The segment playback is in right now, if any, with its button label.
    private var currentSkippable: (kind: String, label: String, span: ClosedRange<Double>)? {
        let seconds = Double(player.positionTicks) / 10_000_000
        guard seconds > 0.5 else { return nil }
        // Recap ("previously on") is the cold open ahead of the intro, so it's checked first.
        if let span = segments.recap, span.contains(seconds) { return ("recap", "Skip Recap", span) }
        if let span = segments.intro, span.contains(seconds) { return ("intro", "Skip Intro", span) }
        if let span = segments.credits, span.contains(seconds) {
            // Up Next and the suggestions panel already offer a way on from the credits.
            guard !showUpNext, !showMoreLikeThis else { return nil }
            return ("credits", "Skip Credits", span)
        }
        if let span = segments.preview, span.contains(seconds) { return ("preview", "Skip Preview", span) }
        return nil
    }

    private var skipButtonLabel: String? { currentSkippable?.label }

    // MARK: - Up Next

    /// The credits of anything with a title after it (the next episode, or the next one in a
    /// playlist or collection): what's next, and Skip Credits, Like and Dislike for what's
    /// ending.
    func upNextCard(_ next: MediaItem) -> some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        if let url = mediaRepo.imageURL(for: next, type: .thumb, fillWidth: 240) {
                            CachedAsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let img): img.resizable().scaledToFill()
                                default: DT.Color.backgroundSecondary
                                }
                            }
                            .frame(width: 100, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .accessibilityHidden(true)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Up Next")
                                .font(.system(.caption2, design: .default, weight: .bold))
                                .tracking(0.5)
                                .foregroundStyle(DT.Color.accent)
                            Text(next.name)
                                .font(.system(.footnote, design: .default, weight: .semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            if let s = next.parentIndexNumber, let e = next.indexNumber {
                                Text("S\(s) · E\(e)")
                                    .font(.system(.caption2))
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                        }
                        Spacer(minLength: 0)
                        Button { playNextEpisode() } label: {
                            Image(systemName: "play.fill")
                                .font(.system(.subheadline, weight: .semibold))
                                .foregroundStyle(.black)
                                .frame(width: 34, height: 34)
                                .background(.white, in: Circle())
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Play \(next.name)")
                        .playerOverlayButton(cornerRadius: 22)
                        #if os(tvOS)
                        .prefersDefaultFocus(true, in: tvFocusNamespace)
                        #endif
                        Button { dismissUpNext() } label: {
                            Image(systemName: "xmark")
                                .font(.system(.caption, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.7))
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Dismiss")
                        .playerOverlayButton(cornerRadius: 22)
                    }
                    HStack(spacing: 8) {
                        creditsAction("Skip Credits", systemImage: "forward.end.fill", isSelected: false) {
                            skipCredits()
                        }
                        creditsAction("Like", systemImage: "hand.thumbsup", isSelected: currentLikes == true) {
                            rateCurrentItem(true)
                        }
                        creditsAction("Dislike", systemImage: "hand.thumbsdown", isSelected: currentLikes == false) {
                            rateCurrentItem(false)
                        }
                    }
                }
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DT.Radius.lg))
                .overlay(RoundedRectangle(cornerRadius: DT.Radius.lg).stroke(.white.opacity(0.15), lineWidth: 1))
                .frame(maxWidth: 380)
                #if os(tvOS)
                .focusSection()
                #endif
            }
            .padding(.trailing, DT.Spacing.pagePad)
            .padding(.bottom, 100)
        }
        .transition(.move(edge: .trailing).combined(with: .opacity))
        .animation(DT.Animation.fast, value: showUpNext)
    }

    private func creditsAction(_ title: String, systemImage: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: isSelected ? "\(systemImage).fill" : systemImage)
                .font(.system(.caption, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(isSelected ? .black : .white)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.16)),
                    in: RoundedRectangle(cornerRadius: DT.Radius.md))
        }
        .playerOverlayButton(cornerRadius: DT.Radius.md)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Past the credits: on to the next title when they run to the end, or to the scene after
    /// them. Without the server's credits marker, the rest of the title counts as credits.
    private func skipCredits() {
        let now = Double(player.positionTicks) / 10_000_000
        let duration = Double(player.durationTicks) / 10_000_000
        skip(kind: "credits", span: segments.credits ?? (now...max(now, duration)))
    }

    // MARK: - More Like This

    /// The credits panel: the top three suggestions in the middle of the screen (a row in
    /// landscape, a stack in portrait) and Like / Dislike buttons for what was just watched
    /// along the bottom.
    @ViewBuilder
    var moreLikeThisOverlay: some View {
        if showMoreLikeThis, !moreLikeThis.isEmpty {
            ZStack {
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        Button {
                            moreLikeThisDismissed = true
                            withAnimation(DT.Animation.fast) { showMoreLikeThis = false }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(.footnote, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(.white.opacity(0.18), in: Circle())
                        }
                        .playerOverlayButton(cornerRadius: 17)
                        .accessibilityLabel("Dismiss suggestions")
                    }

                    Spacer(minLength: 0)

                    VStack(spacing: 14) {
                        Text("More Like This")
                            .font(.system(.title3, weight: .bold))
                            .foregroundStyle(.white)
                        let top = Array(moreLikeThis.prefix(3))
                        if suggestionsAreHorizontal {
                            HStack(spacing: 14) {
                                ForEach(top) { suggestion in
                                    Button { playSuggestion(suggestion) } label: { suggestionCard(suggestion) }
                                        .playerOverlayButton(cornerRadius: DT.Radius.sm)
                                }
                            }
                        } else {
                            VStack(spacing: 10) {
                                ForEach(top) { suggestion in
                                    Button { playSuggestion(suggestion) } label: { suggestionRow(suggestion) }
                                        .playerOverlayButton(cornerRadius: DT.Radius.sm)
                                }
                            }
                        }
                    }

                    Spacer(minLength: 0)

                    HStack(spacing: 12) {
                        ratingButton(title: "Like", systemImage: "hand.thumbsup", isSelected: currentLikes == true) {
                            rateCurrentItem(true)
                        }
                        ratingButton(title: "Dislike", systemImage: "hand.thumbsdown", isSelected: currentLikes == false) {
                            rateCurrentItem(false)
                        }
                    }
                    .frame(maxWidth: 420)
                    .padding(.bottom, isControlsVisible ? 90 : 0)
                }
                .padding(.horizontal, DT.Spacing.pagePad)
                .padding(.vertical, 20)
                #if os(tvOS)
                .focusSection()
                #endif
            }
            .transition(.opacity)
            .animation(DT.Animation.fast, value: isControlsVisible)
            #if os(tvOS)
            .onExitCommand {
                moreLikeThisDismissed = true
                withAnimation(DT.Animation.fast) { showMoreLikeThis = false }
            }
            #endif
        }
    }

    /// Closes the panel before handing over, since this view can outlive the item it was
    /// showing suggestions for.
    private func playSuggestion(_ suggestion: MediaItem) {
        moreLikeThisDismissed = true
        withAnimation(DT.Animation.fast) { showMoreLikeThis = false }
        onPlayNext(suggestion)
    }

    private func ratingButton(title: String, systemImage: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: isSelected ? "\(systemImage).fill" : systemImage)
                .font(.system(.body, weight: .semibold))
                .foregroundStyle(isSelected ? .black : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.16)),
                    in: RoundedRectangle(cornerRadius: DT.Radius.md))
                .overlay(RoundedRectangle(cornerRadius: DT.Radius.md).stroke(.white.opacity(0.3), lineWidth: 1))
        }
        .playerOverlayButton(cornerRadius: DT.Radius.md)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Landscape (and the always-wide Mac window) lays suggestions out in a row; portrait
    /// stacks them in a list.
    private var suggestionsAreHorizontal: Bool {
        #if os(iOS)
        isLandscape
        #else
        true
        #endif
    }

    private func suggestionImageURL(_ suggestion: MediaItem) -> URL? {
        mediaRepo.imageURL(for: suggestion, type: .thumb, fillWidth: 400)
            ?? mediaRepo.imageURL(for: suggestion, type: .backdrop, fillWidth: 400)
            ?? mediaRepo.imageURL(for: suggestion, type: .primary, fillWidth: 400)
    }

    private func suggestionThumb(_ suggestion: MediaItem) -> some View {
        CachedAsyncImage(url: suggestionImageURL(suggestion)) { phase in
            if case .success(let image) = phase {
                image.resizable().scaledToFill()
            } else {
                DT.Color.backgroundSecondary
            }
        }
    }

    private func suggestionCard(_ suggestion: MediaItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            suggestionThumb(suggestion)
                .frame(width: 176, height: 99)
                .clipShape(RoundedRectangle(cornerRadius: DT.Radius.sm))
            Text(suggestion.name)
                .font(.system(.footnote, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(width: 176, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Play \(suggestion.name)")
    }

    private func suggestionRow(_ suggestion: MediaItem) -> some View {
        HStack(spacing: 12) {
            suggestionThumb(suggestion)
                .frame(width: 128, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: DT.Radius.sm))
            VStack(alignment: .leading, spacing: 3) {
                Text(suggestion.name)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if let year = suggestion.productionYear {
                    Text(String(year))
                        .font(.system(.caption))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "play.fill")
                .font(.system(.footnote))
                .foregroundStyle(.white.opacity(0.8))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Play \(suggestion.name)")
    }

    // MARK: - Are you still watching

    var stillWatchingOverlay: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "eye.slash")
                    .scaledFont(size: 40, weight: .medium)
                    .foregroundStyle(DT.Color.accent)
                VStack(spacing: 6) {
                    Text("Are you still watching?")
                        .font(.system(.title3, design: .default, weight: .bold))
                        .foregroundStyle(.white)
                    if let pendingAutoAdvanceEpisode = pendingAutoAdvanceEpisode {
                        Text("Playback paused before \(pendingAutoAdvanceEpisode.name)")
                            .font(.system(.footnote))
                            .foregroundStyle(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                    }
                }
                VStack(spacing: 12) {
                    Button { continueAfterStillWatchingPrompt() } label: {
                        Text("Continue Watching")
                            .font(.system(.subheadline, design: .default, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(LinearGradient(colors: [DT.Color.accentDeep, DT.Color.accent], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.lg))
                    }
                    #if os(tvOS)
                    .buttonStyle(TVCardButtonStyle())
                    .focusEffectDisabled()
                    .tvFocusRing(cornerRadius: DT.Radius.lg)
                    .prefersDefaultFocus(true, in: tvFocusNamespace)
                    #else
                    .buttonStyle(.plain)
                    #endif

                    Button { stopAfterStillWatchingPrompt() } label: {
                        Text("Stop")
                            .font(.system(.subheadline, design: .default, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    #if os(tvOS)
                    .buttonStyle(TVCardButtonStyle())
                    .focusEffectDisabled()
                    .tvFocusRing(cornerRadius: DT.Radius.md)
                    #else
                    .buttonStyle(.plain)
                    #endif
                }
                .frame(maxWidth: 280)
                #if os(tvOS)
                .focusSection()
                #endif
            }
        }
        .transition(.opacity)
    }

    // MARK: - Casting

    // Not canImport(GoogleCast) — CastManager's isConnected/deviceName/endSession() are all
    // plain cross-platform API that no-ops on their own where GoogleCast isn't linked (see
    // CastManager's own doc comment), and PlayerView.body's `!os(tvOS)` video-surface block
    // (which macOS is now part of) references this view unconditionally within that scope,
    // so it needs to actually exist there even though CastManager.isConnected can never be
    // true on macOS — the branch is simply unreachable there, not absent.
    #if !os(tvOS)
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
        let durationSeconds = Double(player.durationTicks) / 10_000_000
        let liveSeconds = cast.lastKnownPositionSeconds ?? 0
        let shownSeconds = isCastScrubbing ? castScrubTicks / 10_000_000 : liveSeconds
        let fraction = durationSeconds > 0 ? min(max(shownSeconds / durationSeconds, 0), 1) : 0

        return VStack(spacing: 16) {
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
                                castScrubTicks = Double(player.durationTicks) * f
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
                .accessibilityValue("\(timeLabel(ticks: Int64(shownSeconds * 10_000_000))) of \(timeLabel(ticks: player.durationTicks))")
                .accessibilityAdjustableAction { direction in
                    let step = Double(direction == .increment ? skipForwardSeconds : -skipBackwardSeconds)
                    cast.seek(toSeconds: min(max(liveSeconds + step, 0), durationSeconds))
                }

                HStack {
                    Text(timeLabel(ticks: Int64(shownSeconds * 10_000_000)))
                    Spacer()
                    Text("-" + timeLabel(ticks: Int64(max(durationSeconds - shownSeconds, 0) * 10_000_000)))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.7))
                .accessibilityHidden(true)
            }

            HStack(spacing: 24) {
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

                Button { cast.togglePlayPause() } label: {
                    Image(systemName: cast.isPaused ? "play.fill" : "pause.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.white)
                        .frame(minWidth: 64, minHeight: 64)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(cast.isPaused ? "Play" : "Pause")

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
                if let audio = playbackInfo?.audioStreams, audio.count > 1 {
                    Menu {
                        Picker("Audio", selection: Binding(
                            get: { selectedAudioIndex ?? playbackInfo?.defaultAudioStreamIndex ?? audio[0].index },
                            set: { selectCastAudio(index: $0) }
                        )) {
                            ForEach(audio, id: \.index) { Text($0.displayTitle ?? $0.language ?? "Track \($0.index)").tag($0.index) }
                        }
                    } label: {
                        castTrackLabel("Audio", systemImage: "speaker.wave.2")
                    }
                }
                if let subs = playbackInfo?.subtitleStreams, !subs.isEmpty {
                    Menu {
                        Picker("Subtitles", selection: Binding(
                            get: { selectedSubtitleIndex ?? -1 },
                            set: { selectCastSubtitle(index: $0 < 0 ? nil : $0) }
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
    #endif

    private func skipToSegmentEnd() {
        guard let current = currentSkippable else { return }
        skip(kind: current.kind, span: current.span)
    }

    // MARK: - Playback actions

    func togglePlayPause() {
        // A manual play/pause is proof someone's actually there — same signal a manual
        // Up Next tap gives, so it resets the "are you still watching" streak too.
        UserDefaults.standard.set(0, forKey: Self.autoplayStreakKey)
        #if canImport(GoogleCast)
        if CastManager.shared.isConnected {
            // The receiver, not the local player, is the one actually playing — control
            // it instead.
            CastManager.shared.togglePlayPause()
            toggleControlsVisibilityOnAction()
            return
        }
        #endif
        #if !os(tvOS)
        if syncPlayManager.isInGroup, let credential = authManager.state.credential {
            let authHeader = authManager.authClient.authHeader(token: credential.accessToken)
            if player.status == .playing {
                syncPlayManager.requestPause(credential: credential, authHeader: authHeader)
            } else {
                syncPlayManager.requestPlay(credential: credential, authHeader: authHeader)
            }
            toggleControlsVisibilityOnAction()
            return
        }
        #endif
        Task {
            if player.status == .playing { await player.pause() } else { await player.play() }
        }
        toggleControlsVisibilityOnAction()
    }

    func seek(by seconds: Int) {
        let base = pendingSeekTargetTicks ?? player.positionTicks
        let newTicks = min(max(0, base + Int64(seconds) * 10_000_000), player.durationTicks)
        performSeek(to: newTicks)
        toggleControlsVisibilityOnAction()
    }

    /// Routes through SyncPlay's Seek command when in a group (applied once it echoes back
    /// over the WebSocket, same as every other group member sees it) instead of seeking the
    /// local player directly — see PlayerView.applySyncPlayCommand.
    func performSeek(to ticks: Int64) {
        pendingSeekTargetTicks = ticks
        #if canImport(GoogleCast)
        if CastManager.shared.isConnected {
            CastManager.shared.seek(toSeconds: Double(ticks) / 10_000_000)
            return
        }
        #endif
        #if !os(tvOS)
        if syncPlayManager.isInGroup, let credential = authManager.state.credential {
            let authHeader = authManager.authClient.authHeader(token: credential.accessToken)
            syncPlayManager.requestSeek(credential: credential, authHeader: authHeader, positionTicks: ticks)
            return
        }
        #endif
        Task {
            await player.seek(to: ticks)
            if pendingSeekTargetTicks == ticks { pendingSeekTargetTicks = nil }
        }
    }

    private func toggleControlsVisibilityOnAction() {
        if !isControlsVisible { withAnimation(DT.Animation.fast) { isControlsVisible = true } }
        #if os(tvOS)
        if tvControlsHidden { withAnimation(DT.Animation.fast) { tvControlsHidden = false } }
        #endif
        scheduleAutoHide()
    }

    // MARK: - Error / feedback views

    func networkToastView(_ text: String) -> some View {
        VStack {
            HStack(spacing: 8) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(.footnote, weight: .semibold))
                Text(text)
                    .font(.system(.caption, design: .default, weight: .medium))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(.black.opacity(0.7), in: Capsule())
            .padding(.top, 60)
            Spacer()
        }
        .transition(.opacity)
        .allowsHitTesting(false)
    }

    func subtitleOverlay(_ text: String) -> some View {
        // The fixed bottom padding below is only clearance ABOVE the safe area, not a
        // substitute for it — on a device where an ancestor's ignoresSafeArea() (the video
        // surface, Color.black) leaves no safe-area context to inherit, 32/110pt alone
        // wasn't enough to clear the home indicator, and long cues sat behind/under it.
        // Reading the real inset via GeometryReader and adding it explicitly guarantees
        // clearance regardless of what the rest of the hierarchy is doing with safe areas.
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

    /// AetherEngine's native PGS/DVB bitmap cue path — a track Jellyfin has no delivery URL
    /// for, so this is additive to subtitleOverlay above, not a replacement. `cue.position`
    /// is already normalized [0, 1] against the source canvas, so it maps directly onto the
    /// on-screen video rect without needing the exact video frame math a cropped-canvas rip
    /// would technically call for (a simplification, not attempting canvas-to-video-rect
    /// letterbox alignment for v1).
    func bitmapSubtitleOverlay(_ cue: NativeBitmapCue) -> some View {
        GeometryReader { proxy in
            Image(decorative: cue.cgImage, scale: 1)
                .resizable()
                .frame(
                    width: cue.position.width * proxy.size.width,
                    height: cue.position.height * proxy.size.height
                )
                .position(
                    x: cue.position.midX * proxy.size.width,
                    y: cue.position.midY * proxy.size.height
                )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .animation(DT.Animation.fast, value: isControlsVisible)
    }

    func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(.largeTitle))
                .foregroundStyle(Color(hex: "EF4444"))
            Text(message)
                .font(.system(.footnote))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Button("Close") { closePlayer() }
                .font(.system(.footnote, design: .default, weight: .semibold))
                .foregroundStyle(DT.Color.accent)
                #if os(tvOS)
                .buttonStyle(TVCardButtonStyle())
                .focusEffectDisabled()
                .tvFocusRing(cornerRadius: DT.Radius.md)
                #endif
        }
        .padding(24)
        .frame(maxWidth: 320)
    }

    #if canImport(UIKit) && !os(tvOS)
    @ViewBuilder
    var dragAxisIndicator: some View {
        if let dragAxis {
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
                    Text("\(Int(dragValue * 100))%")
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
    #elseif os(macOS)
    /// Same visual language as dragAxisIndicator above (there's no brightness axis to show on
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
                Text("\(Int(volume * 100))%")
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
                audioStreams: playbackInfo?.audioStreams ?? [],
                subtitleStreams: playbackInfo?.subtitleStreams ?? [],
                selectedAudioIndex: selectedAudioIndex,
                selectedSubtitleIndex: selectedSubtitleIndex,
                onSelectAudio: { index in
                    showTrackMenu = false
                    changeTrack(audioIndex: index)
                },
                onSelectSubtitle: { index in
                    showTrackMenu = false
                    changeTrack(subtitleIndex: .some(index))
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    var macChapterListPanel: some View {
        macMenuPanel(title: "Chapters", onDone: { showChapterMenu = false }) {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(chapters.enumerated()), id: \.offset) { index, chapter in
                        let isCurrent = currentChapterIndex == index
                        Button {
                            showChapterMenu = false
                            jumpToChapter(chapter)
                        } label: {
                            HStack(spacing: 12) {
                                ChapterThumbnailView(loader: trickplayLoader, positionTicks: chapter.startPositionTicks)
                                Text(chapter.name ?? "Chapter \(index + 1)")
                                    .font(.system(.footnote, design: .default, weight: isCurrent ? .semibold : .regular))
                                    .foregroundStyle(isCurrent ? DT.Color.accent : DT.Color.textPrimary)
                                Spacer()
                                Text(timeLabel(ticks: chapter.startPositionTicks))
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
    #endif

    func seekFeedbackView(_ feedback: SeekFeedback) -> some View {
        // Positioned by onRight (where the tap actually landed), not forward (which side now
        // seeks which direction) — the indicator shows up under your finger, just with
        // whichever icon/direction that side now performs. A LEADING Spacer pushes content to
        // the trailing edge, not the other way around — this was inverted before, putting the
        // indicator on the opposite side from the actual tap.
        HStack {
            if feedback.onRight { Spacer() }
            VStack(spacing: 4) {
                Image(systemName: skipIconName(seconds: feedback.seconds, forward: feedback.forward))
                    .font(.system(.title))
                Text("\(feedback.seconds)s")
                    .font(.system(.caption2, design: .default, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(20)
            .background(.black.opacity(0.4), in: Circle())
            if !feedback.onRight { Spacer() }
        }
        .padding(.horizontal, 40)
        .transition(.opacity)
        .allowsHitTesting(false)
    }
}

// MARK: - Audio & subtitle track selection

struct TrackSelectionSheet: View {
    let audioStreams: [JellyfinMediaStream]
    let subtitleStreams: [JellyfinMediaStream]
    let selectedAudioIndex: Int?
    let selectedSubtitleIndex: Int?
    let onSelectAudio: (Int) -> Void
    let onSelectSubtitle: (Int?) -> Void
    /// Set to offer a search of the server's subtitle providers for this item.
    var subtitleSearchItemId: String? = nil
    var onSubtitleDownloaded: () -> Void = {}

    var body: some View {
        List {
            if !audioStreams.isEmpty {
                Section("Audio") {
                    ForEach(audioStreams, id: \.index) { stream in
                        trackRow(label(for: stream), isSelected: stream.index == selectedAudioIndex) {
                            onSelectAudio(stream.index)
                        }
                    }
                }
            }
            Section("Subtitles") {
                trackRow("Off", isSelected: selectedSubtitleIndex == nil) {
                    onSelectSubtitle(nil)
                }
                ForEach(subtitleStreams, id: \.index) { stream in
                    trackRow(label(for: stream), isSelected: stream.index == selectedSubtitleIndex) {
                        onSelectSubtitle(stream.index)
                    }
                }
                if let subtitleSearchItemId {
                    NavigationLink {
                        SubtitleSearchView(itemId: subtitleSearchItemId, onDownloaded: onSubtitleDownloaded)
                    } label: {
                        Label("Search for Subtitles…", systemImage: "magnifyingglass")
                            .foregroundStyle(DT.Color.accent)
                    }
                    .listRowBackground(DT.Color.backgroundSecondary)
                }
            }
        }
        #if canImport(UIKit) && !os(tvOS)
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        #endif
        .screenBackground()
    }

    private func trackRow(_ label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label).foregroundStyle(DT.Color.textPrimary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark").foregroundStyle(DT.Color.accent)
                }
            }
        }
        .listRowBackground(DT.Color.backgroundSecondary)
    }

    private func label(for stream: JellyfinMediaStream) -> String {
        if let title = stream.displayTitle, !title.isEmpty { return title }
        let parts = [stream.language, stream.codec?.uppercased()].compactMap { $0 }
        return parts.isEmpty ? "Track \(stream.index)" : parts.joined(separator: " · ")
    }
}

private extension View {
    /// A button on the player's own overlays (suggestions, X-Ray): plain where it's pointed or
    /// tapped at, a focus ring on tvOS where the remote moves between them.
    @ViewBuilder
    func playerOverlayButton(cornerRadius: CGFloat) -> some View {
        #if os(tvOS)
        buttonStyle(TVCardButtonStyle())
            .focusEffectDisabled()
            .tvFocusRing(cornerRadius: cornerRadius, prominent: true)
        #else
        buttonStyle(.plain)
        #endif
    }
}
