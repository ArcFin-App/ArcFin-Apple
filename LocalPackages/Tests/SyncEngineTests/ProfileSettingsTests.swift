// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Testing
@testable import SyncEngine

@Suite("Settings per profile")
struct ProfileSettingsTests {
    private let defaults: UserDefaults

    init() {
        let name = "ProfileSettingsTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
    }

    @Test("Each profile keeps its own value through switches")
    func switching() {
        ProfileSettings.activate(profile: "A", profiles: ["A", "B"], defaults: defaults)
        defaults.set(false, forKey: "smartDownloadsEnabled")
        ProfileSettings.activate(profile: "B", profiles: ["A", "B"], defaults: defaults)
        // A's change stayed with A.
        #expect(defaults.object(forKey: "smartDownloadsEnabled") == nil)
        defaults.set(true, forKey: "smartDownloadsEnabled")
        ProfileSettings.activate(profile: "A", profiles: ["A", "B"], defaults: defaults)
        #expect(defaults.object(forKey: "smartDownloadsEnabled") as? Bool == false)
        ProfileSettings.activate(profile: "B", profiles: ["A", "B"], defaults: defaults)
        #expect(defaults.object(forKey: "smartDownloadsEnabled") as? Bool == true)
    }

    @Test("A profile added later starts at the defaults, not the last profile's settings")
    func newProfile() {
        ProfileSettings.activate(profile: "A", profiles: ["A"], defaults: defaults)
        defaults.set(false, forKey: "smartDownloadsEnabled")
        defaults.set(["one"], forKey: "hiddenLibraryIDs")
        ProfileSettings.activate(profile: "C", profiles: ["A", "C"], defaults: defaults)
        #expect(defaults.object(forKey: "smartDownloadsEnabled") == nil)
        #expect(defaults.object(forKey: "hiddenLibraryIDs") == nil)
    }

    @Test("The first time, the profile in use keeps what's there and the others start from what they last synced")
    func firstTime() {
        defaults.set(false, forKey: "smartDownloadsEnabled")
        defaults.set(10, forKey: "skipForwardSeconds")
        defaults.set(["smartDownloadsEnabled": "true", "seerrURL": "http://b"], forKey: "arcfin.settingsSync.lastSynced.B")
        ProfileSettings.activate(profile: "A", profiles: ["A", "B", "C"], defaults: defaults)
        #expect(defaults.object(forKey: "smartDownloadsEnabled") as? Bool == false)
        ProfileSettings.activate(profile: "B", profiles: ["A", "B", "C"], defaults: defaults)
        #expect(defaults.object(forKey: "smartDownloadsEnabled") as? Bool == true)
        #expect(defaults.integer(forKey: "skipForwardSeconds") == 10)
        // Seerr is swapped with its sign-in, not here.
        #expect(defaults.string(forKey: "seerrURL") == nil)
        ProfileSettings.activate(profile: "C", profiles: ["A", "B", "C"], defaults: defaults)
        #expect(defaults.object(forKey: "smartDownloadsEnabled") as? Bool == false)
    }

    @Test("After a switch there's nothing to send: the values are the profile's own")
    func nothingToPushAfterSwitch() {
        ProfileSettings.activate(profile: "A", profiles: ["A", "B"], defaults: defaults)
        defaults.set(true, forKey: "smartDownloadsEnabled")
        ProfileSettings.activate(profile: "B", profiles: ["A", "B"], defaults: defaults)
        defaults.set(true, forKey: "smartDownloadsEnabled")
        defaults.set(SettingsSyncEngine.collectLocalPayload(defaults: defaults).settings,
                     forKey: "arcfin.settingsSync.lastSynced.B")
        ProfileSettings.activate(profile: "A", profiles: ["A", "B"], defaults: defaults)
        defaults.set(false, forKey: "smartDownloadsEnabled")
        ProfileSettings.activate(profile: "B", profiles: ["A", "B"], defaults: defaults)
        #expect(!SettingsSyncEngine.hasLocalChanges(profile: "B", defaults: defaults))
    }

    @Test("A removed profile's settings aren't kept")
    func removed() {
        ProfileSettings.activate(profile: "A", profiles: ["A", "B"], defaults: defaults)
        defaults.set(false, forKey: "smartDownloadsEnabled")
        // A was removed, so it's no longer among the profiles.
        ProfileSettings.activate(profile: "B", profiles: ["B"], defaults: defaults)
        #expect(defaults.dictionary(forKey: "arcfin.profileSettings.A") == nil)
    }

    @Test("Every synced setting is each profile's; what describes the device isn't")
    func coverage() {
        let keys = Set(ProfileSettings.keys)
        for entry in SettingsSyncRegistry.entries {
            #expect(keys.contains(entry.key) || ProfileSettings.swappedWithSeerr.contains(entry.key), "\(entry.key)")
        }
        for deviceKey in ["codecAllowHEVCDirectPlay", "codecAllowSurroundAudioDirectPlay", "appLockUseFaceID",
                          "bottomNavOrder", "arcfin.introduction.onboardingSeen"] {
            #expect(!keys.contains(deviceKey))
        }
    }
}
