// SPDX-License-Identifier: AGPL-3.0-or-later

import AVFoundation
import AVKit
import AuthCore
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import JellyfinAPI
import SwiftUI
import UIKit

/// Sharing a scene: the video itself, trimmed as the person likes, upright or wide, with a small
/// Arcfin logo in its corner unless they (and the server's admin) leave it off.
struct ArcsShareView: View {
    let clip: ArcClip
    let model: ArcsModel

    @Environment(\.dismiss) private var dismiss
    @AppStorage(ArcsSettings.watermarkKey) private var watermarkSetting = true
    @State private var source: URL?
    @State private var failed: String?
    @State private var start: Double = 0
    @State private var end: Double = 1
    @State private var duration: Double = 0
    @State private var watermark = true
    @State private var burnSubtitles = false
    @State private var isExporting = false
    @State private var exported: URL?
    @State private var preview: AVPlayer?
    @State private var shape = ArcsShareShape.portrait
    @State private var format = ArcsShareFormat.video
    @State private var cues: [ArcSubtitleCue] = []
    /// A line from the scene drawn into the picture, or nil.
    @State private var quote: String?
    /// Upright, the scene is framed as the feed shows it.
    @AppStorage(ArcsSettings.framingKey) private var framing = ArcsFraming.fill

    private var policy: ArcsAvailability.Watermark { model.availability?.watermark ?? .optional }
    private var subtitle: ArcSubtitle? { ArcSubtitles.track(for: clip) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    previewView
                        .frame(height: 320)
                        .frame(maxWidth: .infinity)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.black)
                    Picker("Shape", selection: $shape) {
                        ForEach(ArcsShareShape.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                if duration > 0 {
                    Section {
                        LabeledContent("Starts") { Text(time(start * duration)) }
                        Slider(value: $start, in: 0...max(0, end - minimumFraction)) { Text("Starts") }
                            .onChange(of: start) { _, value in seekPreview(value) }
                        LabeledContent("Ends") { Text(time(end * duration)) }
                        Slider(value: $end, in: min(1, start + minimumFraction)...1) { Text("Ends") }
                            .onChange(of: end) { _, value in seekPreview(value) }
                    } header: {
                        Text("Trim")
                    } footer: {
                        Text("\(time((end - start) * duration)) shared.")
                    }
                }
                Section {
                    Picker("Format", selection: $format) {
                        ForEach(ArcsShareFormat.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if !quotes.isEmpty {
                        Picker("Line", selection: $quote) {
                            Text("None").tag(String?.none)
                            ForEach(quotes, id: \.self) { line in Text(verbatim: line).tag(Optional(line)) }
                        }
                    }
                } footer: {
                    if format == .gif {
                        Text("A GIF loops without sound, and is up to six seconds from the start of your trim.")
                    } else if !quotes.isEmpty {
                        Text("Pick a line and it's written across the scene, above the logo.")
                    }
                }
                Section {
                    Toggle("Arcfin Watermark", isOn: $watermark)
                        .disabled(policy != .optional)
                    if subtitle != nil {
                        Toggle("Subtitles in the Video", isOn: $burnSubtitles)
                            .onChange(of: burnSubtitles) { _, _ in Task { await fetch() } }
                    }
                } footer: {
                    switch policy {
                    case .forced: Text("Your server's admin has the watermark always on.")
                    case .off:    Text("Your server's admin has turned the watermark off.")
                    case .optional: Text("A small Arcfin logo in the corner of the video. Turn it off for good in Settings › Arcs.")
                    }
                }
                if let failed {
                    Section { Label { Text(verbatim: failed) } icon: { Image(systemName: "exclamationmark.triangle") } }
                }
            }
            .navigationTitle("Share Scene")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isExporting {
                        ProgressView()
                    } else {
                        Button("Share") { Task { await export() } }
                            .disabled(source == nil)
                    }
                }
            }
            .sheet(item: Binding(get: { exported.map(SharedFile.init) }, set: { if $0 == nil { exported = nil } })) { file in
                ActivitySheet(items: [file.url]) { completed in
                    if completed { model.noteShared(clip) }
                    dismiss()
                }
            }
        }
        .alwaysDark()
        .task {
            watermark = policy == .forced || (policy == .optional && watermarkSetting)
            await fetch()
            if !clip.subtitles.isEmpty, let (credential, header) = model.auth() {
                cues = await ArcSubtitles.load(for: clip, credential: credential, authHeader: header)
            }
        }
        .onDisappear { preview?.pause() }
    }

    private var minimumFraction: Double { duration > 0 ? min(1, 3 / duration) : 0.1 }

    /// The scene's lines inside the trim, each once.
    private var quotes: [String] {
        let from = start * duration, to = end * duration
        var seen = Set<String>()
        return cues.filter { $0.end > from && $0.start < to }.map { $0.text.replacingOccurrences(of: "\n", with: " ") }
            .filter { seen.insert($0).inserted }
    }

    @ViewBuilder
    private var previewView: some View {
        if let preview {
            // As it'll be shared: upright as the feed shows it, or wide as it is.
            ArcsSharePreview(player: preview, framing: shape == .portrait ? framing : .fit)
                .aspectRatio(shape.aspectRatio, contentMode: .fit)
                .overlay(alignment: .bottomTrailing) {
                    if watermark { ArcsWatermarkBadge(height: 22).padding(10).allowsHitTesting(false) }
                }
                .overlay(alignment: .bottom) {
                    if let quote {
                        Text(verbatim: quote)
                            .font(.caption.weight(.heavy))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .shadow(color: .black.opacity(0.85), radius: 3)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
                            .padding(.horizontal, 16)
                            .padding(.bottom, 34)
                            .allowsHitTesting(false)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.vertical, 8)
                .animation(.easeInOut(duration: 0.25), value: shape)
        } else if failed == nil {
            ZStack {
                Color.black
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Preparing the scene…").font(.footnote).foregroundStyle(.secondary)
                }
            }
        } else {
            Color.black
        }
    }

    // MARK: Work

    /// The clip from the plugin, at full quality, with subtitles in the picture if asked.
    private func fetch() async {
        guard let (credential, header) = model.auth(),
              let url = ArcsClient.videoURL(for: clip, seconds: Int(clip.seconds.rounded()), quality: .high, purpose: .share,
                                            subtitle: burnSubtitles ? subtitle?.index : nil, baseURL: credential.baseURL) else { return }
        preview?.pause()
        preview = nil
        source = nil
        failed = nil
        var request = URLRequest(url: url)
        request.setValue(header, forHTTPHeaderField: "Authorization")
        for (name, value) in CustomHTTPHeaders.headers(for: url) { request.setValue(value, forHTTPHeaderField: name) }
        request.timeoutInterval = 120
        do {
            let (file, response) = try await URLSession.arcfin.download(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                failed = status == 403 ? String(localized: "Your server's admin has turned off sharing Arcs.")
                                       : String(localized: "Couldn't get this scene from your server.")
                return
            }
            let local = FileManager.default.temporaryDirectory.appendingPathComponent("arc-\(UUID().uuidString).mp4")
            try FileManager.default.moveItem(at: file, to: local)
            let seconds = try await AVURLAsset(url: local).load(.duration).seconds
            duration = seconds.isFinite ? seconds : clip.seconds
            source = local
            let player = AVPlayer(url: local)
            player.actionAtItemEnd = .none
            player.play()
            preview = player
        } catch {
            failed = String(localized: "Couldn't get this scene from your server.")
        }
    }

    private func seekPreview(_ fraction: Double) {
        preview?.seek(to: CMTime(seconds: fraction * duration, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func export() async {
        guard let source else { return }
        isExporting = true
        defer { isExporting = false }
        preview?.pause()
        do {
            exported = try await ArcsExporter.export(source: source, from: start * duration, to: end * duration, shape: shape,
                                                     framing: framing, watermark: watermark, caption: quote, gif: format == .gif, clip: clip)
        } catch {
            failed = String(localized: "Couldn't make the video to share.")
        }
    }

    private func time(_ seconds: Double) -> String {
        Duration.seconds(max(0, seconds)).formatted(.time(pattern: .minuteSecond))
    }
}

private struct SharedFile: Identifiable {
    let url: URL
    var id: URL { url }
}

/// The shared video's shape: upright for phones and stories, or wide as the film is.
enum ArcsShareShape: String, CaseIterable, Identifiable {
    case portrait, landscape
    var id: String { rawValue }

    var label: LocalizedStringResource {
        switch self {
        case .portrait:  "Portrait"
        case .landscape: "Landscape"
        }
    }

    var aspectRatio: CGFloat { self == .portrait ? 9 / 16 : 16 / 9 }
}

/// The share preview: the same framing the export draws.
private struct ArcsSharePreview: UIViewRepresentable {
    let player: AVPlayer
    let framing: ArcsFraming

    func makeUIView(context: Context) -> ArcVideoUIView {
        ArcVideoUIView(player: player, framing: framing)
    }

    func updateUIView(_ view: ArcVideoUIView, context: Context) {
        view.setFraming(framing)
    }
}

/// Cuts the clip, puts it in the chosen shape and draws the watermark into its picture.
enum ArcsExporter {
    static func export(source: URL, from start: Double, to end: Double, shape: ArcsShareShape, framing: ArcsFraming,
                       watermark: Bool, caption: String? = nil, gif: Bool = false, clip: ArcClip) async throws -> URL {
        let asset = AVURLAsset(url: source)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // A GIF is made from a short video made the same way first.
        let end = gif ? min(end, start + ArcsGIF.maxSeconds) : end
        let output = folder.appendingPathComponent(fileName(clip: clip, from: start, to: end))
        let reshapes = shape == .portrait || watermark || caption != nil
        let preset = reshapes ? AVAssetExportPresetHighestQuality : AVAssetExportPresetPassthrough
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { throw CocoaError(.fileWriteUnknown) }
        let range = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), end: CMTime(seconds: end, preferredTimescale: 600))
        session.timeRange = range
        session.shouldOptimizeForNetworkUse = true
        session.metadata = metadata(clip: clip)
        if reshapes {
            session.videoComposition = try await composition(for: asset, framing: shape == .portrait ? framing : nil, watermark: watermark,
                                                             caption: caption)
        }
        try await session.export(to: output, as: .mp4)
        guard gif else { return output }
        let gifURL = output.deletingPathExtension().appendingPathExtension("gif")
        try await ArcsGIF.make(from: output, to: gifURL)
        try? FileManager.default.removeItem(at: output)
        return gifURL
    }

    /// "Arcfin_Show-Name_S01E05_2m10s-2m40s.mp4": the title, the episode and where in it
    /// the scene is, so it's still clear what it is wherever it ends up.
    static func fileName(clip: ArcClip, from start: Double, to end: Double) -> String {
        var parts = ["Arcfin", slug(clip.seriesName ?? clip.name)]
        if clip.isEpisode, let season = clip.seasonNumber, let episode = clip.episodeNumber {
            parts.append(String(format: "S%02dE%02d", season, episode))
        }
        let offset = Double(clip.startTicks) / 10_000_000
        parts.append("\(stamp(offset + start))-\(stamp(offset + end))")
        return parts.filter { !$0.isEmpty }.joined(separator: "_") + ".mp4"
    }

    /// Letters and digits kept (in any script), everything else one hyphen.
    private static func slug(_ text: String) -> String {
        let words = text.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        return String(words.joined(separator: "-").prefix(60))
    }

    private static func stamp(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let (h, m, s) = (total / 3600, total % 3600 / 60, total % 60)
        return h > 0 ? "\(h)h\(String(format: "%02d", m))m\(String(format: "%02d", s))s" : "\(m)m\(String(format: "%02d", s))s"
    }

    /// What the file says about itself: the scene, and that it came from Arcfin. Nothing about the
    /// person sharing it or their server.
    private static func metadata(clip: ArcClip) -> [AVMetadataItem] {
        let title = ([clip.seriesName ?? clip.name] + [ArcText.sceneLine(clip)].compactMap { $0 }).joined(separator: " · ")
        let about = "Shared from Arcfin, the Jellyfin app for iPhone, iPad, Mac and Apple TV. https://arcfin.psmattas.com"
        func item(_ identifier: AVMetadataIdentifier, _ value: String) -> AVMetadataItem {
            let item = AVMutableMetadataItem()
            item.identifier = identifier
            item.value = value as NSString
            item.extendedLanguageTag = "und"
            return item
        }
        return [
            item(.commonIdentifierTitle, title),
            item(.commonIdentifierSoftware, "Arcfin"),
            item(.commonIdentifierCreator, "Arcfin"),
            item(.commonIdentifierDescription, about),
            item(.iTunesMetadataUserComment, about),
        ]
    }

    /// `framing` nil: wide, as the source is.
    private static func composition(for asset: AVAsset, framing: ArcsFraming?, watermark: Bool, caption: String?) async throws -> AVVideoComposition {
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw CocoaError(.fileReadCorruptFile) }
        let natural = try await track.load(.naturalSize)
        let duration = try await asset.load(.duration)
        // Upright: as wide as the source is tall, so a 720p scene becomes 720 × 1280.
        let size = framing != nil
            ? CGSize(width: even(min(natural.width, natural.height)), height: even(min(natural.width, natural.height) * 16 / 9))
            : CGSize(width: even(natural.width), height: even(natural.height))
        let markSide = (min(size.width, size.height) * 0.09).rounded()
        let mark = watermark ? await MainActor.run { ArcsWatermarkBadge.image(side: markSide) } : nil
        var line: UIImage?
        if let caption {
            line = await MainActor.run { ArcsCaption.image(text: caption, width: size.width * 0.86, scale: min(size.width, size.height) / 720) }
        }
        var configuration = try await AVVideoComposition.Configuration(for: asset)
        configuration.renderSize = size
        configuration.customVideoCompositorClass = ArcsCompositor.self
        configuration.instructions = [ArcsInstruction(timeRange: CMTimeRange(start: .zero, duration: duration), trackID: track.trackID,
                                                      framing: framing, watermark: mark?.cgImage, caption: line?.cgImage)]
        return AVVideoComposition(configuration: configuration)
    }

    private static func even(_ value: CGFloat) -> CGFloat { (value / 2).rounded() * 2 }
}

/// What the compositor draws for the whole clip.
final class ArcsInstruction: NSObject, AVVideoCompositionInstructionProtocol, @unchecked Sendable {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID = kCMPersistentTrackID_Invalid
    let trackID: CMPersistentTrackID
    /// Upright, framed as the feed is; nil keeps the source's shape.
    let framing: ArcsFraming?
    let watermark: CGImage?
    let caption: CGImage?

    init(timeRange: CMTimeRange, trackID: CMPersistentTrackID, framing: ArcsFraming?, watermark: CGImage?, caption: CGImage? = nil) {
        self.timeRange = timeRange
        self.trackID = trackID
        self.framing = framing
        self.watermark = watermark
        self.caption = caption
        requiredSourceTrackIDs = [NSNumber(value: trackID)]
    }
}

/// Draws each frame: upright, as the feed frames it (filling the screen, the whole picture over a
/// blurred copy, or the whole picture on black); wide, as it is. Then the logo in the bottom-right corner.
final class ArcsCompositor: NSObject, AVVideoCompositing, @unchecked Sendable {
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var renderContext: AVVideoCompositionRenderContext?

    var sourcePixelBufferAttributes: [String: any Sendable]? {
        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    }

    var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] {
        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    }

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        renderContext = newRenderContext
    }

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let instruction = request.videoCompositionInstruction as? ArcsInstruction,
              let frame = request.sourceFrame(byTrackID: instruction.trackID),
              let output = request.renderContext.newPixelBuffer() else {
            request.finish(with: CocoaError(.fileReadCorruptFile))
            return
        }
        let size = request.renderContext.size
        let canvas = CGRect(origin: .zero, size: size)
        let source = CIImage(cvPixelBuffer: frame)
        let fill = max(size.width / source.extent.width, size.height / source.extent.height)
        let fit = min(size.width / source.extent.width, size.height / source.extent.height)
        func placed(_ scale: CGFloat) -> CIImage {
            source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                .transformed(by: CGAffineTransform(translationX: (size.width - source.extent.width * scale) / 2,
                                                   y: (size.height - source.extent.height * scale) / 2))
        }
        let black = CIImage(color: .black).cropped(to: canvas)
        var image: CIImage
        switch instruction.framing {
        case .fill:
            image = placed(fill)
        case .blur:
            let background = placed(fill).clampedToExtent().applyingGaussianBlur(sigma: 28)
                .applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: -0.12])
            image = placed(fit).composited(over: background)
        case .fit, nil:
            image = placed(fit).composited(over: black)
        }
        if let caption = instruction.caption {
            let line = CIImage(cgImage: caption)
            // Centred, in the lower part of the picture, clear of the logo's corner.
            let y = (min(size.width, size.height) * 0.035).rounded() + size.height * 0.07
            image = line.transformed(by: CGAffineTransform(translationX: (size.width - line.extent.width) / 2, y: y)).composited(over: image)
        }
        if let watermark = instruction.watermark {
            let mark = CIImage(cgImage: watermark)
            let margin = (min(size.width, size.height) * 0.035).rounded()
            // Core Image counts up from the bottom-left.
            image = mark.transformed(by: CGAffineTransform(translationX: size.width - mark.extent.width - margin, y: margin))
                .composited(over: image)
        }
        context.render(image.cropped(to: canvas), to: output, bounds: canvas, colorSpace: CGColorSpace(name: CGColorSpace.itur_709))
        request.finish(withComposedVideoFrame: output)
    }
}

/// The mark: Arcfin's icon, rounded, nothing else.
struct ArcsWatermarkBadge: View {
    var height: CGFloat = 22

    var body: some View {
        Image("ArcfinLogo")
            .resizable()
            .scaledToFill()
            .frame(width: height, height: height)
            .clipShape(RoundedRectangle(cornerRadius: height * 0.24, style: .continuous))
            .opacity(0.9)
            .shadow(color: .black.opacity(0.4), radius: height * 0.15)
            .accessibilityHidden(true)
    }

    /// The logo drawn `side` pixels square, for the exported video.
    @MainActor static func image(side: CGFloat) -> UIImage? {
        let renderer = ImageRenderer(content: ArcsWatermarkBadge(height: side).padding(side * 0.2))
        renderer.scale = 1
        return renderer.uiImage
    }
}

/// The system share sheet for files.
struct ActivitySheet: UIViewControllerRepresentable {
    let items: [Any]
    let completion: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, _ in completion(completed) }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

enum ArcsShareFormat: String, CaseIterable, Identifiable {
    case video, gif
    var id: String { rawValue }

    var label: LocalizedStringResource {
        switch self {
        case .video: "Video"
        case .gif:   "GIF"
        }
    }
}

/// A line from the scene, as a caption drawn into the shared video.
enum ArcsCaption {
    @MainActor static func image(text: String, width: CGFloat, scale: CGFloat) -> UIImage? {
        let caption = Text(verbatim: text)
            .font(.system(size: 30 * max(scale, 0.5), weight: .heavy))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .shadow(color: .black.opacity(0.85), radius: 4)
            .padding(.horizontal, 14 * scale)
            .padding(.vertical, 8 * scale)
            .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 12 * scale))
            .frame(maxWidth: width)
            .fixedSize(horizontal: false, vertical: true)
        let renderer = ImageRenderer(content: caption)
        renderer.proposedSize = ProposedViewSize(width: width, height: nil)
        renderer.scale = 1
        return renderer.uiImage
    }
}

/// A short looping GIF from a shared video: small and silent, for chats that play GIFs inline.
enum ArcsGIF {
    static let maxSeconds = 6.0
    private static let framesPerSecond = 12.0
    private static let width: CGFloat = 480

    static func make(from video: URL, to output: URL) async throws {
        let asset = AVURLAsset(url: video)
        let duration = try await asset.load(.duration).seconds
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: width, height: width * 2)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let count = max(1, Int(min(duration, maxSeconds) * framesPerSecond))
        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.gif.identifier as CFString, count, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFLoopCount as String: 0]] as CFDictionary)
        let frame = [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFDelayTime as String: 1 / framesPerSecond]] as CFDictionary
        for index in 0..<count {
            let time = CMTime(seconds: Double(index) / framesPerSecond, preferredTimescale: 600)
            let (image, _) = try await generator.image(at: time)
            CGImageDestinationAddImage(destination, image, frame)
        }
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }
}
