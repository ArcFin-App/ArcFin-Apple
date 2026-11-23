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

    // MARK: Cleared settings

    @Test("A setting cleared on another device is cleared here, not sent back; an older server can't clear one")
    func clearedElsewhereIsClearedHere() {
        let local = ["autoPlayNext": "false", "skipIntro": "true"]
        let base = ["autoPlayNext": "false", "skipIntro": "true"]
        let result = SettingsSyncEngine.merge(local: local, remote: ["skipIntro": "true"], base: base, locked: [],
                                              canClearOnServer: true)
        #expect(result.clear == ["autoPlayNext"])
        #expect(result.push.isEmpty)
        #expect(result.apply.isEmpty)
        let legacy = SettingsSyncEngine.merge(local: local, remote: ["skipIntro": "true"], base: base, locked: [])
        #expect(legacy.clear.isEmpty)
        #expect(legacy.push == ["autoPlayNext": "false"])
    }

    @Test("A setting changed here since still goes, even if another device cleared it")
    func changedHereBeatsClear() {
        let result = SettingsSyncEngine.merge(
            local: ["autoPlayNext": "true"], remote: [:], base: ["autoPlayNext": "false"], locked: [], canClearOnServer: true)
        #expect(result.push == ["autoPlayNext": "true"])
        #expect(result.clear.isEmpty)
    }

    @Test("The Seerr sign-in is never cleared by a sync")
    func seerrNeverCleared() {
        let result = SettingsSyncEngine.merge(
            local: ["seerrURL": "https://a"], remote: [:], base: ["seerrURL": "https://a"], locked: [], canClearOnServer: true)
        #expect(result.clear.isEmpty)
        #expect(result.push == ["seerrURL": "https://a"])
        let cleared = SettingsSyncEngine.merge(
            local: [:], remote: ["seerrURL": "https://a"], base: ["seerrURL": "https://a"], locked: [], canClearOnServer: true)
        #expect(cleared.clearOnServer.isEmpty)
        #expect(cleared.apply == ["seerrURL": "https://a"])
    }

    @Test("A setting cleared here is cleared on a server that takes clears; on one that doesn't, it comes back")
    func clearedHereGoesToServer() {
        let result = SettingsSyncEngine.merge(
            local: [:], remote: ["autoPlayNext": "false"], base: ["autoPlayNext": "false"], locked: [], canClearOnServer: true)
        #expect(result.clearOnServer == ["autoPlayNext"])
        #expect(result.apply.isEmpty)
        let legacy = SettingsSyncEngine.merge(
            local: [:], remote: ["autoPlayNext": "false"], base: ["autoPlayNext": "false"], locked: [])
        #expect(legacy.clearOnServer.isEmpty)
        #expect(legacy.apply == ["autoPlayNext": "false"])
        // Changed on the server since: the server's value is taken.
        let changed = SettingsSyncEngine.merge(
            local: [:], remote: ["autoPlayNext": "true"], base: ["autoPlayNext": "false"], locked: [], canClearOnServer: true)
        #expect(changed.apply == ["autoPlayNext": "true"])
    }

    @Test("A sent setting the server didn't keep isn't agreed, so it's sent again rather than cleared")
    func notKeptIsntAgreed() {
        let base = ["autoPlayNext": "false"]
        let agreed = SettingsSyncEngine.agreedAfterSending(
            ["autoPlayNext": "true", "skipIntro": "true"], pushed: ["autoPlayNext": "true", "skipIntro": "true"], cleared: [],
            kept: ["skipIntro": "true"], base: base)
        #expect(agreed == ["autoPlayNext": "false", "skipIntro": "true"])
        let next = SettingsSyncEngine.merge(local: ["autoPlayNext": "true", "skipIntro": "true"],
                                            remote: ["skipIntro": "true"], base: agreed, locked: [], canClearOnServer: true)
        #expect(next.push == ["autoPlayNext": "true"])
        #expect(next.clear.isEmpty)
        // Nothing reached the server: a clear stays to be sent too.
        let failed = SettingsSyncEngine.agreedAfterSending([:], pushed: [:], cleared: ["autoPlayNext"], kept: nil, base: base)
        #expect(failed == base)
    }
}
