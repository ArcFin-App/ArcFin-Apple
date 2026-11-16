// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import MediaEngine

/// Bars along the bottom of a cover, over a fade so they read on any artwork.
struct MusicArtworkVisualizer: View {
    let bars: Int
    var spacing: CGFloat = 2
    /// How far the bars sit from the cover's sides and bottom.
    var inset: CGFloat = 4
    let cornerRadius: CGFloat

    var body: some View {
        GeometryReader { geometry in
            MusicVisualizer(bars: bars, spacing: spacing, color: .white.opacity(0.9), shadeInset: inset)
                .frame(height: geometry.size.height * 0.32)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .allowsHitTesting(false)
    }
}

/// Bars that follow what's playing, low notes on the left. When there's no sound here to
/// follow (on a Chromecast, or before the first samples) they sway instead. Hidden when the
/// setting or Reduce Motion is off.
struct MusicVisualizer: View {
    let bars: Int
    var spacing: CGFloat = 2
    var color: Color = DT.Color.accent
    /// Set, the bars sit this far inside a dark fade, for drawing them over artwork.
    var shadeInset: CGFloat?

    @AppStorage(MusicPlayback.visualizerKey) private var isOn = true
    @AppStorage("reduceMotion") private var appReduceMotion = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    var body: some View {
        if isOn, !appReduceMotion, !systemReduceMotion {
            MusicVisualizerBars(bars: bars, spacing: spacing, color: color)
                .padding(shadeInset ?? 0)
                .background {
                    if shadeInset != nil {
                        LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                    }
                }
                .accessibilityHidden(true)
        }
    }
}

private struct MusicVisualizerBars: View {
    let bars: Int
    let spacing: CGFloat
    let color: Color

    @State private var meter = MusicMeter()
    /// Paused long enough for the bars to have fallen; the timeline stops until it plays.
    @State private var isSettled = false
    private var isPlaying: Bool { AppServices.music.isPlaying }

    var body: some View {
        let isPlaying = isPlaying
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: isSettled)) { context in
            Canvas { canvas, size in
                let heights = meter.heights(bars, at: context.date, playing: isPlaying)
                let width = max((size.width - spacing * CGFloat(bars - 1)) / CGFloat(bars), 1)
                for (index, height) in heights.enumerated() {
                    let barHeight = max(CGFloat(height) * size.height, min(width, size.height))
                    let rect = CGRect(x: CGFloat(index) * (width + spacing), y: size.height - barHeight,
                                      width: width, height: barHeight)
                    canvas.fill(Path(roundedRect: rect, cornerRadius: width / 2), with: .color(color))
                }
            }
        }
        .task(id: isPlaying) {
            guard !isPlaying else {
                isSettled = false
                return
            }
            guard (try? await Task.sleep(for: .seconds(0.8))) != nil else { return }
            isSettled = true
        }
    }
}

/// Bar heights over time: the player's spectrum, risen to quickly and fallen from slowly.
@MainActor
private final class MusicMeter {
    private let spectrum = MusicSpectrum()
    private var samples: [Float] = []
    private var heights: [Float] = []
    private var last: Date?

    func heights(_ count: Int, at date: Date, playing: Bool) -> [Float] {
        if heights.count != count { heights = [Float](repeating: 0, count: count) }
        let elapsed = Float(min(max(date.timeIntervalSince(last ?? date), 0), 0.1))
        last = date
        let targets: [Float]
        if playing, let rate = AppServices.music.player.levels.latest(spectrum.size, into: &samples) {
            targets = spectrum.bands(count, of: samples, sampleRate: rate)
        } else if playing {
            let time = date.timeIntervalSinceReferenceDate
            targets = (0..<count).map { index in
                let phase = Double(index)
                return Float(0.35 + 0.25 * sin(time * 3 + phase * 0.9) * sin(time * 1.7 + phase * 0.4))
            }
        } else {
            targets = [Float](repeating: 0, count: count)
        }
        for index in heights.indices {
            let rate: Float = targets[index] > heights[index] ? 30 : 7
            heights[index] += (targets[index] - heights[index]) * min(1, elapsed * rate)
        }
        return heights
    }
}
