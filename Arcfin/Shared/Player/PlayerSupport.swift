// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI
import MediaEngine

// MARK: - Shared playback request

struct PlaybackRequest: Identifiable, Equatable {
    let id = UUID()
    let item: MediaItem
    let startTicks: Int64
}

// MARK: - Skip interval

/// Curated so every option maps to a real SF Symbol — goforward./gobackward. numbered
/// variants only exist for these specific values, not arbitrary integers. (20 was dropped —
/// no numbered symbol exists for it, so it only ever showed the plain unnumbered glyph.)
let skipIntervalOptions = [5, 10, 15, 30, 45, 60]

/// Falls back to the plain (unnumbered) glyph for a value with no matching numbered symbol —
/// shouldn't happen via the Settings picker above, but anyone who already had 20 selected
/// before it was dropped, or a future direct-entry field, could still produce one.
func skipIconName(seconds: Int, forward: Bool) -> String {
    let base = forward ? "goforward" : "gobackward"
    guard skipIntervalOptions.contains(seconds) else { return base }
    return "\(base).\(seconds)"
}

extension PlayerView {
    struct AutoActionCountdown: Equatable {
        let kind: String
        let startedAt: Date
        let seconds: Double
    }

    struct SeekFeedback: Identifiable, Equatable {
        let id = UUID()
        let forward: Bool
        /// Which side of the screen was actually tapped — kept separate from `forward` so the
        /// indicator's on-screen position is driven by where the tap landed, not by which
        /// direction that tap happens to seek.
        let onRight: Bool
        /// Forward and backward can be configured to different skip amounts (Settings >
        /// Playback), so the indicator has to show whichever one this particular tap used.
        let seconds: Int
    }

    /// Set when the player is about to be replaced by the next title in the same cover, so
    /// the outgoing instance doesn't unlock the orientation the viewer had chosen.
    static var keepOrientationOnNextDisappear = false

    /// How long an automatic skip or Up Next waits, so it can be seen and cancelled first.
    static var autoActionSeconds: Double {
        Double(min(max(UserDefaults.standard.object(forKey: "upNextCountdownSeconds") as? Int ?? 5, 3), 5))
    }
}

extension View {
    /// Keeps the display on while a player is loading, buffering or playing; once paused,
    /// ended or failed the device can sleep as usual.
    func keepsScreenAwake(status: PlaybackStatus) -> some View {
        onAppear { ScreenAwake.set(true) }
            .onChange(of: status) { _, status in
                switch status {
                case .idle, .loading, .playing: ScreenAwake.set(true)
                case .paused, .ended, .failed: ScreenAwake.set(false)
                }
            }
            .onDisappear { ScreenAwake.set(false) }
    }
}

/// The player's spinner. A start or rebuffer that runs past a couple of seconds also says what
/// it's waiting on, so a slow server or connection doesn't look like a frozen app.
struct PlayerLoadingIndicator: View {
    let status: String
    @State private var showsStatus = false

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(.white)
                .scaleEffect(1.4)
            if showsStatus {
                Text(status)
                    .font(.system(.footnote, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 32)
        .animation(.easeInOut(duration: 0.25), value: showsStatus)
        .animation(.easeInOut(duration: 0.25), value: status)
        .task {
            try? await Task.sleep(for: .seconds(2))
            showsStatus = true
        }
    }
}

/// Fills left to right over an automatic action's countdown, behind the button it belongs to.
struct CountdownFill: View {
    let countdown: PlayerView.AutoActionCountdown
    let color: Color

    var body: some View {
        TimelineView(.animation) { context in
            let progress = min(max(context.date.timeIntervalSince(countdown.startedAt) / countdown.seconds, 0), 1)
            GeometryReader { proxy in
                color.frame(width: proxy.size.width * progress)
            }
        }
        .allowsHitTesting(false)
    }
}
