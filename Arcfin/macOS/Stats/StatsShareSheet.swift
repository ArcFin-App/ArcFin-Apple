// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import ImageIO
import JellyfinAPI

/// A picture of the period's stats to post: rendered here, shared as an image.
struct StatsShareSheet: View {
    let stats: WatchStats
    let name: String?

    @Environment(MediaRepository.self) private var mediaRepo
    @Environment(\.dismiss) private var dismiss
    @State private var format = StatsShareCard.Format.story
    @State private var artwork: StatsShareCard.Artwork?
    @State private var rendered: CGImage?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Picker("Size", selection: $format) {
                    ForEach(StatsShareCard.Format.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                Group {
                    if let rendered {
                        Image(decorative: rendered, scale: 1)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.lg, style: .continuous))
                            .shadow(color: .black.opacity(0.35), radius: 20, y: 10)
                            .accessibilityLabel("Your stats card for \(stats.name)")
                    } else {
                        ProgressView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let rendered {
                    let image = Image(decorative: rendered, scale: 1)
                    ShareLink(item: image, preview: SharePreview("My \(stats.period == .allTime ? "Stats" : stats.name) on Arcfin", image: image)) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.system(.headline))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(DT.Color.accent)
                    .foregroundStyle(DT.Color.onAccent)
                }
            }
            .padding(DT.Spacing.pagePad)
            .screenBackground()
            .navigationTitle("Share Your Stats")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 460, minHeight: 720)
        .task(id: format) {
            if artwork == nil { artwork = await loadArtwork() }
            render()
        }
    }

    private func render() {
        let card = StatsShareCard(stats: stats, name: name, format: format, artwork: artwork ?? .init())
        let renderer = ImageRenderer(content: card.environment(\.colorScheme, .dark))
        renderer.scale = 3
        rendered = renderer.cgImage
    }

    /// ImageRenderer draws only what's already in memory, so the artwork is fetched first.
    private func loadArtwork() async -> StatsShareCard.Artwork {
        let backdropItem = stats.topShows.first?.item ?? stats.topMovies.first?.item
        let backdropURL = backdropItem.flatMap { mediaRepo.imageURL(for: $0, type: .backdrop, fillWidth: 1200) }
        let showURL = stats.topShows.first.flatMap { mediaRepo.imageURL(for: $0.item, fillWidth: 400) }
        let movieURL = stats.topMovies.first.flatMap { mediaRepo.imageURL(for: $0.item, fillWidth: 400) }
        async let backdrop = image(backdropURL)
        async let show = image(showURL)
        async let movie = image(movieURL)
        return await .init(backdrop: backdrop, topShow: show, topMovie: movie)
    }

    private func image(_ url: URL?) async -> CGImage? {
        guard let url, let data = await URLSession.arcfin.imageData(from: url),
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
