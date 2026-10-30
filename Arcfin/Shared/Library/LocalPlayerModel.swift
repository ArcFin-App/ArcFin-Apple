// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import MediaEngine
import SwiftVLC

/// A picked file's playback and its controls, shared by the iPhone, iPad and Mac `LocalPlayerView`.
@MainActor @Observable
final class LocalPlayerModel {
    let player = VLCEnginePlayer()
    var isControlsVisible = true
    private var hideControlsTask: Task<Void, Never>?
    private(set) var isScrubbing = false
    private(set) var scrubTicks: Double = 0
    var showTrackMenu = false
    var isFillScreen = false

    func start(_ url: URL) async {
        _ = url.startAccessingSecurityScopedResource()
        try? await player.load(url: url, startPositionTicks: 0)
        await player.play()
    }

    func stop(_ url: URL) {
        Task { await player.stop() }
        url.stopAccessingSecurityScopedResource()
    }

    func applyFillScreen() {
        player.vlcPlayer.aspectRatio = isFillScreen ? .fill : .default
    }

    func togglePlayPause() {
        Task { if player.status == .playing { await player.pause() } else { await player.play() } }
        toggleControlsVisibilityOnAction()
    }

    func seek(by seconds: Int) {
        let newTicks = max(0, player.positionTicks + Int64(seconds) * 10_000_000)
        Task { await player.seek(to: min(newTicks, player.durationTicks)) }
        toggleControlsVisibilityOnAction()
    }

    func scrub(to fraction: Double) {
        isScrubbing = true
        hideControlsTask?.cancel()
        scrubTicks = Double(player.durationTicks) * fraction
    }

    func endScrub() {
        Task {
            await player.seek(to: Int64(scrubTicks))
            isScrubbing = false
            scheduleAutoHide()
        }
    }

    func toggleControls() {
        withAnimation(DT.Animation.fast) { isControlsVisible.toggle() }
        if isControlsVisible { scheduleAutoHide() }
    }

    private func toggleControlsVisibilityOnAction() {
        if !isControlsVisible { withAnimation(DT.Animation.fast) { isControlsVisible = true } }
        scheduleAutoHide()
    }

    func scheduleAutoHide() {
        hideControlsTask?.cancel()
        hideControlsTask = Task {
            try? await Task.sleep(for: .seconds(3.5))
            guard !Task.isCancelled, player.status == .playing else { return }
            withAnimation(DT.Animation.fast) { isControlsVisible = false }
        }
    }

    var shownTicks: Int64 { isScrubbing ? Int64(scrubTicks) : player.positionTicks }

    var remainingLabel: String {
        let remaining = max(player.durationTicks - player.positionTicks, 0)
        return "-" + Self.timeLabel(ticks: remaining)
    }

    static func timeLabel(ticks: Int64) -> String {
        let totalSeconds = Int(Double(ticks) / 10_000_000)
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
