// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Testing
@testable import Arcfin

@MainActor
struct MusicPagedListTests {
    private struct Row: Identifiable, Sendable { let id: Int }

    @Test func aCancelledRequestLeavesTheListToLoadAgain() async {
        let list = MusicPagedList<Row> { _ in throw URLError(.cancelled) }
        await list.loadIfNeeded()
        #expect(!list.hasLoaded)
        #expect(!list.hasFailed)
    }

    @Test func aFailedRequestShowsAsFailed() async {
        let list = MusicPagedList<Row> { _ in throw URLError(.timedOut) }
        await list.loadIfNeeded()
        #expect(list.hasLoaded)
        #expect(list.hasFailed)
    }

    @Test func comingBackAfterACancelLoadsTheList() async {
        var calls = 0
        let list = MusicPagedList<Row> { _ in
            calls += 1
            if calls == 1 { throw URLError(.cancelled) }
            return ([Row(id: 1), Row(id: 2)], 2)
        }
        await list.loadIfNeeded()
        await list.loadIfNeeded()
        #expect(list.items.map(\.id) == [1, 2])
        #expect(list.hasLoaded && !list.hasFailed)
    }
}
