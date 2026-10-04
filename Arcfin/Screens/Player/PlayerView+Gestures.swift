// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
#if canImport(UIKit) && !os(tvOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

#if canImport(UIKit) && !os(tvOS)
extension PlayerView {

    var activeWindowScene: UIWindowScene? {
        UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
    }

    func tapGesture(width: CGFloat) -> some Gesture {
        SpatialTapGesture(count: 2)
            .onEnded { value in handleDoubleTap(at: value.location, width: width) }
            .exclusively(before:
                SpatialTapGesture(count: 1)
                    .onEnded { _ in toggleControls() }
            )
    }

    func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                if dragAxis == nil {
                    guard abs(value.translation.height) > abs(value.translation.width) else { return }
                    let axis: DragAxis = value.startLocation.x < width / 2 ? .brightness : .volume
                    dragAxis = axis
                    if axis == .volume {
                        volumeEchoSuppressTask?.cancel()
                        isDraggingVolume = true
                    }
                    dragBaseline = axis == .brightness
                        ? (activeWindowScene?.screen.brightness ?? 0.5)
                        : CGFloat(volumeController?.currentVolume ?? 0.5)
                    lastHapticStep = nil
                    HapticManager.impact(.light)
                }
                guard let dragAxis else { return }
                let delta = -value.translation.height / 250
                let newValue = min(max(dragBaseline + delta, 0), 1)
                dragValue = newValue
                switch dragAxis {
                case .brightness: activeWindowScene?.screen.brightness = newValue
                case .volume: volumeController?.setVolume(Float(newValue))
                }
                // Light tick every 10% crossed, not every pixel of drag.
                let step = Int((newValue * 10).rounded())
                if step != lastHapticStep {
                    lastHapticStep = step
                    HapticManager.impact(.light)
                }
            }
            .onEnded { _ in
                dragAxis = nil
                lastHapticStep = nil
                // The final setVolume call's own echo through the outputVolume observer
                // can still arrive briefly after the finger lifts — keep swallowing it a
                // moment longer so it doesn't reopen the HUD with a stale value right as
                // this gesture's own indicator was fading out. Cancellable so a fresh drag
                // starting within that window (see onChanged above) isn't cut short by this
                // stale reset firing mid-gesture.
                volumeEchoSuppressTask?.cancel()
                volumeEchoSuppressTask = Task {
                    try? await Task.sleep(for: .seconds(0.5))
                    guard !Task.isCancelled else { return }
                    isDraggingVolume = false
                }
            }
    }

    func toggleOrientation() {
        togglePlayerOrientation()
    }

    private func handleDoubleTap(at location: CGPoint, width: CGFloat) {
        let tappedRight = location.x > width / 2
        let forward = tappedRight
        let seconds = forward ? skipForwardSeconds : skipBackwardSeconds
        HapticManager.impact(.medium)
        seek(by: forward ? seconds : -seconds)
        seekFeedback = SeekFeedback(forward: forward, onRight: tappedRight, seconds: seconds)
        Task {
            try? await Task.sleep(for: .seconds(0.6))
            seekFeedback = nil
        }
    }
}
#elseif os(macOS)
extension PlayerView {

    /// Mouse-pointer analog of the iOS tapGesture above: click toggles controls the same as
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
                    .onEnded { _ in toggleControls() }
            )
    }

    private func handleMacDoubleClick(at location: CGPoint, width: CGFloat) {
        let tappedRight = location.x > width / 2
        let forward = tappedRight
        let seconds = forward ? skipForwardSeconds : skipBackwardSeconds
        seek(by: forward ? seconds : -seconds)
        seekFeedback = SeekFeedback(forward: forward, onRight: tappedRight, seconds: seconds)
        Task {
            try? await Task.sleep(for: .seconds(0.6))
            seekFeedback = nil
        }
    }

    /// Hover is the pointer-driven equivalent of a touch tap revealing controls — there's no
    /// "the finger just touched the glass" moment with a mouse, so any mouse movement over
    /// the video surface re-shows the controls and restarts the same auto-hide timer a tap
    /// would.
    func handleMacMouseActivity() {
        if !isControlsVisible {
            withAnimation(DT.Animation.fast) { isControlsVisible = true }
        }
        scheduleAutoHide()
    }

    /// Sets output volume directly through the active engine (setEngineVolume, PlayerView.swift)
    /// rather than through a hidden system slider — macOS has no per-app "hidden MPVolumeView"
    /// trick to reach for the way iOS does.
    func adjustMacVolume(by delta: Double) {
        macVolume = min(max(macVolume + delta, 0), 1)
        setEngineVolume(Float(macVolume))
        macVolumeHUD = macVolume
        macVolumeHUDTask?.cancel()
        macVolumeHUDTask = Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            macVolumeHUD = nil
        }
    }
}
#endif
