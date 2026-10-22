// SPDX-License-Identifier: AGPL-3.0-or-later

import Testing
@testable import SyncEngine

@Suite("Settings sync merge")
struct SettingsMergeTests {

    @Test("A setting changed here since the last sync is sent, not overwritten")
    func localChangeWins() {
        let result = SettingsSyncEngine.merge(
            local: ["smartDownloadsEnabled": "true"],
            remote: ["smartDownloadsEnabled": "false"],
            base: ["smartDownloadsEnabled": "false"],
            locked: [])
        #expect(result.push == ["smartDownloadsEnabled": "true"])
        #expect(result.apply.isEmpty)
    }

    @Test("A setting changed only on the server is taken from it")
    func remoteChangeWins() {
        let result = SettingsSyncEngine.merge(
            local: ["autoPlayNext": "true"],
            remote: ["autoPlayNext": "false"],
            base: ["autoPlayNext": "true"],
            locked: [])
        #expect(result.apply == ["autoPlayNext": "false"])
        #expect(result.push.isEmpty)
    }

    @Test("A locked setting always comes from the server")
    func lockedComesFromServer() {
        let result = SettingsSyncEngine.merge(
            local: ["wifiOnly": "false"],
            remote: ["wifiOnly": "true"],
            base: ["wifiOnly": "true"],
            locked: ["wifiOnly"])
        #expect(result.apply == ["wifiOnly": "true"])
        #expect(result.push.isEmpty)
    }

    @Test("A setting the server has never had is sent")
    func missingOnServerIsSent() {
        let result = SettingsSyncEngine.merge(
            local: ["skipIntro": "true"], remote: [:], base: [:], locked: [])
        #expect(result.push == ["skipIntro": "true"])
    }

    @Test("Before any agreed values are kept, a value set here is this device's choice")
    func firstMergeKeepsLocalChoice() {
        let result = SettingsSyncEngine.merge(
            local: ["smartDownloadsEnabled": "true"],
            remote: ["smartDownloadsEnabled": "false", "skipIntro": "true"],
            base: nil,
            locked: [])
        #expect(result.push == ["smartDownloadsEnabled": "true"])
        #expect(result.apply == ["skipIntro": "true"])
    }

    @Test("Keys outside the registry are left alone")
    func unknownKeysIgnored() {
        let result = SettingsSyncEngine.merge(
            local: ["somethingElse": "1"], remote: ["somethingElse": "2"], base: nil, locked: [])
        #expect(result.apply.isEmpty)
        #expect(result.push.isEmpty)
    }
}
