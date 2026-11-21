// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI
import AuthCore

// MARK: - Library card

/// Browse with no library tiles: still loading them, or the server couldn't be reached.
struct BrowseLibrariesStatus: View {
    @Environment(MediaRepository.self) private var mediaRepo
    @Environment(AuthManager.self) private var authManager

    var body: some View {
        if mediaRepo.connectionFailed {
            ContentUnavailableView {
                Label("Couldn't Load Your Libraries", systemImage: "exclamationmark.triangle")
            } description: {
                Text("Couldn't reach your server. Check your connection, then try again.")
            } actions: {
                Button("Try Again", action: retry)
            }
        } else if !mediaRepo.loaded {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, DT.Spacing.xl)
        }
    }

    private func retry() {
        guard case .authenticated(let cred) = authManager.state else { return }
        Task { await mediaRepo.load(credential: cred, authClient: authManager.authClient, force: true) }
    }
}

struct LibraryCard: View {
    @Environment(MediaRepository.self) private var mediaRepo
    let library: JellyfinLibrary
    let imageURL: URL?

    var body: some View {
        BrowseTile(systemImage: library.collectionType.systemIcon, title: library.name, count: mediaRepo.libraryCounts[library.id]) {
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
            BrowseTileFallback(systemImage: "text.badge.checkmark")
        }
    }
}

/// A Browse tile: artwork filling a 16:9 card, a warm scrim, and the icon and name at the
/// bottom. Lifts with a coral ring on hover (Mac, iPad pointer) or focus (Apple TV). The scrim
/// fades to the page surface, so the label is light on dark or dark on light.
struct BrowseTile<Background: View>: View {
    let systemImage: String
    let title: String
    /// How many titles the library holds, shown in the corner once it's known.
    var count: Int? = nil
    @ViewBuilder let background: Background

    @Environment(\.isFocused) private var isFocused
    @Environment(\.colorScheme) private var colorScheme
    @State private var hovered = false

    private var highlighted: Bool { hovered || isFocused }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: DT.Radius.lg, style: .continuous) }

    var body: some View {
        Color.clear
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                background
                    .scaleEffect(highlighted ? 1.06 : 1)
            }
            .overlay {
                LinearGradient(stops: [
                    .init(color: DT.Color.backgroundSecondary.opacity(0.92), location: 0),
                    .init(color: DT.Color.backgroundSecondary.opacity(0.45), location: 0.45),
                    .init(color: .clear, location: 0.85),
                ], startPoint: .bottom, endPoint: .top)
            }
            .overlay {
                RadialGradient(colors: [DT.Color.accent.opacity(highlighted ? 0.4 : 0.22), .clear],
                               center: .bottomLeading, startRadius: 0, endRadius: 240 * DT.Scale.font)
            }
            .overlay(alignment: .bottomLeading) { label }
            .overlay(alignment: .topTrailing) { countBadge }
            .clipShape(shape)
            .overlay(shape.strokeBorder(DT.Color.textPrimary.opacity(0.08), lineWidth: 1))
            .overlay(
                shape.strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.2), .clear], startPoint: .top, endPoint: .bottom),
                    lineWidth: 1
                )
            )
            .overlay(shape.strokeBorder(DT.Color.accent, lineWidth: 2 * DT.Scale.font).opacity(highlighted ? 1 : 0))
            .shadow(color: highlighted ? DT.Color.accent.opacity(0.35) : .black.opacity(colorScheme == .dark ? 0.3 : 0.1),
                    radius: highlighted ? 18 : 10, y: highlighted ? 8 : 5)
            .scaleEffect(highlighted ? 1.03 : 1)
            .animation(DT.Animation.fast, value: highlighted)
            .onPointerHover { hovered = $0 }
            .contentShape(shape)
    }

    @ViewBuilder
    private var countBadge: some View {
        if let count, count > 0 {
            Text(count.formatted())
                .scaledFont(size: 11, weight: .semibold)
                .monospacedDigit()
                .foregroundStyle(DT.Color.textPrimary)
                .padding(.horizontal, 8 * DT.Scale.font)
                .padding(.vertical, 3 * DT.Scale.font)
                .background(DT.Color.backgroundSecondary.opacity(0.75), in: Capsule())
                .padding(10 * DT.Scale.font)
        }
    }

    private var label: some View {
        HStack(spacing: 10 * DT.Scale.font) {
            Image(systemName: systemImage)
                .scaledFont(size: 12, weight: .bold)
                .foregroundStyle(DT.Color.onAccent)
                .frame(width: 28 * DT.Scale.font, height: 28 * DT.Scale.font)
                .background(DT.Color.accent, in: Circle())
            Text(title)
                .scaledFont(size: 17, weight: .bold)
                .foregroundStyle(DT.Color.textPrimary)
                .lineLimit(1)
                .shadow(color: DT.Color.backgroundSecondary.opacity(0.5), radius: 4)
        }
        .padding(14 * DT.Scale.font)
    }
}

/// A tile with no artwork: graphite, with its icon large, tilted and lit coral from the corner.
struct BrowseTileFallback: View {
    let systemImage: String

    var body: some View {
        ZStack(alignment: .trailing) {
            LinearGradient(colors: [DT.Color.backgroundTertiary, DT.Color.backgroundPrimary],
                           startPoint: .topTrailing, endPoint: .bottomLeading)
            Image(systemName: systemImage)
                .font(.system(size: 110 * DT.Scale.font, weight: .ultraLight))
                .foregroundStyle(LinearGradient(colors: [DT.Color.accent.opacity(0.45), DT.Color.textPrimary.opacity(0.03)],
                                                startPoint: .topTrailing, endPoint: .bottomLeading))
                .rotationEffect(.degrees(-12))
                .offset(x: 30 * DT.Scale.font, y: -12 * DT.Scale.font)
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
                            .contentFont(.caption2, design: .default, weight: .semibold)
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        if let year {
                            Text(year)
                                .contentFont(.caption2)
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
    let title: LocalizedStringKey

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
                .contentFont(.title3)
                .foregroundStyle(DT.Color.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .contentFont(.subheadline, design: .default, weight: .semibold)
                    .foregroundStyle(DT.Color.textPrimary)
                Text(subtitle)
                    .contentFont(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .contentFont(.footnote)
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
