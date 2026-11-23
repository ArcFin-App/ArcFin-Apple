// SPDX-License-Identifier: AGPL-3.0-or-later

import Testing
import JellyfinAPI
@testable import Arcfin

/// Arcfin for Everyone's per-user locks.
@MainActor
struct ArcfinSyncAdminModelTests {
    @Test func aUsersOwnDefaultKeepsFollowingEveryonesLock() {
        let model = ArcfinSyncAdminModel()
        model.setLocked(true, for: "skipIntro")
        model.setUserDefault("false", for: "skipIntro", user: "u1")
        #expect(model.lockChoice("skipIntro", user: "u1") == .inherited)
        #expect(model.entry("skipIntro", user: "u1")?.locked == nil)
        #expect(model.entry("skipIntro", user: "u1")?.defaultValue == "false")
    }

    @Test func sameAsEveryoneDropsOnlyTheUsersOwnLock() {
        let model = ArcfinSyncAdminModel()
        model.setUserDefault("false", for: "skipIntro", user: "u1")
        model.setLockChoice(.unlocked, for: "skipIntro", user: "u1")
        #expect(model.lockChoice("skipIntro", user: "u1") == .unlocked)
        model.setLockChoice(.inherited, for: "skipIntro", user: "u1")
        #expect(model.lockChoice("skipIntro", user: "u1") == .inherited)
        #expect(model.entry("skipIntro", user: "u1")?.defaultValue == "false")

        model.setUserDefault(nil, for: "skipIntro", user: "u1")
        #expect(model.entry("skipIntro", user: "u1") == nil)
        #expect(model.overrideCount(user: "u1") == 0)
    }
}
