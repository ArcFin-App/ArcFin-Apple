// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import MediaEngine
import AppKit

extension PlayerView {

    /// Mouse-pointer analog of the iOS player's tapGesture: click toggles controls the same as
    /// a tap, double-click seeks by the configured skip amount (Settings > Playback). No
    /// drag-to-adjust-brightness/volume gesture on macOS
    /// (that's a touch-surface idiom) — Up/Down arrow keys cover volume instead (see
    /// adjustMacVolume), and there's no equivalent brightness control at all outside System
    /// Settings, so it's simply not offered.
    func macTapGesture(width: CGFloat) -> some Gesture {
        SpatialTapGesture(count: 2)
            .onEnded { value in handleMacDoubleClick(at: value.location, width: width) }
            .exclusively(before:
                SpatialTapGesture(count: 1)
                    .onEnded { _ in model.toggleControls() }
            )
    }

    private func handleMacDoubleClick(at location: CGPoint, width: CGFloat) {
        guard doubleTapToSkip, !model.isLive else { model.toggleControls(); return }
        let tappedRight = location.x > width / 2
        let forward = tappedRight
        let seconds = forward ? skipForwardSeconds : skipBackwardSeconds
        model.seek(by: forward ? seconds : -seconds)
        model.seekFeedback = SeekFeedback(forward: forward, onRight: tappedRight, seconds: seconds)
        Task {
            try? await Task.sleep(for: .seconds(0.6))
            model.seekFeedback = nil
        }
    }

    /// Hover is the pointer-driven equivalent of a touch tap revealing controls — there's no
    /// "the finger just touched the glass" moment with a mouse, so any mouse movement over
    /// the video surface re-shows the controls and restarts the same auto-hide timer a tap
    /// would.
    func handleMacMouseActivity() {
        if !model.isControlsVisible {
            withAnimation(DT.Animation.fast) { model.isControlsVisible = true }
        }
        model.scheduleAutoHide()
    }

    /// Sets output volume directly through the active engine (PlayerModel.setEngineVolume)
    /// rather than through a hidden system slider — macOS has no per-app "hidden MPVolumeView"
    /// trick to reach for the way iOS does.
    func adjustMacVolume(by delta: Double) {
        macVolume = min(max(macVolume + delta, 0), 1)
        model.setEngineVolume(Float(macVolume))
        macVolumeHUD = macVolume
        macVolumeHUDTask?.cancel()
        macVolumeHUDTask = Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            macVolumeHUD = nil
        }
    }

    func toggleMacMute() {
        if macVolume == 0 {
            adjustMacVolume(by: macVolumeBeforeMute ?? 1)
            macVolumeBeforeMute = nil
        } else {
            macVolumeBeforeMute = macVolume
            adjustMacVolume(by: -macVolume)
        }
    }
}
