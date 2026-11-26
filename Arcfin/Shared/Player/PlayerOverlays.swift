// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI
import MediaEngine

// The touch and pointer players' overlays, used by the iPhone, iPad and Mac `PlayerView`.
// Apple TV has its own, built around focus.

/// The scrub bar: dragged to seek, with the trickplay frame above it while dragging.
struct PlayerScrubber: View {
    let model: PlayerModel

    @AppStorage("skipForwardSeconds") private var skipForwardSeconds = 10
    @AppStorage("skipBackwardSeconds") private var skipBackwardSeconds = 10

    static let trickplaySize = CGSize(width: 140, height: 79)

    var body: some View {
        let trackHeight: CGFloat = 4
        return GeometryReader { proxy in
            let duration = max(model.player.durationTicks, 1)
            let fraction = Double(model.isScrubbing ? Int64(model.scrubTicks) : (model.pendingSeekTargetTicks ?? model.player.positionTicks)) / Double(duration)
            let thumbX = proxy.size.width * min(max(fraction, 0), 1)

            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.25)).frame(height: trackHeight)
                Capsule().fill(DT.Color.accent)
                    .frame(width: thumbX, height: trackHeight)

                // Some sources report duplicate chapter start times — id'd by array offset
                // rather than startPositionTicks so SwiftUI never sees a colliding identity.
                ForEach(Array(model.chapters.dropFirst().enumerated()), id: \.offset) { _, chapter in
                    let x = proxy.size.width * min(max(Double(chapter.startPositionTicks) / Double(duration), 0), 1)
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
                    TrickplayPreview(image: model.scrubThumbnail, size: Self.trickplaySize)
                        .offset(x: min(max(thumbX - Self.trickplaySize.width / 2, 0), proxy.size.width - Self.trickplaySize.width),
                                y: -(Self.trickplaySize.height / 2 + 21))
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            // DragGesture tracks a mouse drag on macOS the same way it tracks a touch drag on
            // iOS — no platform split needed for the gesture itself, only for what's iOS-only
            // inside it (HapticManager already safely no-ops off iOS on its own).
            .onScrub(width: proxy.size.width, changed: { fraction in
                if !model.isScrubbing { HapticManager.impact(.light) }
                model.isScrubbing = true
                model.hideControlsTask?.cancel()
                model.scrubTicks = Double(model.player.durationTicks) * fraction
                model.updateScrubThumbnail()
            }, ended: {
                HapticManager.impact(.light)
                model.performSeek(to: Int64(model.scrubTicks))
                model.isScrubbing = false
                model.scrubThumbnail = nil
                model.scheduleAutoHide()
            })
        }
        .frame(height: 20)
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(model.timeLabel(ticks: model.elapsedTicks)) of \(model.timeLabel(ticks: model.player.durationTicks))")
        .accessibilityAdjustableAction { direction in
            model.seek(by: direction == .increment ? skipForwardSeconds : -skipBackwardSeconds)
        }
    }
}

/// "2× ▸▸" at the top while playback is held at speed.
struct SpeedBoostBadge: View {
    let model: PlayerModel

    var body: some View {
        VStack {
            if model.isSpeedBoosting {
                HStack(spacing: 6) {
                    Text("\(model.holdSpeed.formatted())×")
                        .font(.system(.subheadline, weight: .bold))
                        .monospacedDigit()
                    Image(systemName: "forward.fill")
                        .font(.system(.caption, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.black.opacity(0.55), in: Capsule())
                .padding(.top, 24 * DT.Scale.font)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .accessibilityLabel(Text("Playing at \(model.holdSpeed.formatted()) times speed"))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
        .animation(DT.Animation.fast, value: model.isSpeedBoosting)
    }
}

/// Skip Intro, Credits and the like, with the auto-skip countdown filling it.
struct SkipSegmentLabel: View {
    let model: PlayerModel
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Text(label).font(.system(.footnote, design: .default, weight: .semibold))
            Image(systemName: "forward.fill").font(.system(.caption))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background {
            if let countdown = model.autoSkipCountdown, countdown.kind == model.skipButtonKind {
                CountdownFill(countdown: countdown, color: .white.opacity(0.28))
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DT.Radius.lg))
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: DT.Radius.lg).stroke(.white.opacity(0.15), lineWidth: 1))
    }
}

/// The skip button on its own in the corner while the controls are hidden, for a few seconds
/// unless it's counting down to skip. With the controls up it sits in them instead
/// (`SkipSegmentControl`).
struct SkipSegmentButton: View {
    let model: PlayerModel
    let controlsShown: Bool

    var body: some View {
        if let label = model.skipButtonLabel, model.showsFloatingSkip, !controlsShown {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button { model.skipToSegmentEnd() } label: {
                        SkipSegmentLabel(model: model, label: label)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, DT.Spacing.pagePad)
                    .padding(.bottom, 100)
                }
            }
        }
    }
}

/// The skip button's place in the controls, above the scrubber at the trailing edge.
struct SkipSegmentControl: View {
    let model: PlayerModel

    var body: some View {
        if let label = model.skipButtonLabel {
            HStack {
                Spacer()
                Button { model.skipToSegmentEnd() } label: {
                    SkipSegmentLabel(model: model, label: label)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// The credits of anything with a title after it (the next episode, or the next one in a
/// playlist or collection): what's next, with Play Next, Like and Dislike.
struct UpNextCard: View {
    let model: PlayerModel
    let next: MediaItem

    @Environment(MediaRepository.self) private var mediaRepo

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        if let url = model.source.isLocal ? model.source.localImageURL(for: next.id) : mediaRepo.landscapeURL(for: next) {
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
                        Button { model.dismissUpNext() } label: {
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
                        // With something up next, going on to it comes before skipping the credits.
                        CreditsActionButton(title: next.type == .episode ? "Next Episode" : "Play Next",
                                            systemImage: "play", isSelected: true, countdown: model.upNextCountdownState) {
                            model.playNextEpisode()
                        }
                        .accessibilityLabel("Play \(next.name)")
                        if model.capabilities.rating {
                            CreditsActionButton(title: "Like", systemImage: "hand.thumbsup", isSelected: model.currentLikes == true) {
                                model.rateCurrentItem(true)
                            }
                            CreditsActionButton(title: "Dislike", systemImage: "hand.thumbsdown", isSelected: model.currentLikes == false) {
                                model.rateCurrentItem(false)
                            }
                        }
                    }
                }
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DT.Radius.lg))
                .overlay(RoundedRectangle(cornerRadius: DT.Radius.lg).stroke(.white.opacity(0.15), lineWidth: 1))
                .frame(maxWidth: 380)
            }
            .padding(.trailing, DT.Spacing.pagePad)
            .padding(.bottom, 100)
        }
        .transition(.move(edge: .trailing).combined(with: .opacity))
        .animation(DT.Animation.fast, value: model.showUpNext)
    }
}

/// The credits panel: the top three suggestions in the middle of the screen (a row in
/// landscape, a stack in portrait) and Like / Dislike buttons for what was just watched
/// along the bottom.
struct MoreLikeThisPanel: View {
    let model: PlayerModel
    /// Landscape (and the always-wide Mac window) lays suggestions out in a row; portrait
    /// stacks them in a list.
    let suggestionsAreHorizontal: Bool

    var body: some View {
        if model.showMoreLikeThis, !model.moreLikeThis.isEmpty {
            ZStack {
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        Button {
                            model.moreLikeThisDismissed = true
                            withAnimation(DT.Animation.fast) { model.showMoreLikeThis = false }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(.footnote, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(.white.opacity(0.18), in: Circle())
                                .frame(width: 44, height: 44)
                                .contentShape(Circle())
                        }
                        .playerOverlayButton(cornerRadius: 22)
                        .accessibilityLabel("Dismiss suggestions")
                    }

                    Spacer(minLength: 0)

                    VStack(spacing: 14) {
                        Text("More Like This")
                            .font(.system(.title3, weight: .bold))
                            .foregroundStyle(.white)
                        let top = Array(model.moreLikeThis.prefix(3))
                        if suggestionsAreHorizontal {
                            HStack(spacing: 14) {
                                ForEach(top) { suggestion in
                                    Button { model.playSuggestion(suggestion) } label: { SuggestionCard(suggestion: suggestion) }
                                        .playerOverlayButton(cornerRadius: DT.Radius.sm)
                                }
                            }
                        } else {
                            VStack(spacing: 10) {
                                ForEach(top) { suggestion in
                                    Button { model.playSuggestion(suggestion) } label: { SuggestionRow(suggestion: suggestion) }
                                        .playerOverlayButton(cornerRadius: DT.Radius.sm)
                                }
                            }
                        }
                    }

                    Spacer(minLength: 0)

                    HStack(spacing: 12) {
                        // Nothing up next: Skip Credits joins Like and Dislike when the server
                        // marks the credits.
                        if model.segments.credits != nil {
                            CreditsRatingButton(title: "Skip Credits", systemImage: "forward.end", isSelected: false) {
                                model.skipCredits()
                            }
                        }
                        CreditsRatingButton(title: "Like", systemImage: "hand.thumbsup", isSelected: model.currentLikes == true) {
                            model.rateCurrentItem(true)
                        }
                        CreditsRatingButton(title: "Dislike", systemImage: "hand.thumbsdown", isSelected: model.currentLikes == false) {
                            model.rateCurrentItem(false)
                        }
                    }
                    .frame(maxWidth: model.segments.credits != nil ? 560 : 420)
                    .padding(.bottom, model.isControlsVisible ? 90 : 0)
                }
                .padding(.horizontal, DT.Spacing.pagePad)
                .padding(.vertical, 20)
            }
            .transition(.opacity)
            .animation(DT.Animation.fast, value: model.isControlsVisible)
        }
    }
}

/// Who's in this, beside the picture: a panel on the trailing edge in landscape, along the
/// bottom in portrait. Playback carries on; picking someone pauses and opens their page.
struct CastPanel: View {
    let item: MediaItem
    let castMembers: [MediaPerson]
    @Binding var isPresented: Bool
    /// A photo kept on this device, for a download's cast.
    var photoURL: (MediaPerson) -> URL? = { _ in nil }
    /// Opens the person's page; nil where there's no server to show it from.
    let onSelect: ((MediaPerson) -> Void)?

    var body: some View {
        if isPresented {
            GeometryReader { proxy in
                let landscape = proxy.size.width > proxy.size.height
                ZStack(alignment: landscape ? .trailing : .bottom) {
                    Color.black.opacity(0.25)
                        .ignoresSafeArea()
                        .onTapGesture { withAnimation(DT.Animation.fast) { isPresented = false } }

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Cast & Characters")
                                    .font(.system(.headline, weight: .bold))
                                    .foregroundStyle(.white)
                                Text("In \(item.type == .episode ? (item.seriesName ?? item.name) : item.name)")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.6))
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button {
                                withAnimation(DT.Animation.fast) { isPresented = false }
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
                            .accessibilityLabel("Close Cast & Characters")
                        }
                        ScrollView(landscape ? .vertical : .horizontal, showsIndicators: false) {
                            let layout = landscape
                                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
                                : AnyLayout(HStackLayout(alignment: .top, spacing: 14))
                            layout {
                                ForEach(castMembers) { person in
                                    if let onSelect {
                                        Button { onSelect(person) } label: {
                                            CastPanelPersonRow(person: person, compact: !landscape, localPhoto: photoURL(person))
                                        }
                                        .playerOverlayButton(cornerRadius: DT.Radius.md)
                                    } else {
                                        CastPanelPersonRow(person: person, compact: !landscape, localPhoto: photoURL(person))
                                            .accessibilityElement(children: .combine)
                                    }
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
                }
            }
        }
    }
}

struct StillWatchingPrompt: View {
    let model: PlayerModel

    var body: some View {
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
                    if let pendingAutoAdvanceEpisode = model.pendingAutoAdvanceEpisode {
                        Text("Playback paused before \(pendingAutoAdvanceEpisode.name)")
                            .font(.system(.footnote))
                            .foregroundStyle(.white.opacity(0.6))
                            .multilineTextAlignment(.center)
                    }
                }
                VStack(spacing: 12) {
                    Button { model.continueAfterStillWatchingPrompt() } label: {
                        Text("Continue Watching")
                            .font(.system(.subheadline, design: .default, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(LinearGradient(colors: [DT.Color.accentDeep, DT.Color.accent], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.lg))
                    }
                    .buttonStyle(.plain)

                    Button { model.stopAfterStillWatchingPrompt() } label: {
                        Text("Stop")
                            .font(.system(.subheadline, design: .default, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: 280)
            }
        }
        .transition(.opacity)
    }
}

struct PlayerErrorView: View {
    let message: String
    var retry: (() -> Void)? = nil
    /// On a channel, moves on to the next one in the list.
    var nextChannel: (() -> Void)? = nil
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(.largeTitle))
                .foregroundStyle(DT.Color.palette("F43F5E"))
                .accessibilityHidden(true)
            Text(message)
                .font(.system(.subheadline))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                if let retry {
                    Button("Try Again", action: retry)
                        .buttonStyle(.glassProminent)
                        .tint(DT.Color.accent)
                        .foregroundStyle(DT.Color.onAccent)
                }
                if let nextChannel {
                    Button("Next Channel", action: nextChannel)
                        .buttonStyle(.glass)
                }
            }
            .font(.system(.subheadline, weight: .semibold))
            Button("Close") { onClose() }
                .font(.system(.footnote, design: .default, weight: .semibold))
                .foregroundStyle(DT.Color.accent)
        }
        .padding(24)
        .frame(maxWidth: 360)
    }
}
