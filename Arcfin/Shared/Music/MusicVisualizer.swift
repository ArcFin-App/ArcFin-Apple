// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import ImageIO
import JellyfinAPI
import MediaEngine

/// Frosted bars that follow what's playing, standing on the bottom edge of a cover from one
/// side to the other, low notes on the left. When there's no sound here to follow (on a
/// Chromecast, or before the first samples) they sway instead. Hidden when the setting or
/// Reduce Motion is off.
struct MusicArtworkVisualizer: View {
    let bars: Int
    var spacing: CGFloat = 2
    let cornerRadius: CGFloat

    @AppStorage(MusicSettings.visualizerKey) private var isOn = true
    @AppStorage(MusicSettings.visualizerTintKey) private var tintsToCover = true
    @AppStorage("reduceMotion") private var appReduceMotion = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var tint: Color?

    private var artworkURL: URL? { AppServices.music.player.current.flatMap { MusicAPI.artworkURL($0, width: 300) } }

    var body: some View {
        if isOn, !appReduceMotion, !systemReduceMotion {
            GeometryReader { geometry in
                MusicGlassBars(bars: bars, spacing: spacing, tint: tintsToCover ? tint : nil)
                    .frame(height: geometry.size.height * 0.34)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .task(id: tintsToCover ? artworkURL : nil) {
                guard tintsToCover, let url = artworkURL else { return }
                let found = await MusicCoverTint.tint(for: url)
                withAnimation(.easeInOut(duration: 0.6)) { tint = found }
            }
        }
    }
}

/// A colour for the bars taken from the cover, so they stand out from it: the cover's most
/// vivid colour, made dark where the bottom of the cover is light and light where it's dark.
/// A grey cover gets black or white.
enum MusicCoverTint {
    @MainActor private static var cache: [URL: Color] = [:]

    @MainActor
    static func tint(for url: URL) async -> Color? {
        if let cached = cache[url] { return cached }
        guard let data = await URLSession.arcfin.imageData(from: url) else { return nil }
        let color = await Task.detached(priority: .utility) { tint(from: data) }.value
        if let color { cache[url] = color }
        return color
    }

    nonisolated static func tint(from data: Data) -> Color? {
        let side = 32
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: side,
              ] as CFDictionary)
        else { return nil }
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Rows are top first; the bars cover the bottom third.
        var bottomLight = 0.0, bottomCount = 0.0
        var vivid: [(score: Double, r: Double, g: Double, b: Double)] = []
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let r = Double(pixels[i]) / 255, g = Double(pixels[i + 1]) / 255, b = Double(pixels[i + 2]) / 255
                let high = max(r, g, b), low = min(r, g, b)
                let saturation = high > 0 ? (high - low) / high : 0
                vivid.append((saturation * high, r, g, b))
                if y >= height * 2 / 3 {
                    bottomLight += 0.2126 * r + 0.7152 * g + 0.0722 * b
                    bottomCount += 1
                }
            }
        }
        let isLightBelow = bottomCount > 0 && bottomLight / bottomCount > 0.55
        let top = vivid.sorted { $0.score > $1.score }.prefix(max(vivid.count / 10, 1))
        let count = Double(top.count)
        let (r, g, b) = (top.map(\.r).reduce(0, +) / count, top.map(\.g).reduce(0, +) / count, top.map(\.b).reduce(0, +) / count)
        let hue = hsb(r, g, b)
        guard hue.saturation > 0.2 else { return isLightBelow ? Color(white: 0.12) : .white }
        return isLightBelow
            ? Color(hue: hue.hue, saturation: min(hue.saturation * 1.2, 1), brightness: 0.38)
            : Color(hue: hue.hue, saturation: hue.saturation * 0.55, brightness: 1)
    }

    private nonisolated static func hsb(_ r: Double, _ g: Double, _ b: Double) -> (hue: Double, saturation: Double) {
        let high = max(r, g, b), low = min(r, g, b), delta = high - low
        guard delta > 0 else { return (0, 0) }
        var hue: Double
        if high == r { hue = (g - b) / delta } else if high == g { hue = (b - r) / delta + 2 } else { hue = (r - g) / delta + 4 }
        hue /= 6
        if hue < 0 { hue += 1 }
        return (hue, delta / high)
    }
}

/// The bars cut out of a frosted layer, so the cover shows through them blurred, lit from the top.
private struct MusicGlassBars: View {
    let bars: Int
    let spacing: CGFloat
    /// From the cover; nil keeps the plain white glass.
    let tint: Color?

    @State private var meter = MusicMeter()
    /// Paused long enough for the bars to have fallen; the timeline stops until it plays.
    @State private var isSettled = false
    private var isPlaying: Bool { AppServices.music.isPlaying }

    var body: some View {
        let isPlaying = isPlaying
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            if let tint {
                LinearGradient(colors: [tint.opacity(0.9), tint.opacity(0.6)], startPoint: .top, endPoint: .bottom)
            } else {
                LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.12)], startPoint: .top, endPoint: .bottom)
            }
        }
        .mask {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: isSettled)) { context in
                Canvas { canvas, size in
                    let heights = meter.heights(bars, at: context.date, playing: isPlaying)
                    let width = max((size.width - spacing * CGFloat(bars - 1)) / CGFloat(bars), 1)
                    let radius = min(width / 2, 4)
                    for (index, height) in heights.enumerated() {
                        let barHeight = max(CGFloat(height) * size.height, 3)
                        let rect = CGRect(x: CGFloat(index) * (width + spacing), y: size.height - barHeight,
                                          width: width, height: barHeight)
                        let shape = UnevenRoundedRectangle(topLeadingRadius: radius, topTrailingRadius: radius)
                        canvas.fill(shape.path(in: rect), with: .color(.white))
                    }
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
