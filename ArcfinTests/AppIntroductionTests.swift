// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Testing
import SyncEngine
@testable import Arcfin

@MainActor
struct AppIntroductionTests {
    private let defaults: UserDefaults

    init() {
        let suite = "AppIntroductionTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    @Test func freshInstallShowsTheTour() {
        #expect(AppIntroduction(defaults: defaults).presentation == .onboarding)
    }

    @Test func finishingTheTourAlsoCountsThisVersionsNewsAsSeen() {
        AppIntroduction(defaults: defaults).finishOnboarding()
        #expect(AppIntroduction(defaults: defaults).presentation == nil)
    }

    @Test func updatingFromBeforeTheTourShowsWhatsNew() {
        defaults.set(UUID().uuidString, forKey: "arcfin.activeProfileID")
        #expect(AppIntroduction(defaults: defaults).presentation == .whatsNew)
    }

    @Test func whatsNewStaysAwayOnceDismissed() {
        defaults.set(UUID().uuidString, forKey: "arcfin.activeProfileID")
        AppIntroduction(defaults: defaults).finishWhatsNew()
        #expect(AppIntroduction(defaults: defaults).presentation == nil)
    }

    @Test func raisingAVersionShowsItAgain() {
        defaults.set(AppIntroduction.onboardingVersion, forKey: AppIntroduction.onboardingKey)
        defaults.set(AppIntroduction.whatsNewVersion - 1, forKey: AppIntroduction.whatsNewKey)
        #expect(AppIntroduction(defaults: defaults).presentation == .whatsNew)

        defaults.set(AppIntroduction.onboardingVersion - 1, forKey: AppIntroduction.onboardingKey)
        #expect(AppIntroduction(defaults: defaults).presentation == .onboarding)
    }

    @Test func settingsCanShowEitherAgain() {
        let introduction = AppIntroduction(defaults: defaults)
        introduction.finishOnboarding()
        introduction.showWhatsNew()
        #expect(introduction.presentation == .whatsNew)
        introduction.showOnboarding()
        #expect(introduction.presentation == .onboarding)
    }

    @Test func seenFlagsStayOnThisDevice() {
        #expect(!SettingsSyncRegistry.allKeys.contains(AppIntroduction.onboardingKey))
        #expect(!SettingsSyncRegistry.allKeys.contains(AppIntroduction.whatsNewKey))
    }
}

struct WhoIsWatchingTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let isOn: Bool
        let profileCount: Int
        let isColdLaunch: Bool
        let minutesAway: Double
        let isPlayerOpen: Bool
        let isMusicPlaying: Bool
        let asks: Bool

        var testDescription: String {
            "on \(isOn), \(profileCount) profiles, \(isColdLaunch ? "cold launch" : "\(minutesAway) min away"), player \(isPlayerOpen), music \(isMusicPlaying)"
        }
    }

    @Test(arguments: [
        Case(isOn: true, profileCount: 2, isColdLaunch: true, minutesAway: 0, isPlayerOpen: false, isMusicPlaying: false, asks: true),
        Case(isOn: true, profileCount: 3, isColdLaunch: true, minutesAway: 0, isPlayerOpen: false, isMusicPlaying: false, asks: true),
        Case(isOn: false, profileCount: 2, isColdLaunch: true, minutesAway: 0, isPlayerOpen: false, isMusicPlaying: false, asks: false),
        Case(isOn: true, profileCount: 1, isColdLaunch: true, minutesAway: 0, isPlayerOpen: false, isMusicPlaying: false, asks: false),
        Case(isOn: true, profileCount: 0, isColdLaunch: true, minutesAway: 0, isPlayerOpen: false, isMusicPlaying: false, asks: false),
        Case(isOn: true, profileCount: 2, isColdLaunch: false, minutesAway: 30, isPlayerOpen: false, isMusicPlaying: false, asks: true),
        Case(isOn: true, profileCount: 2, isColdLaunch: false, minutesAway: 120, isPlayerOpen: false, isMusicPlaying: false, asks: true),
        Case(isOn: true, profileCount: 2, isColdLaunch: false, minutesAway: 29.9, isPlayerOpen: false, isMusicPlaying: false, asks: false),
        Case(isOn: true, profileCount: 2, isColdLaunch: false, minutesAway: 0, isPlayerOpen: false, isMusicPlaying: false, asks: false),
        Case(isOn: true, profileCount: 2, isColdLaunch: false, minutesAway: 45, isPlayerOpen: true, isMusicPlaying: false, asks: false),
        Case(isOn: true, profileCount: 2, isColdLaunch: false, minutesAway: 45, isPlayerOpen: false, isMusicPlaying: true, asks: false),
        Case(isOn: false, profileCount: 2, isColdLaunch: false, minutesAway: 45, isPlayerOpen: false, isMusicPlaying: false, asks: false),
        Case(isOn: true, profileCount: 1, isColdLaunch: false, minutesAway: 45, isPlayerOpen: false, isMusicPlaying: false, asks: false),
    ])
    func shouldAsk(_ c: Case) {
        #expect(WhoIsWatching.shouldAsk(isOn: c.isOn, profileCount: c.profileCount, isColdLaunch: c.isColdLaunch,
                                        secondsAway: c.minutesAway * 60, isPlayerOpen: c.isPlayerOpen,
                                        isMusicPlaying: c.isMusicPlaying) == c.asks)
    }

    @Test func settingStaysOnThisDevice() {
        #expect(!SettingsSyncRegistry.allKeys.contains(WhoIsWatching.settingKey))
        #expect(!ProfileSettings.keys.contains(WhoIsWatching.settingKey))
    }
}
