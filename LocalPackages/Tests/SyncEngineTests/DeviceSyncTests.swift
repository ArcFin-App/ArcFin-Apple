// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import JellyfinAPI
import Testing
@testable import SyncEngine

@Suite("Device sync")
struct DeviceSyncTests {
    private let defaults: UserDefaults

    init() {
        let suite = "DeviceSyncTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    private func state(by device: String?, at seconds: TimeInterval?) -> ArcfinSyncState {
        ArcfinSyncState(settings: [], updatedAt: seconds.map { Date(timeIntervalSince1970: $0) },
                        updatedByDeviceId: device, updatedByDeviceName: "Living Room")
    }

    // MARK: Ask First

    @Test("A change from another device asks once")
    func asksForAnotherDevicesChange() {
        let changes = ["skipIntro": "true"]
        #expect(SettingsSyncEngine.shouldAsk(state: state(by: "tv", at: 100), deviceID: "phone", lastHandled: nil, changes: changes))
        #expect(SettingsSyncEngine.shouldAsk(state: state(by: "tv", at: 100), deviceID: "phone",
                                             lastHandled: Date(timeIntervalSince1970: 50), changes: changes))
        #expect(!SettingsSyncEngine.shouldAsk(state: state(by: "tv", at: 100), deviceID: "phone",
                                              lastHandled: Date(timeIntervalSince1970: 100), changes: changes))
    }

    @Test("This device's own change, one with no device, or nothing to take never asks")
    func doesntAsk() {
        #expect(!SettingsSyncEngine.shouldAsk(state: state(by: "phone", at: 100), deviceID: "phone", lastHandled: nil,
                                              changes: ["skipIntro": "true"]))
        #expect(!SettingsSyncEngine.shouldAsk(state: state(by: nil, at: 100), deviceID: "phone", lastHandled: nil,
                                              changes: ["skipIntro": "true"]))
        #expect(!SettingsSyncEngine.shouldAsk(state: state(by: "tv", at: nil), deviceID: "phone", lastHandled: nil,
                                              changes: ["skipIntro": "true"]))
        #expect(!SettingsSyncEngine.shouldAsk(state: state(by: "tv", at: 100), deviceID: "phone", lastHandled: nil, changes: [:]))
    }

    @Test("Using them applies them and counts them as agreed; keeping applies nothing")
    func answers() {
        let profile = UUID().uuidString
        defaults.set(false, forKey: "skipIntro")
        defaults.set(["skipIntro": "false"], forKey: SettingsSyncEngine.lastSyncedKey(profile: profile))
        let change = RemoteSettingsChange(profile: profile, deviceName: "TV", updatedAt: Date(timeIntervalSince1970: 100),
                                          values: ["skipIntro": "true"])

        SettingsSyncEngine.answer(change, useThem: false, defaults: defaults)
        #expect(defaults.bool(forKey: "skipIntro") == false)

        SettingsSyncEngine.answer(change, useThem: true, defaults: defaults)
        #expect(defaults.bool(forKey: "skipIntro") == true)
        #expect(!SettingsSyncEngine.hasLocalChanges(profile: profile, defaults: defaults))
    }

    @Test("Using them leaves a locked setting as the administrator set it")
    func answerKeepsLocks() {
        let profile = UUID().uuidString
        defaults.set(false, forKey: "skipIntro")
        defaults.set(["skipIntro"], forKey: SettingsSyncEngine.lockedKey(profile: profile))
        let change = RemoteSettingsChange(profile: profile, deviceName: "TV", updatedAt: .now, values: ["skipIntro": "true"])
        SettingsSyncEngine.answer(change, useThem: true, defaults: defaults)
        #expect(defaults.bool(forKey: "skipIntro") == false)
    }

    @Test("Using them clears what the other device cleared")
    func answerClears() {
        let profile = UUID().uuidString
        defaults.set(false, forKey: "autoPlayNext")
        defaults.set(["autoPlayNext": "false"], forKey: SettingsSyncEngine.lastSyncedKey(profile: profile))
        let change = RemoteSettingsChange(profile: profile, deviceName: "TV", updatedAt: .now, values: [:], cleared: ["autoPlayNext"])
        SettingsSyncEngine.answer(change, useThem: true, defaults: defaults)
        #expect(defaults.object(forKey: "autoPlayNext") == nil)
        #expect(!SettingsSyncEngine.hasLocalChanges(profile: profile, defaults: defaults))
    }

    @Test("A question still waiting isn't lost to a later sync, but a newer one replaces it")
    func pendingSurvivesSyncs() {
        let old = RemoteSettingsChange(profile: "a", deviceName: "TV", updatedAt: Date(timeIntervalSince1970: 1), values: ["skipIntro": "true"])
        let newer = RemoteSettingsChange(profile: "a", deviceName: "Mac", updatedAt: Date(timeIntervalSince1970: 2), values: ["skipCredits": "true"])
        #expect(SettingsSyncEngine.stillPending(old, found: nil, profile: "a") == old)
        #expect(SettingsSyncEngine.stillPending(old, found: newer, profile: "a") == newer)
        #expect(SettingsSyncEngine.stillPending(old, found: nil, profile: "b") == nil)
    }

    @Test("A question still waiting is kept through a relaunch, and answering it forgets it")
    func pendingIsKept() {
        let profile = UUID().uuidString
        let change = RemoteSettingsChange(profile: profile, deviceName: "TV", updatedAt: Date(timeIntervalSince1970: 100),
                                          values: ["skipIntro": "true"], cleared: ["autoPlayNext"])
        SettingsSyncEngine.savePending(change, profile: profile, defaults: defaults)
        #expect(SettingsSyncEngine.savedPending(profile: profile, defaults: defaults) == change)
        #expect(SettingsSyncEngine.savedPending(profile: UUID().uuidString, defaults: defaults) == nil)
        SettingsSyncEngine.answer(change, useThem: false, defaults: defaults)
        #expect(SettingsSyncEngine.savedPending(profile: profile, defaults: defaults) == nil)
    }

    @Test("What Keep This Device's turned down isn't offered again until the other device changes it")
    func declinedIsntOfferedAgain() {
        let profile = UUID().uuidString
        let change = RemoteSettingsChange(profile: profile, deviceName: "TV", updatedAt: .now,
                                          values: ["skipIntro": "true"], cleared: ["autoPlayNext"])
        SettingsSyncEngine.answer(change, useThem: false, defaults: defaults)
        let declined = SettingsSyncEngine.declined(profile: profile, defaults: defaults)

        let again = SettingsSyncEngine.offer(["skipIntro": "true", "skipCredits": "true"], cleared: ["autoPlayNext"],
                                             declined: declined)
        #expect(again.values == ["skipCredits": "true"])
        #expect(again.cleared.isEmpty)

        // Changed on the other device since: offered, and the old answer is forgotten.
        let changed = SettingsSyncEngine.offer(["skipIntro": "false"], cleared: [], declined: declined)
        #expect(changed.values == ["skipIntro": "false"])
        #expect(changed.declined == DeclinedSettings())
    }

    // MARK: Size limits

    @Test("A value longer than the server keeps isn't sent, and isn't cleared either")
    func tooLongStaysHere() {
        let long = String(repeating: "x", count: SettingsSyncEngine.maxValueLength + 1)
        #expect(SettingsSyncEngine.withinServerLimits(["a": long, "b": "short"]) == ["b": "short"])
        let result = SettingsSyncEngine.merge(local: ["homeShelfOrder": long], remote: [:], base: ["homeShelfOrder": long],
                                              locked: [], canClearOnServer: true)
        #expect(result == SettingsSyncEngine.MergeResult())
        let replace = SettingsSyncEngine.replacePayload(local: ["homeShelfOrder": long], remote: ["homeShelfOrder": "a,b"],
                                                        platform: "iOS", locked: [])
        #expect(replace["homeShelfOrder"] == "a,b")
    }

    // MARK: Using another device's settings

    @Test("Another device's settings replace this one's, but only what that device shows")
    func replacement() {
        let local = ["skipIntro": "false", "autoPlayNext": "false", "wifiOnly": "false", "seerrURL": "https://a"]
        let source = ["skipIntro": "true"]
        let result = SettingsSyncEngine.replacement(source: source, sourcePlatform: "tvOS", local: local, locked: [])
        #expect(result.set == ["skipIntro": "true"])
        // Shown on Apple TV but not set there: back to the default.
        #expect(result.clear.contains("autoPlayNext"))
        // Downloads aren't on Apple TV, and the Seerr sign-in never goes.
        #expect(!result.clear.contains("wifiOnly"))
        #expect(!result.clear.contains("seerrURL"))
    }

    @Test("A setting Use These Settings Here clears is then cleared on the server, not taken back from it")
    func useSettingsClearsOnServer() {
        let profile = UUID().uuidString
        defaults.set(false, forKey: "autoPlayNext")
        defaults.set(true, forKey: "skipIntro")
        let agreed = ["autoPlayNext": "false", "skipIntro": "true"]
        defaults.set(agreed, forKey: SettingsSyncEngine.lastSyncedKey(profile: profile))
        let tv = ArcfinSyncDevice(deviceId: "tv", name: "TV", platform: "tvOS", settings: ["skipIntro": "true"])
        SettingsSyncEngine.useSettings(of: tv, profile: profile, defaults: defaults)
        #expect(defaults.object(forKey: "autoPlayNext") == nil)

        let local = SettingsSyncEngine.collectLocalPayload(defaults: defaults).settings
        let result = SettingsSyncEngine.merge(local: local, remote: agreed, base: agreed, locked: [], canClearOnServer: true)
        #expect(result.clearOnServer == ["autoPlayNext"])
        #expect(result.apply.isEmpty)
    }

    @Test("An iPad's settings count as iOS's")
    func iPadIsIOS() {
        let result = SettingsSyncEngine.replacement(source: [:], sourcePlatform: "iPadOS", local: ["wifiOnly": "false"], locked: [])
        #expect(result.clear == ["wifiOnly"])
    }

    @Test("Locked settings and device settings are never replaced")
    func replacementSkipsLockedAndDevice() {
        let result = SettingsSyncEngine.replacement(
            source: ["skipIntro": "true", "codecAllowHEVCDirectPlay": "false"], sourcePlatform: "iOS",
            local: ["skipIntro": "false", "codecAllowHEVCDirectPlay": "true"], locked: ["skipIntro"])
        #expect(result.set.isEmpty)
        #expect(result.clear.isEmpty)
    }

    @Test("Sending from Apple TV keeps what it doesn't show, and the Seerr sign-in")
    func replacePayload() {
        let values = SettingsSyncEngine.replacePayload(
            local: ["skipIntro": "true"],
            remote: ["wifiOnly": "false", "autoPlayNext": "false", "seerrURL": "https://a", "skipCredits": "true"],
            platform: "tvOS", locked: ["skipCredits"])
        #expect(values == ["skipIntro": "true", "wifiOnly": "false", "seerrURL": "https://a"])
    }

    // MARK: Snapshot and device policy

    @Test("A device's snapshot has only schema settings, never secrets or private state")
    func snapshotLeavesOutExcluded() {
        defaults.set(true, forKey: "skipIntro")
        defaults.set(false, forKey: "codecAllowHEVCDirectPlay")
        defaults.set("automatic", forKey: SettingsSyncMode.key)
        for key in ["arcfin.deviceId", "seerrPassword", "recentSearches", "homeShelfKnown", "offlineModeEnabled", "lastPlaybackRate",
                    "arcfin.activeProfileID", "bottomNavProfile", "arcfin.introduction.onboardingSeen"] {
            defaults.set("x", forKey: key)
        }
        let snapshot = SettingsSyncEngine.snapshot(defaults: defaults)
        #expect(snapshot == ["skipIntro": "true", "codecAllowHEVCDirectPlay": "false", "settingsSyncMode": "automatic"])
        #expect(SettingsSyncEngine.snapshot(scope: .device, defaults: defaults).keys.sorted()
                == ["codecAllowHEVCDirectPlay", "settingsSyncMode"])
    }

    @Test("A device lock always applies; a device default only where nothing is set")
    func devicePolicy() {
        let settings = [
            ArcfinSyncSetting(key: "codecAllowHEVCDirectPlay", value: "false", isLocked: true, source: .locked),
            ArcfinSyncSetting(key: "codecCompatibilityMode", value: "true", isLocked: false, source: .default),
            ArcfinSyncSetting(key: "codecForceHDRTranscode", value: "true", isLocked: false, source: .default),
            ArcfinSyncSetting(key: "skipIntro", value: "true", isLocked: true, source: .locked),
        ]
        let result = SettingsSyncEngine.devicePolicy(settings, local: ["codecAllowHEVCDirectPlay": "true",
                                                                       "codecForceHDRTranscode": "false"])
        #expect(result.apply == ["codecAllowHEVCDirectPlay": "false", "codecCompatibilityMode": "true"])
        #expect(result.locked == ["codecAllowHEVCDirectPlay"])
    }

    @Test("Writing typed values follows the schema")
    func writesTyped() {
        SettingsSyncEngine.write(["skipForwardSeconds": "30", "codecAllowHEVCDirectPlay": "false", "videoQuality": "auto",
                                  "arcfin.deviceId": "nope"], clearing: ["skipIntro"], schema: .bundled, defaults: defaults)
        #expect(defaults.integer(forKey: "skipForwardSeconds") == 30)
        #expect(defaults.object(forKey: "codecAllowHEVCDirectPlay") as? Bool == false)
        #expect(defaults.string(forKey: "videoQuality") == "auto")
        #expect(defaults.object(forKey: "arcfin.deviceId") == nil)
    }

    @Test("Doubles and JSON settings go over the wire and back as they're stored")
    func doublesAndJSON() {
        defaults.set(1.25, forKey: "defaultPlaybackSpeed")
        defaults.set(Data(#"[{"id":8}]"#.utf8), forKey: "streamingServices")
        let snapshot = SettingsSyncEngine.snapshot(defaults: defaults)
        #expect(snapshot["defaultPlaybackSpeed"] == "1.25")
        #expect(snapshot["streamingServices"] == #"[{"id":8}]"#)

        SettingsSyncEngine.write(["defaultPlaybackSpeed": "1.5", "streamingServices": #"[]"#, "holdSpeedRate": "fast"], schema: .bundled, defaults: defaults)
        #expect(defaults.double(forKey: "defaultPlaybackSpeed") == 1.5)
        #expect(defaults.data(forKey: "streamingServices") == Data("[]".utf8))
        #expect(defaults.object(forKey: "holdSpeedRate") == nil)
    }

    @Test("A setting that newly syncs keeps this device's value at the first sync, even against a server default")
    func newlySyncedKeepsLocal() {
        let result = SettingsSyncEngine.merge(
            local: ["statsPeriod": "year", "skipIntro": "true"],
            remote: ["statsPeriod": "month", "skipIntro": "true", "libraryGridDensity": "compact"],
            base: ["skipIntro": "true"], locked: [])
        #expect(result.push == ["statsPeriod": "year"])
        #expect(result.apply == ["libraryGridDensity": "compact"])
    }

    @Test("Sync mode defaults to automatic, exactly as before")
    func modeDefault() {
        #expect(SettingsSyncMode.current(defaults: defaults) == .automatic)
        defaults.set("ask", forKey: SettingsSyncMode.key)
        #expect(SettingsSyncMode.current(defaults: defaults) == .ask)
        defaults.set("nonsense", forKey: SettingsSyncMode.key)
        #expect(SettingsSyncMode.current(defaults: defaults) == .automatic)
    }
}
