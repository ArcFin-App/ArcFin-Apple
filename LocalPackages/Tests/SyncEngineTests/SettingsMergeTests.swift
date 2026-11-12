// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
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

    @Test("A profile's first sync after a switch takes the server's values and sends nothing")
    func adoptRemoteAfterSwitch() {
        let result = SettingsSyncEngine.merge(
            local: ["seerrURL": "https://a.example", "autoPlayNext": "true"],
            remote: ["seerrURL": "https://b.example"],
            base: nil, locked: [], adoptRemote: true)
        #expect(result.apply == ["seerrURL": "https://b.example"])
        #expect(result.push.isEmpty)
    }

    @Test("Each profile starts from its own record; another profile's last sync means adopt")
    func startingPointPerProfile() {
        let defaults = UserDefaults(suiteName: "SettingsMergeTests.\(UUID().uuidString)")!
        defaults.set(["autoPlayNext": "true"], forKey: "arcfin.settingsSync.lastSynced")
        let first = SettingsSyncEngine.startingPoint(profile: "A", defaults: defaults)
        #expect(first.base == ["autoPlayNext": "true"])
        #expect(first.adoptRemote == false)
        defaults.set("A", forKey: "arcfin.settingsSync.lastProfile")
        defaults.set(["autoPlayNext": "true"], forKey: "arcfin.settingsSync.lastSynced.A")
        let other = SettingsSyncEngine.startingPoint(profile: "B", defaults: defaults)
        #expect(other.base == nil)
        #expect(other.adoptRemote == true)
        let again = SettingsSyncEngine.startingPoint(profile: "A", defaults: defaults)
        #expect(again.base == ["autoPlayNext": "true"])
    }
}
