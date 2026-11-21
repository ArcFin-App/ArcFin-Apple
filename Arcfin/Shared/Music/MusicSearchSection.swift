// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

/// Music in Browse search, below the library's results: artists, albums, then songs.
struct MusicSearchSection: View {
    let results: MusicSearchResults
    var appleMusic: [AppleMusicCatalog.Song] = []

    var body: some View {
        VStack(alignment: .leading, spacing: DT.Spacing.xl) {
            if !results.artists.isEmpty {
                shelf(String(localized: "Artists"), count: results.artists.count) {
                    ForEach(results.artists) { artist in
                        NavigationLink { MusicDestination(route: MusicRoute.artist(artist, libraryID: nil)) } label: {
                            VStack(spacing: DT.Spacing.xs) {
                                MusicArtwork(url: MusicAPI.artworkURL(artist, width: 240), isCircle: true)
                                    .frame(width: 100, height: 100)
                                Text(verbatim: artist.name)
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(DT.Color.textPrimary)
                                    .lineLimit(1)
                            }
                            .frame(width: 100)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !results.albums.isEmpty {
                shelf(String(localized: "Albums"), count: results.albums.count) {
                    ForEach(results.albums) { album in
                        MusicAlbumCard(album: album).frame(width: 140)
                    }
                }
            }
            if !results.songs.isEmpty {
                VStack(alignment: .leading, spacing: DT.Spacing.sm) {
                    SearchSectionHeader(title: String(localized: "Songs"), count: results.songs.count)
                        .padding(.horizontal, DT.Spacing.pagePad)
                    VStack(spacing: 0) {
                        ForEach(Array(results.songs.prefix(8).enumerated()), id: \.element.id) { index, song in
                            MusicSongRow(song: song) { MusicActions.play(results.songs, from: index) }
                                .padding(.vertical, 6)
                        }
                    }
                    .padding(.horizontal, DT.Spacing.pagePad)
                }
            }
            if !appleMusic.isEmpty {
                VStack(alignment: .leading, spacing: DT.Spacing.sm) {
                    SearchSectionHeader(title: String(localized: "From Apple Music"), count: appleMusic.count)
                        .padding(.horizontal, DT.Spacing.pagePad)
                    VStack(spacing: 0) {
                        ForEach(appleMusic) { song in
                            Button { Task { await AppleMusicCatalog.shared.play(song) } } label: {
                                HStack(spacing: DT.Spacing.sm) {
                                    MusicArtwork(url: song.artworkURL, cornerRadius: DT.Radius.xs)
                                        .frame(width: 44, height: 44)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(verbatim: song.title).foregroundStyle(DT.Color.textPrimary)
                                        Text(verbatim: song.artist).font(.footnote).foregroundStyle(DT.Color.textSecondary)
                                    }
                                    .lineLimit(1)
                                    Spacer()
                                    Image(systemName: "applelogo").foregroundStyle(DT.Color.textSecondary)
                                        .accessibilityLabel("Apple Music")
                                }
                                .padding(.vertical, 6)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, DT.Spacing.pagePad)
                }
            }
        }
    }

    private func shelf<Content: View>(_ title: String, count: Int, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DT.Spacing.sm) {
            SearchSectionHeader(title: title, count: count)
                .padding(.horizontal, DT.Spacing.pagePad)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: DT.Spacing.md) { content() }
                    .padding(.horizontal, DT.Spacing.pagePad)
            }
        }
    }
}
