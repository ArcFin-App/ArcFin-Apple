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

    var body: some View {
        ZStack(alignment: .bottom) {
            // Background: poster image or gradient fallback
            if let url = imageURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: placeholderGradient
                    }
                }
                .clipped()
            } else {
                placeholderGradient
            }

            // Scan-line texture
            Canvas { context, size in
                for y in stride(from: 0, through: size.height, by: 4) {
                    context.fill(
                        Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                        with: .color(.white.opacity(0.012))
                    )
                }
            }
            .allowsHitTesting(false)

            // Glass sheen — top third
            LinearGradient(
                colors: [.white.opacity(0.06), .clear],
                startPoint: .top,
                endPoint: .init(x: 0.5, y: 0.4)
            )

            // Bottom title + progress
            VStack(spacing: 0) {
                Spacer()

                VStack(alignment: .leading, spacing: 3) {
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(DT.Color.textSecondary)
                    }
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DT.Color.textPrimary)
                        .lineLimit(2)
                        .shadow(color: .black.opacity(0.8), radius: 2)
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
        #if !os(tvOS)
        .onHover { hovered = $0 }
        #endif
    }

    private var placeholderGradient: some View {
        LinearGradient(
            colors: [accentHue, DT.Color.backgroundPrimary],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

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

struct RequestStatusPill: View {
    let status: CardRequestStatus

    var body: some View {
        Text(status.label)
            .font(.system(size: 7, weight: .bold))
            .tracking(0.5)
            .textCase(.uppercase)
            .foregroundStyle(status.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(status.color.opacity(0.15))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(status.color.opacity(0.3), lineWidth: 1))
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
