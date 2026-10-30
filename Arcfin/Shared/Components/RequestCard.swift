// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

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
                    .font(.system(.caption2, design: .default, weight: .semibold))
                    .foregroundStyle(DT.Color.textPrimary)
            }
            .padding(8)
        }
        .frame(width: 140, height: 80)
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.card))
        .overlay(RoundedRectangle(cornerRadius: DT.Radius.card).stroke(DT.Color.textPrimary.opacity(0.06), lineWidth: 1))
    }
}

// MARK: - Status models

enum CardRequestStatus: String {
    case approved, pending, downloading, available

    var color: Color {
        switch self {
        case .approved, .available: DT.Color.palette("10b981")
        case .pending:              DT.Color.palette("f59e0b")
        case .downloading:          DT.Color.accent
        }
    }

    var label: String {
        switch self {
        case .approved:    String(localized: "Approved")
        case .pending:     String(localized: "Pending")
        case .downloading: String(localized: "Downloading")
        case .available:   String(localized: "Available")
        }
    }
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
            .font(.system(.caption2, design: .default, weight: .bold))
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
