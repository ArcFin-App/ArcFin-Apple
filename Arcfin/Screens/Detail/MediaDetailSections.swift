// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI
import SeerrAPI

// The title page's sections below the hero, each its own view.

struct DetailSectionTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(.callout, design: .default, weight: .bold))
            .foregroundStyle(DT.Color.textPrimary)
            .tracking(-0.3)
    }
}

struct DetailGenreChips: View {
    let genres: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(genres, id: \.self) { genre in
                    Text(genre)
                        .font(.system(.caption2, design: .default, weight: .medium))
                        .foregroundStyle(DT.Color.textSecondary)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(DT.Color.textPrimary.opacity(0.05))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(DT.Color.textPrimary.opacity(0.08), lineWidth: 1))
                }
            }
            .padding(.horizontal, DT.Spacing.pagePad)
        }
        .shelfScrollButtons()
        .padding(.bottom, DT.Spacing.md)
#if os(tvOS)
        .focusSection()
#endif
    }
}

struct DetailOverviewSection: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DetailSectionTitle(title: "Overview")
            Text(text)
                .font(.system(.footnote, design: .default))
                .foregroundStyle(DT.Color.textSecondary)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                // Lines across a whole iPad are too long to read comfortably.
                .frame(maxWidth: 720, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.bottom, DT.Spacing.md)
    }
}

struct DetailCastSection: View {
    @Environment(MediaRepository.self) private var mediaRepo
    let cast: [MediaPerson]
    let onSelect: (MediaPerson) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DetailSectionTitle(title: "Cast").padding(.horizontal, DT.Spacing.pagePad)
            ScrollView(.horizontal, showsIndicators: false) {
                // Lazy: a plain HStack fired every cast member's AsyncImage request the
                // instant this section appeared — a large cast (20+ for some titles) could
                // saturate AsyncImage's shared URLSession all at once and fail the whole
                // burst together under any network degradation. See ShelfRow.swift for the
                // same fix applied to Home's shelves.
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(cast) { person in
                        Button { onSelect(person) } label: {
                            CastPersonCard(
                                imageURL: person.primaryImageTag.flatMap {
                                    mediaRepo.personImageURL(personId: person.id, tag: $0, fillWidth: 120)
                                },
                                name: person.name,
                                role: person.role,
                                placeholder: { DetailPersonPlaceholder() }
                            )
                        }
#if os(tvOS)
                        .buttonStyle(TVCardButtonStyle())
                        .focusEffectDisabled()
#else
                        .buttonStyle(.plain)
#endif
                    }
                }
                .padding(.horizontal, DT.Spacing.pagePad)
            }
            .shelfScrollButtons()
        }
        .padding(.bottom, DT.Spacing.md)
#if os(tvOS)
        .focusSection()
#endif
    }
}

private struct DetailPersonPlaceholder: View {
    var body: some View {
        Circle()
            .fill(DT.Color.backgroundSecondary)
            .overlay(Image(systemName: "person.fill")
                .font(.system(.title2))
                .foregroundStyle(DT.Color.textSecondary.opacity(0.4)))
    }
}

struct DetailCrewSection: View {
    let directors: [MediaPerson]
    let writers: [MediaPerson]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !directors.isEmpty {
                DetailCrewRow(label: "Director", people: directors)
            }
            if !writers.isEmpty {
                DetailCrewRow(label: "Writer", people: Array(writers.prefix(3)))
            }
        }
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.bottom, DT.Spacing.md)
    }
}

private struct DetailCrewRow: View {
    let label: String
    let people: [MediaPerson]

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(.caption2, design: .default, weight: .bold))
                .foregroundStyle(DT.Color.textSecondary)
                .frame(width: 60, alignment: .leading)
            Text(people.map { $0.name }.joined(separator: ", "))
                .font(.system(.caption, design: .default))
                .foregroundStyle(DT.Color.textPrimary)
                .lineLimit(1)
        }
    }
}

/// A row of library titles that open their own pages: More Like This and the server's
/// recommendation rows.
struct DetailTitleShelf: View {
    @Environment(MediaRepository.self) private var mediaRepo
    let title: String
    let items: [MediaItem]
    /// Unused on Apple TV, which has no zoom transition.
    var zoomNamespace: Namespace.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DetailSectionTitle(title: title).padding(.horizontal, DT.Spacing.pagePad)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(items) { rec in
                        NavigationLink(value: rec) {
                            PosterCard(
                                title: rec.name,
                                subtitle: rec.productionYear.map { String($0) },
                                imageURL: mediaRepo.imageURL(for: rec)
                            )
                        }
#if os(tvOS)
                        .buttonStyle(TVCardButtonStyle())
                        .focusEffectDisabled()
#else
                        .buttonStyle(.plain)
                        .zoomTransitionSource(id: rec.id, in: zoomNamespace)
#endif
                    }
                }
                .padding(.horizontal, DT.Spacing.pagePad)
#if os(tvOS)
                .focusSection()
#endif
            }
            .shelfScrollButtons()
        }
        .padding(.bottom, DT.Spacing.md)
    }
}

/// The collections or playlists this title is in, laid out like More Like This.
struct DetailSetShelf: View {
    @Environment(MediaRepository.self) private var mediaRepo
    let title: String
    let sets: [MediaItem]
    let open: (MediaItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DetailSectionTitle(title: title).padding(.horizontal, DT.Spacing.pagePad)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(sets) { set in
                        Button { open(set) } label: {
                            PosterCard(title: set.name, imageURL: mediaRepo.imageURL(for: set))
                        }
#if os(tvOS)
                        .buttonStyle(TVCardButtonStyle())
                        .focusEffectDisabled()
#else
                        .buttonStyle(.plain)
#endif
                    }
                }
                .padding(.horizontal, DT.Spacing.pagePad)
#if os(tvOS)
                .focusSection()
#endif
            }
            .shelfScrollButtons()
        }
        .padding(.bottom, DT.Spacing.md)
    }
}

/// Seerr's recommendations for a title the library doesn't have, each opening a request.
struct DetailSeerrShelf: View {
    let items: [SeerrItem]
    let onSelect: (SeerrItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DetailSectionTitle(title: "Recommended").padding(.horizontal, DT.Spacing.pagePad)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(items) { sim in
                        Button { onSelect(sim) } label: {
                            PosterCard(
                                title: sim.title,
                                subtitle: sim.year,
                                imageURL: sim.posterURL
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, DT.Spacing.pagePad)
            }
            .shelfScrollButtons()
        }
        .padding(.bottom, DT.Spacing.md)
    }
}
