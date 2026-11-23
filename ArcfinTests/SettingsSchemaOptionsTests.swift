// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Testing
import MediaEngine
import SeerrAPI
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
    }

    @Test func numberPickersMatchTheirLists() {
        #expect(values("skipForwardSeconds") == skipIntervalOptions.map(String.init))
        #expect(values("skipBackwardSeconds") == skipIntervalOptions.map(String.init))
        #expect(values("musicCrossfadeSeconds") == MusicSettings.crossfadeOptions.map(String.init))
        #expect(values("musicKeepRecentCount") == MusicSettings.keepRecentOptions.map(String.init))
        #expect(values("musicStorageLimitGB") == MusicSettings.storageLimitOptions.map(String.init))
        #expect(values("subtitleReachLater") == PlayerModel.subtitleReachOptions.map(String.init))
        #expect(values("subtitleReachEarlier") == PlayerModel.subtitleReachOptions.map(String.init))
    }
}
