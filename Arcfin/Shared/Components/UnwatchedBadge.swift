// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

/// How many episodes are left on a series, season or collection's poster, or a check once
/// they're all watched. Settings › Appearance › Show Unwatched Count turns it off.
struct UnwatchedBadge: ViewModifier {
    let item: MediaItem

    @AppStorage("showUnwatchedCount") private var isShown = true

    private var count: Int? {
        guard [.series, .season, .boxSet].contains(item.type) else { return nil }
        if let count = item.userData?.unplayedItemCount { return count }
        return item.userData?.played == true ? 0 : nil
    }

    func body(content: Content) -> some View {
        content.overlay(alignment: .topTrailing) {
            if isShown, let count {
                Group {
                    if count > 0 {
                        Text(count, format: .number)
                            .font(.system(.caption2, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(DT.Color.onAccent)
                            .padding(.horizontal, 6)
                            .frame(minWidth: 20, minHeight: 20)
                            .background(Capsule().fill(DT.Color.accent))
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(.body, weight: .semibold))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, DT.Color.palette("10b981"))
                    }
                }
                .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
                .padding(6)
                .accessibilityLabel(count > 0 ? Text("\(count) unwatched") : Text("Watched"))
            }
        }
    }
}

extension View {
    func unwatchedBadge(_ item: MediaItem) -> some View {
        modifier(UnwatchedBadge(item: item))
    }
}
