// SPDX-License-Identifier: AGPL-3.0-or-later

#if !os(tvOS)
import AppIntents
import Foundation

/// Apple's `.system.searchInApp` assistant schema (iOS 27), so Siri and Apple Intelligence can
/// run a request like "search Arcfin for heist movies" and land on the in-app results. Kept in
/// its own file because it is the one place that depends on the newest SDK.
///
/// There is no video domain among Apple's schema domains (only Audio, which is music and
/// podcasts), so search is what a video app can adopt. Opening a title is handled by
/// `OpenTitleIntent`, which keeps working on iOS 26.
@available(iOS 27.0, macOS 27.0, *)
@AppIntent(schema: .system.searchInApp)
struct SearchTitlesIntent: ShowInAppSearchResultsIntent {
    static let searchScopes: [StringSearchScope] = [.general]

    var criteria: StringSearchCriteria

    @MainActor
    func perform() async throws -> some IntentResult {
        ArcfinRouting.search(criteria.term)
        return .result()
    }
}
#endif
