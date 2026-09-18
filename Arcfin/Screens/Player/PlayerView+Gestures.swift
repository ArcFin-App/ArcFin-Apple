import SwiftUI
#if canImport(UIKit) && !os(tvOS)
import UIKit
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
                    dragBaseline = axis == .brightness
                        ? (activeWindowScene?.screen.brightness ?? UIScreen.main.brightness)
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
            }
    }

    func toggleOrientation() {
        togglePlayerOrientation()
    }

    private func handleDoubleTap(at location: CGPoint, width: CGFloat) {
        let forward = location.x > width / 2
        HapticManager.impact(.medium)
        seek(by: forward ? 10 : -10)
        seekFeedback = SeekFeedback(forward: forward)
        Task {
            try? await Task.sleep(for: .seconds(0.6))
            seekFeedback = nil
        }
    }
}
#endif
