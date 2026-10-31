// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

// MARK: - Library card

struct LibraryCard: View {
    let library: JellyfinLibrary
    let imageURL: URL?

    var body: some View {
        BrowseTile(systemImage: library.collectionType.systemIcon, title: library.name) {
            if let imageURL {
                CachedAsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: BrowseTileFallback(systemImage: library.collectionType.systemIcon)
                    }
                }
            } else {
                BrowseTileFallback(systemImage: library.collectionType.systemIcon)
            }
        }
    }
}

/// "Your Requests" as one more tile alongside the library ones.
struct RequestsCard: View {
    var body: some View {
        BrowseTile(systemImage: "text.badge.checkmark", title: "Requests") {
            ZStack {
                DT.Color.backgroundTertiary
                RadialGradient(colors: [DT.Color.accent.opacity(0.55), .clear],
                               center: .topTrailing, startRadius: 0, endRadius: 180)
            }
        }
    }
}

/// A Browse tile: artwork filling the card, with the icon and name on a scrim at the bottom.
/// Always dark, so the white label reads in either appearance.
private struct BrowseTile<Background: View>: View {
    let systemImage: String
    let title: String
    @ViewBuilder let background: Background

    @State private var hovered = false

    var body: some View {
        Color.clear
            .frame(height: 110)
            .overlay { background }
            .overlay(alignment: .bottomLeading) {
                ZStack(alignment: .bottomLeading) {
                    LinearGradient(colors: [.black.opacity(0.85), .black.opacity(0.35), .clear],
                                   startPoint: .bottom, endPoint: .top)
                    HStack(spacing: 8) {
                        Image(systemName: systemImage)
                            .font(.system(.subheadline, weight: .semibold))
                            .foregroundStyle(DT.Color.accent)
                        Text(title)
                            .font(.system(.subheadline, design: .default, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    .padding(12)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DT.Radius.card, style: .continuous)
                    .stroke(hovered ? DT.Color.accent.opacity(0.6) : .white.opacity(0.08), lineWidth: 1)
            )
            .alwaysDark()
            .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
            .scaleEffect(hovered ? 1.02 : 1)
            .animation(DT.Animation.fast, value: hovered)
            .onPointerHover { hovered = $0 }
            .contentShape(RoundedRectangle(cornerRadius: DT.Radius.card, style: .continuous))
    }
}

/// A library with no artwork: graphite with its icon large and faint in the corner.
private struct BrowseTileFallback: View {
    let systemImage: String

    var body: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(colors: [DT.Color.backgroundTertiary, DT.Color.backgroundSecondary],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: systemImage)
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.white.opacity(0.08))
                .padding(10)
        }
    }
}

// MARK: - Library grid item card

struct LibraryItemCard: View {
    let imageURL: URL?
    let title: String
    let year: String?

    @State private var hovered = false

    var body: some View {
        // The card's shape comes from the grid, not the image: a square cover (a playlist's)
        // filled to the image's own size made the card wider than its column.
        Color.clear
            .aspectRatio(2/3, contentMode: .fit)
            .overlay {
                if let imageURL {
                    CachedAsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFill()
                        default: Color(DT.Color.backgroundSecondary)
                        }
                    }
                } else {
                    DT.Color.backgroundSecondary
                }
            }
            .overlay(alignment: .bottomLeading) {
                ZStack(alignment: .bottomLeading) {
                    LinearGradient(colors: [.black.opacity(0.8), .clear], startPoint: .bottom, endPoint: .top)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(.caption2, design: .default, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        if let year {
                            Text(year)
                                .font(.system(.caption2))
                                .foregroundStyle(.white.opacity(0.6))
                                .lineLimit(2)
                        }
                    }
                    .padding(8)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(hovered ? DT.Color.accent.opacity(0.4) : DT.Color.textPrimary.opacity(0.06), lineWidth: 1)
        )
        .scaleEffect(hovered ? 1.03 : 1)
        .shadow(color: hovered ? DT.Color.accent.opacity(0.2) : .clear, radius: hovered ? 12 : 0)
        .animation(DT.Animation.fast, value: hovered)
        .onPointerHover { hovered = $0 }
        // Without this, a NavigationLink wrapping this ZStack has no explicit click
        // target, which AppKit's hit-testing is stricter about than UIKit's.
        .contentShape(Rectangle())
    }
}

// MARK: - Browse sections

struct LibrarySectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(DT.Font.cardTitle)
            .foregroundStyle(DT.Color.textPrimary)
            .tracking(-0.2)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A full-width row on Browse that leads somewhere: Downloads, or a file on this device.
struct LibraryLinkRow: View {
    let systemImage: String
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(.title3))
                .foregroundStyle(DT.Color.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.subheadline, design: .default, weight: .semibold))
                    .foregroundStyle(DT.Color.textPrimary)
                Text(subtitle)
                    .font(.system(.caption))
                    .foregroundStyle(DT.Color.textSecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(.footnote))
                .foregroundStyle(DT.Color.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: DT.Radius.card)
                .fill(DT.Color.backgroundSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: DT.Radius.card)
                        .stroke(DT.Color.textPrimary.opacity(0.06), lineWidth: 1)
                )
        )
    }
}
