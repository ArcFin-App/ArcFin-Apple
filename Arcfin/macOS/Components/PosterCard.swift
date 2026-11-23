// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

struct PosterCard: View {
    var title: String
    var subtitle: String? = nil
    var accentHue: Color = Color(hex: "24140F")
    var progress: Double? = nil
    var imageURL: URL? = nil
    var width: CGFloat = DT.Size.posterCard.width
    var height: CGFloat = DT.Size.posterCard.height

    @State private var hovered = false

    // The Mac's caption styles are 10 pt, too small over artwork on a bigger card.
    private static let titleStyle: Font.TextStyle = .body
    private static let subtitleStyle: Font.TextStyle = .subheadline

    private var cardAccessibilityValue: Text {
        var parts: [String] = []
        if let subtitle { parts.append(subtitle) }
        if let progress {
            parts.append(String(localized: "\(progress.formatted(.percent.precision(.fractionLength(0)))) watched"))
        }
        return Text(verbatim: parts.joined(separator: ", "))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            imageLayer

            // Pointer-only affordance. Mac only: iPad pointer hover already gets the
            // scale/glow treatment without needing an icon.
            if hovered {
                Image(systemName: "play.fill")
                    .contentFont(.callout, weight: .bold)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.black.opacity(0.45), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 1))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
                    .allowsHitTesting(false)
            }

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
                        .contentFont(Self.titleStyle, design: .default, weight: .semibold)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .shadow(color: .black.opacity(0.8), radius: 2)
                    if let subtitle {
                        Text(subtitle)
                            .contentFont(Self.subtitleStyle, design: .default, weight: .medium)
                            .foregroundStyle(.white.opacity(0.7))
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(cardAccessibilityValue)
        .frame(width: width, height: height)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: DT.Radius.card)
                .stroke(hovered ? DT.Color.accent.opacity(0.35) : DT.Color.textPrimary.opacity(0.06), lineWidth: 1)
        )
        .scaleEffect(hovered ? 1.04 : 1)
        .shadow(
            color: hovered ? DT.Color.accent.opacity(0.22) : .black.opacity(0.5),
            radius: hovered ? 16 : 4,
            y: hovered ? 8 : 2
        )
        .animation(DT.Animation.fast, value: hovered)
        .onHover { hovered = $0 }
        // The Apple TV card has this too — without it, a NavigationLink wrapping this
        // ZStack has no explicit click target, which AppKit's hit-testing is stricter
        // about than UIKit's.
        .contentShape(Rectangle())
    }

    private var imageLayer: some View {
        PosterCardArtwork(title: title, imageURL: imageURL, accentHue: accentHue)
    }
}
