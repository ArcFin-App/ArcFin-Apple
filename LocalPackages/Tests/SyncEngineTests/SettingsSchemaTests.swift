// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Testing
@testable import SyncEngine

@Suite("Settings schema")
struct SettingsSchemaTests {
    private let schema = SettingsSchema.bundled

    @Test("The synced settings are exactly the registry's, with the same types")
    func syncedMatchesRegistry() {
        let synced = Dictionary(uniqueKeysWithValues: schema.settings.filter { $0.scope == .synced }.map { ($0.key, $0.type) })
        let registry = Dictionary(uniqueKeysWithValues: SettingsSyncRegistry.entries.map { ($0.key, $0.type) })
        #expect(synced == registry)
    }

    @Test("Each key is listed once")
    func keysAreUnique() {
        #expect(Set(schema.settings.map(\.key)).count == schema.settings.count)
    }

    @Test("No setting kept on each profile alone is in the schema")
    func localKeysAreLeftOut() {
        #expect(schema.allKeys.isDisjoint(with: ProfileSettings.localKeys))
    }

    @Test("Every setting has a title, a known group and somewhere it's shown")
    func titlesAndGroups() {
        let groups = Set(schema.groups.map(\.id))
        for setting in schema.settings {
            #expect(!setting.title.isEmpty, "\(setting.key)")
            #expect(groups.contains(setting.group), "\(setting.key)")
            #expect(Set(setting.platforms).isSubset(of: ["iOS", "macOS", "tvOS"]), "\(setting.key)")
        }
    }

    @Test("Options have titles, no repeats, and include the default")
    func options() {
        for setting in schema.settings {
            guard let options = setting.options else { continue }
            #expect(!options.isEmpty, "\(setting.key)")
            #expect(Set(options.map(\.value)).count == options.count, "\(setting.key)")
            #expect(options.allSatisfy { !$0.title.isEmpty }, "\(setting.key)")
            if let value = setting.default { #expect(options.contains { $0.value == value }, "\(setting.key)") }
            if setting.type == .int { #expect(options.allSatisfy { Int($0.value) != nil }, "\(setting.key)") }
            #expect(setting.type != .bool, "\(setting.key)")
        }
    }

    @Test("Defaults are in each type's wire format")
    func defaults() {
        for setting in schema.settings {
            guard let value = setting.default else { continue }
            switch setting.type {
            case .bool: #expect(value == "true" || value == "false", "\(setting.key)")
            case .int: #expect(Int(value) != nil, "\(setting.key)")
            case .string: break
            }
        }
    }

    @Test("String settings that pick from a list say what's in it")
    func enumsHaveOptions() {
        let enums = ["videoQuality", "mobileVideoQuality", "playbackEngine", "resumeBehavior", "markWatchedAt",
                     "playerOpeningOrientation", "subtitleTextSize", "subtitleTextColor", "subtitleBackgroundStyle",
                     "musicEqualizer", "musicStreamQuality", "musicMobileStreamQuality", "musicDownloadQuality",
                     "downloadQuality", "downloadSubtitles", "homeEpisodeArtwork", "seerrAuthMethod", "settingsSyncMode",
                     "preferredAudioLanguage", "preferredSubtitleLanguage"]
        for key in enums {
            #expect(schema.setting(key)?.options?.isEmpty == false, "\(key)")
        }
    }

    @Test("A server's PascalCase copy decodes the same")
    func pascalCase() throws {
        let json = #"{"Version":1,"Groups":[{"Id":"playback","Title":"Playback"}],"Settings":[{"Key":"skipIntro","Type":"bool","Scope":"synced","Group":"playback","Title":"Skip Intro Automatically","Default":"false","Platforms":["iOS"]}]}"#
        let decoded = try SettingsSchema.decode(Data(json.utf8))
        #expect(decoded.settings.first?.key == "skipIntro")
        #expect(decoded.settings.first?.type == .bool)
    }
}
