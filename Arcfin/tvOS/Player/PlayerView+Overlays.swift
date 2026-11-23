// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI
import MediaEngine

// The overlays over the Apple TV player, each its own focus section for the remote.
extension PlayerView {

    /// Who's in this, beside the picture: a panel on the trailing edge in landscape, along the
    /// bottom in portrait. Playback carries on; picking someone pauses and opens their page.
    @ViewBuilder
    var castPanelOverlay: some View {
        if showCastPanel {
            GeometryReader { proxy in
                let landscape = proxy.size.width > proxy.size.height
                ZStack(alignment: landscape ? .trailing : .bottom) {
                    Color.black.opacity(0.25)
                        .ignoresSafeArea()

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
                                withAnimation(DT.Animation.fast) { showCastPanel = false }
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
                                ForEach(model.castMembers) { person in
                                    Button { openCastPanelPerson(person) } label: {
                                        CastPanelPersonRow(person: person, compact: !landscape)
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
                    .focusSection()
                }
            }
            .onExitCommand { withAnimation(DT.Animation.fast) { showCastPanel = false } }
        }
    }

    // MARK: - Skip intro/credits

    /// On its own in the corner while the controls are hidden, where a click skips, for a few
    /// seconds unless it's counting down to skip. With the controls up it's in them instead
    /// (skipControl).
    var skipButton: some View {
        Group {
            if let label = model.skipButtonLabel, model.showsFloatingSkip, model.tvControlsHidden {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        skipSegmentButton(label)
                            .prefersDefaultFocus(true, in: tvFocusNamespace)
                            // It holds focus, so any swipe brings up the controls; a click skips.
                            .onMoveCommand { _ in model.toggleControlsVisibilityOnAction() }
                            .padding(.trailing, DT.Spacing.pagePad)
                            .padding(.bottom, 100)
                    }
                }
            }
        }
    }

    /// The skip button's place in the controls, above the scrubber at the trailing edge.
    @ViewBuilder
    var skipControl: some View {
        if let label = model.skipButtonLabel {
            HStack {
                Spacer()
                skipSegmentButton(label)
            }
            .focusSection()
        }
    }

    private func skipSegmentButton(_ label: String) -> some View {
        Button { model.skipToSegmentEnd() } label: {
            SkipSegmentLabel(model: model, label: label)
        }
        .buttonStyle(TVCardButtonStyle())
        .focusEffectDisabled()
        .tvFocusRing(cornerRadius: DT.Radius.lg, prominent: true)
    }

    /// The segment playback is in right now, if any, with its button label.

    // MARK: - Up Next

    /// The credits of anything with a title after it (the next episode, or the next one in a
    /// playlist or collection): what's next, with Play Next, Like and Dislike.
    func upNextCard(_ next: MediaItem) -> some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        if let url = model.source.isLocal ? model.source.localImageURL(for: next.id) : mediaRepo.imageURL(for: next, type: .thumb, fillWidth: 240) {
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
                        .prefersDefaultFocus(true, in: tvFocusNamespace)
                        CreditsActionButton(title: "Like", systemImage: "hand.thumbsup", isSelected: model.currentLikes == true) {
                            model.rateCurrentItem(true)
                        }
                        CreditsActionButton(title: "Dislike", systemImage: "hand.thumbsdown", isSelected: model.currentLikes == false) {
                            model.rateCurrentItem(false)
                        }
                    }
                }
                .padding(10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DT.Radius.lg))
                .overlay(RoundedRectangle(cornerRadius: DT.Radius.lg).stroke(.white.opacity(0.15), lineWidth: 1))
                .frame(maxWidth: 380)
                .focusSection()
            }
            .padding(.trailing, DT.Spacing.pagePad)
            .padding(.bottom, 100)
        }
        .transition(.move(edge: .trailing).combined(with: .opacity))
        .animation(DT.Animation.fast, value: model.showUpNext)
    }

    // MARK: - More Like This

    /// The credits panel: the top three suggestions in the middle of the screen (a row in
    /// landscape, a stack in portrait) and Like / Dislike buttons for what was just watched
    /// along the bottom.
    @ViewBuilder
    var moreLikeThisOverlay: some View {
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
                        // The TV screen is always wide enough for the suggestions in a row.
                        HStack(spacing: 14) {
                            ForEach(top) { suggestion in
                                Button { model.playSuggestion(suggestion) } label: { SuggestionCard(suggestion: suggestion) }
                                    .playerOverlayButton(cornerRadius: DT.Radius.sm)
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
                .focusSection()
            }
            .transition(.opacity)
            .animation(DT.Animation.fast, value: model.isControlsVisible)
            .onExitCommand {
                model.moreLikeThisDismissed = true
                withAnimation(DT.Animation.fast) { model.showMoreLikeThis = false }
            }
        }
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
                    .buttonStyle(TVCardButtonStyle())
                    .focusEffectDisabled()
                    .tvFocusRing(cornerRadius: DT.Radius.lg)
                    .prefersDefaultFocus(true, in: tvFocusNamespace)

                    Button { model.stopAfterStillWatchingPrompt() } label: {
                        Text("Stop")
                            .font(.system(.subheadline, design: .default, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .buttonStyle(TVCardButtonStyle())
                    .focusEffectDisabled()
                    .tvFocusRing(cornerRadius: DT.Radius.md)
                }
                .frame(maxWidth: 280)
                .focusSection()
            }
        }
        .transition(.opacity)
    }

    // MARK: - Error

    func errorView(_ message: String) -> some View {
        VStack(spacing: 28) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 64))
                .foregroundStyle(DT.Color.palette("F43F5E"))
                .accessibilityHidden(true)
            Text(message)
                .font(.system(.body))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 24) {
                errorButton("Try Again", prominent: true) { model.retry() }
                    .prefersDefaultFocus(true, in: tvFocusNamespace)
                if model.isLive, model.nextEpisode != nil {
                    errorButton("Next Channel") { model.playNextEpisode() }
                }
                errorButton("Close") { closePlayer() }
            }
        }
        .padding(48)
        .frame(maxWidth: 900)
        .focusSection()
    }

    private func errorButton(_ title: LocalizedStringKey, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(.callout, weight: .semibold))
                .foregroundStyle(prominent ? DT.Color.onAccent : .white)
                .padding(.horizontal, 36)
                .padding(.vertical, 16)
                .background(prominent ? DT.Color.accent : Color.white.opacity(0.15), in: Capsule())
        }
        .buttonStyle(TVCardButtonStyle())
        .focusEffectDisabled()
        .tvFocusRing(cornerRadius: 40, prominent: true)
    }

}
