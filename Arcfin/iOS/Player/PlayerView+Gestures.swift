// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import MediaEngine
import UIKit

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
                    .onEnded { _ in if !model.justEndedSpeedBoost { model.toggleControls() } }
            )
    }

    /// Touch and hold to play faster (Settings › Playback › Hold Speed), back to the set
    /// speed on letting go.
    var holdForSpeedGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.45, maximumDistance: 12)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                if case .second = value { model.beginSpeedBoost() }
            }
            .onEnded { _ in model.endSpeedBoost() }
    }

    /// How far from the top and bottom a swipe has to start to count, with Ignore Swipes Near
    /// Edges on: room for Control Center, Notification Center and the Home gesture.
    static let edgeSwipeMargin: CGFloat = 48

    func dragGesture(size: CGSize) -> some Gesture {
        let width = size.width
        return DragGesture(minimumDistance: 12)
            .onChanged { value in
                if dragAxis == nil {
                    guard swipeGesturesEnabled, !model.isSpeedBoosting else { return }
                    if ignoreEdgeSwipes,
                       value.startLocation.y < Self.edgeSwipeMargin || value.startLocation.y > size.height - Self.edgeSwipeMargin {
                        return
                    }
                    if abs(value.translation.width) > abs(value.translation.height) {
                        beginSwipeSeek()
                        return
                    }
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
                if dragAxis == .seek {
                    // A swipe across the whole screen moves 90 seconds.
                    let delta = Double(value.translation.width / width) * 90 * 10_000_000
                    model.scrubTicks = min(max(Double(dragBaseline) + delta, 0), Double(model.player.durationTicks))
                    model.updateScrubThumbnail()
                    return
                }
                let delta = -value.translation.height / 250
                let newValue = min(max(dragBaseline + delta, 0), 1)
                dragValue = newValue
                switch dragAxis {
                case .brightness: activeWindowScene?.screen.brightness = newValue
                case .volume: volumeController?.setVolume(Float(newValue))
                case .seek: break
                }
                // Light tick every 10% crossed, not every pixel of drag.
                let step = Int((newValue * 10).rounded())
                if step != lastHapticStep {
                    lastHapticStep = step
                    HapticManager.impact(.light)
                }
            }
            .onEnded { _ in
                if dragAxis == .seek {
                    dragAxis = nil
                    HapticManager.impact(.light)
                    model.performSeek(to: Int64(model.scrubTicks))
                    model.isScrubbing = false
                    model.scrubThumbnail = nil
                    model.scheduleAutoHide()
                    return
                }
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

    /// Sideways swipes scrub, with the controls up so the scrubber and its preview show where
    /// the swipe will land.
    private func beginSwipeSeek() {
        guard model.player.durationTicks > 0, !model.isLive else { return }
        dragAxis = .seek
        dragBaseline = CGFloat(model.pendingSeekTargetTicks ?? model.player.positionTicks)
        model.scrubTicks = Double(dragBaseline)
        model.isScrubbing = true
        model.hideControlsTask?.cancel()
        withAnimation(DT.Animation.fast) { model.isControlsVisible = true }
        HapticManager.impact(.light)
    }

    func toggleOrientation() {
        togglePlayerOrientation()
    }

    private func handleDoubleTap(at location: CGPoint, width: CGFloat) {
        guard doubleTapToSkip, !model.isLive else { model.toggleControls(); return }
        let tappedRight = location.x > width / 2
        let forward = tappedRight
        let seconds = forward ? skipForwardSeconds : skipBackwardSeconds
        HapticManager.impact(.medium)
        model.seek(by: forward ? seconds : -seconds)
        model.seekFeedback = SeekFeedback(forward: forward, onRight: tappedRight, seconds: seconds)
        Task {
            try? await Task.sleep(for: .seconds(0.6))
            model.seekFeedback = nil
        }
    }
}
