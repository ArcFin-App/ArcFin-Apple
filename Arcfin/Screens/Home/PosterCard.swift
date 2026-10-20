// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

struct PosterCard: View {
    var title: String
    var subtitle: String? = nil
    var accentHue: Color = Color(hex: "1a0d2e")
    var progress: Double? = nil
    var imageURL: URL? = nil
    var width: CGFloat = DT.Size.posterCard.width
    var height: CGFloat = DT.Size.posterCard.height

    @State private var hovered = false
#if os(tvOS)
    @Environment(\.isFocused) private var isFocused
#endif

    var body: some View {
#if os(tvOS)
        tvBody
#else
        iOSBody
#endif
    }

#if os(tvOS)
    private var tvBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            imageLayer
                .frame(width: width, height: height)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: DT.Radius.card))
                .overlay(
                    RoundedRectangle(cornerRadius: DT.Radius.card)
                        .stroke(isFocused ? DT.Color.accent : Color.clear, lineWidth: 3)
                )
                .shadow(color: isFocused ? DT.Color.accent.opacity(0.4) : .clear, radius: 10)
                .compositingGroup()
                .scaleEffect(isFocused ? 1.05 : 1.0)
                .animation(.spring(response: 0.2, dampingFraction: 0.75), value: isFocused)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12 * DT.Scale.font, weight: .semibold))
                    .foregroundStyle(isFocused ? DT.Color.accent : DT.Color.textPrimary)
                    .lineLimit(2)
                    .animation(DT.Animation.fast, value: isFocused)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10 * DT.Scale.font, weight: .medium))
                        .foregroundStyle(DT.Color.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(width: width, height: 84, alignment: .topLeading)
        }
        // Clip the whole card+text column so no system focus transform bleeds outside
        .contentShape(Rectangle())
    }
#endif

    #if !os(tvOS)
    private var iOSBody: some View {
        ZStack(alignment: .bottom) {
            imageLayer

#if os(macOS)
            // Pointer-only affordance — mirrors the hover play-button treatment of the
            // Apple TV and Plex Mac apps. Gated to macOS since iPadOS pointer hover
            // already gets the scale/glow treatment below without needing an icon.
            if hovered {
                Image(systemName: "play.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.black.opacity(0.45), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 1))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
                    .allowsHitTesting(false)
            }
#endif

            Canvas { context, size in
                for y in stride(from: 0, through: size.height, by: 4) {
                    context.fill(
                        Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                        with: .color(.white.opacity(0.012))
                    )
                }
            }
            .allowsHitTesting(false)

            LinearGradient(
                colors: [.white.opacity(0.06), .clear],
                startPoint: .top,
                endPoint: .init(x: 0.5, y: 0.4)
            )

            VStack(spacing: 0) {
                Spacer()
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DT.Color.textPrimary)
                        .lineLimit(2)
                        .shadow(color: .black.opacity(0.8), radius: 2)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(DT.Color.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.top, 24)
                .padding(.bottom, progress != nil ? 6 : 8)
                .background(
                    LinearGradient(
                        colors: [.black.opacity(0.95), .clear],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )

                if let progress {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(.white.opacity(0.1))
                            Rectangle()
                                .fill(DT.Color.accent)
                                .frame(width: geo.size.width * progress)
                        }
                    }
                    .frame(height: 2)
                }
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: DT.Radius.card)
                .stroke(hovered ? DT.Color.accent.opacity(0.35) : Color.white.opacity(0.06), lineWidth: 1)
        )
        .scaleEffect(hovered ? 1.04 : 1)
        .shadow(
            color: hovered ? DT.Color.accent.opacity(0.22) : .black.opacity(0.5),
            radius: hovered ? 16 : 4,
            y: hovered ? 8 : 2
        )
        .animation(DT.Animation.fast, value: hovered)
        .onHover { hovered = $0 }
        // tvBody (above) already has this — without it, a NavigationLink wrapping this
        // ZStack has no explicit click target, which AppKit's hit-testing is stricter
        // about than UIKit's.
        .contentShape(Rectangle())
    }
    #endif

    private var imageLayer: some View {
        Group {
            if let url = imageURL {
                RetryingAsyncImage(
                    url: url,
                    logCategory: "PosterCard",
                    logContext: "title=\(title)",
                    content: { img in img.resizable().scaledToFill() },
                    placeholder: { placeholderGradient }
                )
                .clipped()
            } else {
                placeholderGradient
            }
        }
    }

    private var placeholderGradient: some View {
        LinearGradient(
            colors: [accentHue, DT.Color.backgroundPrimary],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Zoom transition wiring

#if !os(tvOS)
extension View {
    /// Matches a poster tap's source geometry with its MediaDetailView destination for the
    /// `.zoom` navigation transition. `namespace` is optional because MediaDetailView can be
    /// reached from places that don't own a matching namespace (e.g. the Home hero banner) —
    /// those fall back to a plain push instead of failing to compile.
    @ViewBuilder
    func zoomTransitionSource(id: String, in namespace: Namespace.ID?) -> some View {
        if let namespace {
            self.matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }
}
#endif

// MARK: - Request card

struct RequestCard: View {
    var title: String
    var status: CardRequestStatus
    var accentHue: Color = DT.Color.backgroundSecondary

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [accentHue, DT.Color.backgroundPrimary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Canvas { context, size in
                for y in stride(from: 0, through: size.height, by: 4) {
                    context.fill(
                        Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                        with: .color(.white.opacity(0.01))
                    )
                }
            }
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 4) {
                RequestStatusPill(status: status)
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DT.Color.textPrimary)
            }
            .padding(8)
        }
        .frame(width: 140, height: 80)
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.card))
        .overlay(RoundedRectangle(cornerRadius: DT.Radius.card).stroke(.white.opacity(0.06), lineWidth: 1))
    }
}

// MARK: - Status models

enum CardRequestStatus: String {
    case approved, pending, downloading, available

    var color: Color {
        switch self {
        case .approved, .available: Color(hex: "10b981")
        case .pending:              Color(hex: "f59e0b")
        case .downloading:          DT.Color.accent
        }
    }

    var label: String { rawValue.capitalized }
}

/// Shared pill treatment for a request/availability status badge — was independently
/// reimplemented at 4 call sites (here, SeerrRequestsListView, and twice in SeerrView),
/// all at a 7pt font, below the 11pt iOS minimum for real text (typography.md). One
/// component means one place to get both the sizing and the look right.
struct StatusPill: View {
    let label: String
    let color: Color
    var uppercase: Bool = false

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .bold))
            .tracking(0.5)
            .textCase(uppercase ? .uppercase : nil)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            // .ultraThinMaterial underneath the tint guarantees a legible backing
            // regardless of what's behind the pill — these sit directly over poster art,
            // whose own color/brightness can't be predicted (color.md).
            .background(.ultraThinMaterial)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(color.opacity(0.3), lineWidth: 1))
    }
}

struct RequestStatusPill: View {
    let status: CardRequestStatus

    var body: some View {
        StatusPill(label: status.label, color: status.color, uppercase: true)
    }
}

#Preview {
    HStack(spacing: 12) {
        PosterCard(title: "Dune: Part Two", subtitle: "2024", accentHue: Color(hex: "1a0a2e"), progress: 0.62)
        PosterCard(title: "Oppenheimer", subtitle: "S2 E7", accentHue: Color(hex: "1c0e00"))
    }
    .padding()
    .background(DT.Color.backgroundPrimary)
}
