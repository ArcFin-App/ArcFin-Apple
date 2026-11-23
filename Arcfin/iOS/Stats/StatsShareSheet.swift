// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import ImageIO
import JellyfinAPI

/// A picture of the period's stats to post: rendered here, shared as an image.
struct StatsShareSheet: View {
    let content: StatsShareContent
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
                            .accessibilityLabel("Your stats card for \(content.periodName)")
                    } else {
                        ProgressView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let rendered {
                    let image = Image(decorative: rendered, scale: 1)
                    ShareLink(item: image, preview: SharePreview(content.period == .allTime ? String(localized: "My Stats on Arcfin") : String(localized: "My \(content.periodName) on Arcfin"), image: image)) {
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task(id: format) {
            if artwork == nil { artwork = await loadArtwork() }
            render()
        }
    }

    private func render() {
        let card = StatsShareCard(content: content, name: name, format: format, artwork: artwork ?? .init())
        let renderer = ImageRenderer(content: card.environment(\.colorScheme, .dark))
        renderer.scale = 3
        rendered = renderer.cgImage
    }

    /// ImageRenderer draws only what's already in memory, so the artwork is fetched first.
    private func loadArtwork() async -> StatsShareCard.Artwork {
        let urls: (backdrop: URL?, first: URL?, second: URL?) = switch content {
        case .video(let stats): (
            (stats.topShows.first?.item ?? stats.topMovies.first?.item).flatMap { mediaRepo.imageURL(for: $0, type: .backdrop, fillWidth: 1200) },
            stats.topShows.first.flatMap { mediaRepo.imageURL(for: $0.item, fillWidth: 400) },
            stats.topMovies.first.flatMap { mediaRepo.imageURL(for: $0.item, fillWidth: 400) })
        case .music(let stats): (
            cover(stats.topAlbums.first ?? stats.topSongs.first, width: 1200),
            cover(stats.topSongs.first, width: 400),
            cover(stats.topArtists.first, width: 400))
        }
        async let backdrop = image(urls.backdrop)
        async let first = image(urls.first)
        async let second = image(urls.second)
        return await .init(backdrop: backdrop, first: first, second: second)
    }

    private func cover(_ entry: MusicStats.Entry?, width: Int) -> URL? {
        guard let entry, let albumId = entry.albumId else { return nil }
        return mediaRepo.primaryImageURL(itemID: albumId, tag: entry.albumImageTag, fillWidth: width)
    }

    private func image(_ url: URL?) async -> CGImage? {
        guard let url, let data = await URLSession.arcfin.imageData(from: url),
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
