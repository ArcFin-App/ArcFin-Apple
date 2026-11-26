// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import ImageIO
import JellyfinAPI
import MediaEngine

/// How the visualizer draws the music.
enum MusicVisualizerStyle: String, CaseIterable, Identifiable {
    case bars, wave, mirror, dots

    var id: String { rawValue }

    var label: LocalizedStringResource {
        switch self {
        case .bars: "Bars"
        case .wave: "Wave"
        case .mirror: "Mirrored"
        case .dots: "Dots"
        }
    }
}

/// Where Now Playing shows the visualizer.
enum MusicVisualizerPlacement: String, CaseIterable, Identifiable {
    case cover, bottom

    var id: String { rawValue }

    var label: LocalizedStringResource {
        switch self {
        case .cover: "On the Cover"
        case .bottom: "Bottom of the Player"
        }
    }
}

/// What colours the visualizer takes.
enum MusicVisualizerColor: String, CaseIterable, Identifiable {
    /// One colour from the cover, picked to stand out from it.
    case cover
    /// Several colours from the cover, one after another across the bars.
    case palette
    /// A rainbow running from the low notes to the high ones.
    case spectrum
    case white

    var id: String { rawValue }

    var label: LocalizedStringResource {
        switch self {
        case .cover: "From the Cover"
        case .palette: "Cover Colours"
        case .spectrum: "Spectrum"
        case .white: "White Glass"
        }
    }

    var usesCover: Bool { self == .cover || self == .palette }
}

/// Frosted shapes that follow what's playing, from one side to the other, low notes on the
/// left: along the bottom of a cover, or filling the space given at the foot of the player.
/// When there's no sound here to follow (on a Chromecast, or before the first samples) they
/// fall still. Hidden when the setting or Reduce Motion is off, and where the chosen
/// placement is somewhere else.
struct MusicArtworkVisualizer: View {
    let bars: Int
    var spacing: CGFloat = 2
    let cornerRadius: CGFloat
    var placement = MusicVisualizerPlacement.cover

    @AppStorage(MusicSettings.visualizerKey) private var isOn = true
    @AppStorage(MusicSettings.visualizerStyleKey) private var style = MusicVisualizerStyle.bars
    @AppStorage(MusicSettings.visualizerPlacementKey) private var chosenPlacement = MusicVisualizerPlacement.cover
    @AppStorage(MusicSettings.visualizerColorKey) private var color = MusicVisualizerColor.cover
    @AppStorage("reduceMotion") private var appReduceMotion = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var coverColors: [Color] = []

    private var artworkURL: URL? { AppServices.music.player.current.flatMap { MusicAPI.artworkURL($0, width: 300) } }

    private var fill: MusicVisualizerFill {
        switch color {
        case .white: .white
        case .spectrum: .blend(MusicVisualizerFill.spectrum)
        case .cover: coverColors.first.map { .single($0) } ?? .white
        case .palette:
            coverColors.count > 1 ? .perBar(coverColors) : (coverColors.first.map { .single($0) } ?? .white)
        }
    }

    var body: some View {
        if isOn, !appReduceMotion, !systemReduceMotion, chosenPlacement == placement {
            GeometryReader { geometry in
                MusicGlassBars(bars: bars, spacing: spacing, style: style, fill: fill)
                    .frame(height: placement == .cover ? geometry.size.height * 0.34 : geometry.size.height)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .task(id: color.usesCover ? artworkURL : nil) {
                guard color.usesCover, let url = artworkURL else { return }
                let found = await MusicCoverTint.colors(for: url)
                withAnimation(.easeInOut(duration: 0.6)) { coverColors = found }
            }
        }
    }
}

/// What the frosted layer is washed with.
enum MusicVisualizerFill {
    case white
    case single(Color)
    /// Each bar its own colour, the colours taking turns.
    case perBar([Color])
    /// The colours running into one another from left to right.
    case blend([Color])

    static let spectrum: [Color] = stride(from: 0.0, through: 0.85, by: 0.85 / 6).map {
        Color(hue: $0, saturation: 0.6, brightness: 1)
    }
}

/// A colour for the bars taken from the cover, so they stand out from it: the cover's most
/// vivid colour, made dark where the bottom of the cover is light and light where it's dark.
/// A grey cover gets black or white.
enum MusicCoverTint {
    @MainActor private static var cache: [URL: Color] = [:]
    @MainActor private static var paletteCache: [URL: [Color]] = [:]

    /// The tint first, then up to three more of the cover's colours, made to stand out the
    /// same way. One colour for a cover with no others to speak of.
    @MainActor
    static func colors(for url: URL) async -> [Color] {
        if let cached = paletteCache[url] { return cached }
        guard let data = await URLSession.arcfin.imageData(from: url) else { return [] }
        let colors = await Task.detached(priority: .utility) { colors(from: data) }.value
        if !colors.isEmpty { paletteCache[url] = colors }
        return colors
    }

    nonisolated static func colors(from data: Data) -> [Color] {
        guard let first = tint(from: data) else { return [] }
        guard let (pixels, width, height) = thumbnail(data) else { return [first] }
        let isLightBelow = lightBelow(pixels, width: width, height: height)
        // Vivid pixels into twelve hues, each weighted by how vivid and how much of it there is.
        var buckets = [(weight: Double, r: Double, g: Double, b: Double)](repeating: (0, 0, 0, 0), count: 12)
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = Double(pixels[i]) / 255, g = Double(pixels[i + 1]) / 255, b = Double(pixels[i + 2]) / 255
            let high = max(r, g, b), low = min(r, g, b)
            guard high > 0, (high - low) / high > 0.25, high > 0.2 else { continue }
            let weight = (high - low) / high * high
            let bucket = min(Int(hsb(r, g, b).hue * 12), 11)
            buckets[bucket].weight += weight
            buckets[bucket].r += r * weight
            buckets[bucket].g += g * weight
            buckets[bucket].b += b * weight
        }
        let heaviest = buckets.map(\.weight).max() ?? 0
        guard heaviest > 0 else { return [first] }
        let others = buckets.enumerated()
            .filter { $0.element.weight > heaviest * 0.08 }
            .sorted { $0.element.weight > $1.element.weight }
            .prefix(4)
            .map { _, bucket in
                let hue = hsb(bucket.r / bucket.weight, bucket.g / bucket.weight, bucket.b / bucket.weight)
                return isLightBelow
                    ? Color(hue: hue.hue, saturation: min(hue.saturation * 1.2, 1), brightness: 0.38)
                    : Color(hue: hue.hue, saturation: hue.saturation * 0.55, brightness: 1)
            }
        return Array(([first] + others).prefix(4))
    }

    private nonisolated static func thumbnail(_ data: Data) -> (pixels: [UInt8], width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 32,
              ] as CFDictionary)
        else { return nil }
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return (pixels, width, height)
    }

    /// Whether the bottom third, where the bars stand, is light.
    private nonisolated static func lightBelow(_ pixels: [UInt8], width: Int, height: Int) -> Bool {
        var light = 0.0, count = 0.0
        for y in (height * 2 / 3)..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                light += 0.2126 * Double(pixels[i]) / 255 + 0.7152 * Double(pixels[i + 1]) / 255 + 0.0722 * Double(pixels[i + 2]) / 255
                count += 1
            }
        }
        return count > 0 && light / count > 0.55
    }

    @MainActor
    static func tint(for url: URL) async -> Color? {
        if let cached = cache[url] { return cached }
        guard let data = await URLSession.arcfin.imageData(from: url) else { return nil }
        let color = await Task.detached(priority: .utility) { tint(from: data) }.value
        if let color { cache[url] = color }
        return color
    }

    nonisolated static func tint(from data: Data) -> Color? {
        guard let (pixels, width, height) = thumbnail(data) else { return nil }
        let isLightBelow = lightBelow(pixels, width: width, height: height)
        let vivid = stride(from: 0, to: pixels.count, by: 4).map { i in
            let r = Double(pixels[i]) / 255, g = Double(pixels[i + 1]) / 255, b = Double(pixels[i + 2]) / 255
            let high = max(r, g, b), low = min(r, g, b)
            return (score: (high > 0 ? (high - low) / high : 0) * high, r: r, g: g, b: b)
        }
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

/// The shapes cut out of a frosted layer, so what's behind shows through them blurred, lit
/// from the top.
private struct MusicGlassBars: View {
    let bars: Int
    let spacing: CGFloat
    let style: MusicVisualizerStyle
    let fill: MusicVisualizerFill

    @State private var meter = MusicMeter()
    /// Paused long enough for the bars to have fallen; the timeline stops until it plays.
    @State private var isSettled = false
    private var isPlaying: Bool { AppServices.music.isPlaying }

    var body: some View {
        let isPlaying = isPlaying
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            wash
        }
        .mask {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: isSettled)) { context in
                Canvas { canvas, size in
                    let heights = meter.heights(bars, at: context.date, playing: isPlaying)
                    draw(heights, in: &canvas, size: size)
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

    @ViewBuilder
    private var wash: some View {
        switch fill {
        case .white:
            LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.12)], startPoint: .top, endPoint: .bottom)
        case .single(let tint):
            LinearGradient(colors: [tint.opacity(0.5), tint.opacity(0.2)], startPoint: .top, endPoint: .bottom)
        case .perBar(let colors):
            // A wave has no bars to take turns; its colours run into one another instead.
            across(style == .wave ? Gradient(colors: colors) : Gradient(stops: (0..<bars).flatMap { index in
                let color = colors[index % colors.count]
                return [Gradient.Stop(color: color, location: CGFloat(index) / CGFloat(bars)),
                        Gradient.Stop(color: color, location: CGFloat(index + 1) / CGFloat(bars))]
            }))
        case .blend(let colors):
            across(Gradient(colors: colors))
        }
    }

    /// Colours from left to right, brighter at the top as the others are.
    private func across(_ gradient: Gradient) -> some View {
        LinearGradient(gradient: gradient, startPoint: .leading, endPoint: .trailing)
            .opacity(0.55)
            .mask(LinearGradient(colors: [.black, .black.opacity(0.4)], startPoint: .top, endPoint: .bottom))
    }

    private func draw(_ heights: [Float], in canvas: inout GraphicsContext, size: CGSize) {
        let width = max((size.width - spacing * CGFloat(bars - 1)) / CGFloat(bars), 1)
        let radius = min(width / 2, 4)
        switch style {
        case .bars:
            for (index, height) in heights.enumerated() {
                let barHeight = max(CGFloat(height) * size.height, 3)
                let rect = CGRect(x: CGFloat(index) * (width + spacing), y: size.height - barHeight, width: width, height: barHeight)
                canvas.fill(UnevenRoundedRectangle(topLeadingRadius: radius, topTrailingRadius: radius).path(in: rect), with: .color(.white))
            }
        case .mirror:
            // Out from the middle both ways.
            for (index, height) in heights.enumerated() {
                let barHeight = max(CGFloat(height) * size.height, 3)
                let rect = CGRect(x: CGFloat(index) * (width + spacing), y: (size.height - barHeight) / 2, width: width, height: barHeight)
                canvas.fill(RoundedRectangle(cornerRadius: radius).path(in: rect), with: .color(.white))
            }
        case .dots:
            // Each bar a column of lit squares, as on a level meter.
            let side = width
            let gap = max(spacing, 1)
            let rows = max(Int((size.height + gap) / (side + gap)), 1)
            for (index, height) in heights.enumerated() {
                let lit = max(Int((CGFloat(height) * CGFloat(rows)).rounded()), 1)
                for row in 0..<min(lit, rows) {
                    let rect = CGRect(x: CGFloat(index) * (width + spacing), y: size.height - CGFloat(row + 1) * (side + gap) + gap,
                                      width: side, height: side)
                    canvas.fill(RoundedRectangle(cornerRadius: side * 0.3).path(in: rect), with: .color(.white))
                }
            }
        case .wave:
            // A smooth line through the bars' tops, filled down to the bottom.
            let points = heights.enumerated().map { index, height in
                CGPoint(x: (CGFloat(index) + 0.5) / CGFloat(heights.count) * size.width,
                        y: size.height - max(CGFloat(height) * size.height, 3))
            }
            guard let first = points.first, let last = points.last else { return }
            var path = Path()
            path.move(to: CGPoint(x: 0, y: size.height))
            path.addLine(to: CGPoint(x: 0, y: first.y))
            path.addLine(to: first)
            for (current, next) in zip(points, points.dropFirst()) {
                path.addQuadCurve(to: CGPoint(x: (current.x + next.x) / 2, y: (current.y + next.y) / 2), control: current)
            }
            path.addLine(to: last)
            path.addLine(to: CGPoint(x: size.width, y: last.y))
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.closeSubpath()
            canvas.fill(path, with: .color(.white))
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
        // Only what's heard: buffering, on AirPlay or a Chromecast, nothing comes through to show.
        if playing, let rate = AppServices.music.player.levels.latest(spectrum.size, into: &samples) {
            targets = spectrum.bands(count, of: samples, sampleRate: rate)
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
