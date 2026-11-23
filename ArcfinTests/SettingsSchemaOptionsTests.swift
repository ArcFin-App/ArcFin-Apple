// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Testing
import MediaEngine
import SeerrAPI
import JellyfinAPI
import SyncEngine
@testable import Arcfin

/// The schema's options are the values the app's pickers really store.
@MainActor
struct SettingsSchemaOptionsTests {
    private func values(_ key: String) -> [String] {
        SettingsSchema.bundled.setting(key)?.options?.map(\.value) ?? []
    }

    @Test func stringPickersMatchTheirEnums() {
        #expect(values("videoQuality") == VideoQuality.allCases.map(\.rawValue))
        #expect(values("mobileVideoQuality") == [""] + VideoQuality.allCases.map(\.rawValue))
        #expect(values("downloadQuality") == DownloadQuality.allCases.map(\.rawValue))
        #expect(values("resumeBehavior") == ResumeBehavior.allCases.map(\.rawValue))
        #expect(values("markWatchedAt") == WatchedThreshold.allCases.map(\.rawValue))
        #expect(values("homeEpisodeArtwork") == HomeEpisodeArtwork.allCases.map(\.rawValue))
        #expect(values("subtitleTextSize") == SubtitleTextSize.allCases.map(\.rawValue))
        #expect(values("subtitleTextColor") == SubtitleTextColorOption.allCases.map(\.rawValue))
        #expect(values("subtitleBackgroundStyle") == SubtitleBackgroundStyle.allCases.map(\.rawValue))
        #expect(values("musicStreamQuality") == MusicQuality.allCases.map(\.rawValue))
        #expect(values("musicMobileStreamQuality") == [""] + MusicQuality.allCases.map(\.rawValue))
        #expect(values("musicDownloadQuality") == MusicQuality.allCases.map(\.rawValue))
        #expect(values("musicEqualizer") == MusicEqualizer.allCases.map(\.rawValue))
        #expect(values("playbackEngine") == PlaybackEngineKind.allCases.map(\.rawValue))
        #expect(values("seerrAuthMethod") == SeerrAuthMethod.allCases.map(\.rawValue))
        #expect(values("settingsSyncMode") == SettingsSyncMode.allCases.map(\.rawValue))
        #expect(values("libraryGridDensity") == LibraryGridDensity.allCases.map(\.rawValue))
        #expect(values("collectionSort") == CollectionSort.allCases.map(\.rawValue))
        #expect(values("statsPeriod") == StatsPeriod.allCases.map(\.rawValue))
        #expect(values("music.songSort") == MusicSort.allCases.map(\.rawValue))
        #expect(values("music.albumSort") == MusicSort.allCases.map(\.rawValue))
        #expect(values("launchTab") == BottomNavItem.allCases.map(\.rawValue))
    }

    @Test func numberPickersMatchTheirLists() {
        #expect(values("skipForwardSeconds") == skipIntervalOptions.map(String.init))
        #expect(values("skipBackwardSeconds") == skipIntervalOptions.map(String.init))
        #expect(values("musicCrossfadeSeconds") == MusicSettings.crossfadeOptions.map(String.init))
        #expect(values("musicKeepRecentCount") == MusicSettings.keepRecentOptions.map(String.init))
        #expect(values("musicStorageLimitGB") == MusicSettings.storageLimitOptions.map(String.init))
        #expect(values("subtitleReachLater") == PlayerModel.subtitleReachOptions.map(String.init))
        #expect(values("subtitleReachEarlier") == PlayerModel.subtitleReachOptions.map(String.init))
        #expect(values("holdSpeedRate") == PlayerModel.holdSpeedOptions.map { String(Double($0)) })
    }

    /// Devices & Sync and Arcfin for Everyone show the schema's titles and options through the
    /// String Catalog, so each has a translation.
    @Test func schemaTextIsTranslated() throws {
        let schema = SettingsSchema.bundled
        let texts = Set(schema.groups.map(\.title) + schema.settings.flatMap { [$0.title] + ($0.options ?? []).map(\.title) })
        let app = Bundle(for: AuthManager.self)
        let german = try #require(app.path(forResource: "de", ofType: "lproj").flatMap(Bundle.init(path:)))
        let untranslated = texts.filter { german.localizedString(forKey: $0, value: "\u{0}", table: nil) == "\u{0}" }
        #expect(untranslated.isEmpty, "\(untranslated.sorted())")
    }
}
