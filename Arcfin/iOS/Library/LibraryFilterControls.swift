// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

extension LibraryFilterList {
    @ViewBuilder
    var minimumScoreControls: some View {
        let score = extraFilters.minRating ?? 0
        LabeledContent("Score", value: score > 0 ? String(format: "%.1f+", score) : "Any")
        Slider(
            value: Binding(
                get: { extraFilters.minRating ?? 0 },
                set: { extraFilters.minRating = $0 > 0 ? $0 : nil }
            ),
            in: 0...9, step: 0.5
        )
        .accessibilityLabel("Minimum score")
        .accessibilityValue(score > 0 ? String(format: "%.1f or higher", score) : "Any")
    }

    @ViewBuilder
    func contentRatingControls(ordered: [String], step: Int, label: String) -> some View {
        LabeledContent("Maturity", value: label)
        Slider(
            value: Binding(
                get: { Double(step) },
                set: { extraFilters.officialRatings = LibraryExtraFilters.ratings(upToStep: Int($0), in: ordered) }
            ),
            in: 0...Double(ordered.count), step: 1
        )
        .accessibilityLabel("Maximum content rating")
        .accessibilityValue(label)
    }
}

/// A filter's choices, expanding in place.
struct FilterGroup<Content: View>: View {
    let title: String
    let value: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        DisclosureGroup {
            content()
        } label: {
            LabeledContent(title, value: value)
        }
    }
}
