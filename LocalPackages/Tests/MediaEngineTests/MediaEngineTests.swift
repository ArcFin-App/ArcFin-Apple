// SPDX-License-Identifier: AGPL-3.0-or-later

import Testing
@testable import MediaEngine

@Suite("PlayerState")
struct MediaEngineTests {

    @Test("Default PlayerState is idle")
    func defaultStateIsIdle() {
        let state = PlayerState()
        #expect(state.status == .idle)
        #expect(state.positionTicks == 0)
    }
}
