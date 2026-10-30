// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import MediaEngine
import SwiftVLC

/// Plays any file the user picks via Files (the "On This Device" section) — always VLC,
/// same reasoning as OfflinePlayerView: an arbitrary local file can be any container/codec,
/// and VLC opens it natively without AVFoundation's mkv/HEVC-tag limitations. Simpler than
/// OfflinePlayerView by design: no Jellyfin metadata exists for a raw picked file, so no
/// trickplay/skip-intro/resume-position — just playback, subtitle tracks VLC finds in the
/// file itself, and the same fill-screen/rotate/PiP affordances the other players have.
struct LocalPlayerView: View {
    let url: URL

    @Environment(\.dismiss) private var dismiss
    @State private var model = LocalPlayerModel()
    @State private var vlcPipController: SwiftVLC.PiPController?

    var body: some View {
        bodyContent.alwaysDarkPlayer()
    }

    @ViewBuilder
    private var bodyContent: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { proxy in
                // See PlayerView/OfflinePlayerView's own comment on why hit-testing is
                // disabled here — PiPVideoView's native drawable is itself interactive and
                // would otherwise swallow the tap before the toggleControls gesture sees it.
                ZStack {
                    PiPVideoView(model.player.vlcPlayer, controller: $vlcPipController,
                                 startsAutomaticallyFromInline: UserDefaults.standard.bool(forKey: "autoPictureInPicture"),
                                 managesAudioSession: false)
                        .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
                .onTapGesture { model.toggleControls() }
            }
            .ignoresSafeArea()

            if model.player.status == .idle || model.player.status == .loading || model.player.isBuffering {
                ProgressView().tint(.white).scaleEffect(1.4)
            }

            if model.isControlsVisible {
                controlsOverlay.transition(.opacity)
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .keepsScreenAwake(status: model.player.status)
        .task { await model.start(url) }
        .onDisappear {
            model.stop(url)
            resetPlayerOrientation()
        }
        .onChange(of: model.player.status) { _, status in
            if status == .playing { model.scheduleAutoHide() }
            if status == .ended { closeRotatedPlayer { dismiss() } }
        }
        .onChange(of: model.isFillScreen) { _, _ in
            model.applyFillScreen()
        }
        .sheet(isPresented: $model.showTrackMenu) {
            LocalPlayerTrackSheet(model: model)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var controlsOverlay: some View {
        VStack(spacing: 0) {
            topBar
            Spacer()
            LocalPlayerBottomBar(model: model)
        }
        .background(LocalPlayerScrim())
    }

    private var topBar: some View {
        HStack(spacing: 16) {
            Button { closeRotatedPlayer { dismiss() } } label: {
                Image(systemName: "chevron.down")
                    .font(.system(.title3, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Close")
            Text(url.deletingPathExtension().lastPathComponent)
                .font(.system(.subheadline, design: .default, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer()
            AirPlayButton().frame(width: 44, height: 44)
            if vlcPipController != nil {
                Button { vlcPipController?.toggle() } label: {
                    Image(systemName: "pip.enter")
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Picture in Picture")
            }
            Button { togglePlayerOrientation() } label: {
                Image(systemName: "rotate.right")
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Rotate")
            Button { model.isFillScreen.toggle() } label: {
                Image(systemName: model.isFillScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.system(.body, weight: .semibold))
                    .foregroundStyle(model.isFillScreen ? DT.Color.accent : .white)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(model.isFillScreen ? "Fit to screen" : "Fill screen")
            if !model.player.availableSubtitleTracks.isEmpty {
                Button { model.showTrackMenu = true } label: {
                    Image(systemName: "captions.bubble")
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Subtitles and audio")
            }
        }
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.top, 8)
    }
}
