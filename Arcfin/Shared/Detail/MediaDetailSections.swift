// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI
import SeerrAPI

// The title page's sections below the hero, each its own view.

struct DetailSectionTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .contentFont(.callout, design: .default, weight: .bold)
            .foregroundStyle(DT.Color.textPrimary)
            .tracking(-0.3)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The title's details couldn't be fetched: says so, with a way to ask again.
struct DetailLoadFailedRow: View {
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Text("Couldn't load this title's details.")
                .contentFont(.callout)
                .foregroundStyle(DT.Color.textSecondary)
                .multilineTextAlignment(.center)
            Button("Try Again", action: retry)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DT.Spacing.md)
    }
}

struct DetailGenreChips: View {
    let genres: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(genres, id: \.self) { genre in
                    Text(genre)
                        .contentFont(.caption2, design: .default, weight: .medium)
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
    }
}

struct DetailOverviewSection: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DetailSectionTitle(title: "Overview")
            Text(text)
                .contentFont(.footnote, design: .default)
                .foregroundStyle(DT.Color.textSecondary)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: PlatformMetrics.descriptionMaxWidth, alignment: .leading)
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

private struct DetailPersonPlaceholder: View {
    var body: some View {
        Circle()
            .fill(DT.Color.backgroundSecondary)
            .overlay(Image(systemName: "person.fill")
                .contentFont(.title2)
                .foregroundStyle(DT.Color.textSecondary.opacity(0.4)))
    }
}

struct CastPersonCard<Placeholder: View>: View {
    let imageURL: URL?
    let name: String
    let role: String?
    @ViewBuilder let placeholder: () -> Placeholder

    @State private var hovered = false

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if let imageURL {
                    RetryingAsyncImage(
                        url: imageURL,
                        logCategory: "CastPersonCard",
                        logContext: "name=\(name)",
                        content: { img in img.resizable().scaledToFill() },
                        placeholder: { placeholder() }
                    )
                } else {
                    placeholder()
                }
            }
            .frame(width: 60, height: 60)
            .clipShape(Circle())
            .overlay(Circle().stroke(hovered ? DT.Color.accent.opacity(0.6) : DT.Color.textPrimary.opacity(0.1), lineWidth: hovered ? 2 : 1))
            .scaleEffect(hovered ? 1.06 : 1)

            Text(name)
                .contentFont(.caption2, design: .default, weight: .semibold)
                .foregroundStyle(DT.Color.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            if let role, !role.isEmpty {
                Text(role)
                    .contentFont(.caption2, design: .default)
                    .foregroundStyle(DT.Color.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(width: 70, alignment: .top)
        .animation(DT.Animation.fast, value: hovered)
        .onPointerHover { hovered = $0 }
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
        .frame(maxWidth: .infinity, alignment: .leading)
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
                .contentFont(.caption2, design: .default, weight: .bold)
                .foregroundStyle(DT.Color.textSecondary)
                .frame(width: 60, alignment: .leading)
            Text(people.map { $0.name }.joined(separator: ", "))
                .contentFont(.caption, design: .default)
                .foregroundStyle(DT.Color.textPrimary)
                .lineLimit(1)
        }
    }
}

/// A row of library titles that open their own pages: More Like This and the server's
/// recommendation rows.
struct DetailTitleShelf<Link: View>: View {
    @Environment(MediaRepository.self) private var mediaRepo
    let title: String
    let items: [MediaItem]
    /// Each platform's link around a title's poster.
    @ViewBuilder let link: (MediaItem, PosterCard) -> Link

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DetailSectionTitle(title: title).padding(.horizontal, DT.Spacing.pagePad)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(items) { rec in
                        link(rec, PosterCard(
                            title: rec.name,
                            subtitle: rec.productionYear.map { String($0) },
                            imageURL: mediaRepo.imageURL(for: rec)
                        ))
                    }
                }
                .padding(.horizontal, DT.Spacing.pagePad)
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

/// Seerr's recommendations for a title the library doesn't have.
struct DetailSeerrShelf: View {
    let items: [SeerrItem]
    let subtitle: (SeerrItem) -> String?
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
                                subtitle: subtitle(sim),
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
