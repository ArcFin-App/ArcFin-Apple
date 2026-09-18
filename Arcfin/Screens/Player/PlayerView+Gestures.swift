import SwiftUI
#if !os(tvOS)
import UIKit
#endif

#if !os(tvOS)
extension PlayerView {

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
                        ? UIScreen.main.brightness
                        : CGFloat(volumeController?.currentVolume ?? 0.5)
                }
                guard let dragAxis else { return }
                let delta = -value.translation.height / 250
                let newValue = min(max(dragBaseline + delta, 0), 1)
                switch dragAxis {
                case .brightness: UIScreen.main.brightness = newValue
                case .volume: volumeController?.setVolume(Float(newValue))
                }
            }
            .onEnded { _ in dragAxis = nil }
    }

    private func handleDoubleTap(at location: CGPoint, width: CGFloat) {
        let forward = location.x > width / 2
        seek(by: forward ? 10 : -10)
        seekFeedback = SeekFeedback(forward: forward)
        Task {
            try? await Task.sleep(for: .seconds(0.6))
            seekFeedback = nil
        }
    }
}
#endif
