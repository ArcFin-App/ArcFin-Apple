// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

extension LibraryFilterList {
    var minimumScoreControls: some View {
        Picker("Score", selection: Binding(
            get: { extraFilters.minRating ?? 0 },
            set: { extraFilters.minRating = $0 > 0 ? $0 : nil }
        )) {
            Text("Any").tag(0.0)
            ForEach([5.0, 6.0, 7.0, 7.5, 8.0, 8.5, 9.0], id: \.self) { Text(String(format: "%.1f+", $0)).tag($0) }
        }
    }

    func contentRatingControls(ordered: [String], step: Int, label: String) -> some View {
        Picker("Maturity", selection: Binding(
            get: { step },
            set: { extraFilters.officialRatings = LibraryExtraFilters.ratings(upToStep: $0, in: ordered) }
        )) {
            ForEach(0..<ordered.count, id: \.self) { Text("Up to \(ordered[$0])").tag($0) }
            Text("Any").tag(ordered.count)
        }
    }
}

/// A filter's choices on their own page.
struct FilterGroup<Content: View>: View {
    let title: String
    let value: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        NavigationLink {
            List { content() }
                .navigationTitle(title)
        } label: {
            LabeledContent(title, value: value)
        }
    }
}
