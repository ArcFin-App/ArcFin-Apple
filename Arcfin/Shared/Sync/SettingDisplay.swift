// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import SyncEngine

/// Words for the schema's settings. The schema's titles are English; a title the app's own
/// Settings already uses comes back in the app's language from the String Catalog.
enum SettingDisplay {
    static func title(_ setting: SettingsSchema.Setting) -> String {
        localized(setting.title)
    }

    static func groupTitle(_ group: SettingsSchema.Group) -> String {
        localized(group.title)
    }

    static func value(_ value: String?, of setting: SettingsSchema.Setting) -> String {
        guard let value else { return String(localized: "Default") }
        switch setting.type {
        case .bool:
            return value == "true" ? String(localized: "On") : String(localized: "Off")
        case .int, .string:
            if let option = setting.optionTitle(for: value) { return localized(option) }
            return value.isEmpty ? String(localized: "None") : value
        }
    }

    static func platformImage(_ platform: String) -> String {
        switch platform {
        case "iPadOS": "ipad"
        case "macOS": "laptopcomputer"
        case "tvOS": "appletv"
        default: "iphone"
        }
    }

    static func platformName(_ platform: String) -> String {
        switch platform {
        case "iPadOS": "iPad"
        case "macOS": "Mac"
        case "tvOS": "Apple TV"
        case "iOS": "iPhone"
        default: platform
        }
    }

    static func syncMode(_ raw: String) -> String {
        (SettingsSyncMode(rawValue: raw) ?? .automatic).title
    }

    private static func localized(_ english: String) -> String {
        String(localized: String.LocalizationValue(english))
    }
}

extension SettingsSyncMode {
    var title: String {
        switch self {
        case .automatic: String(localized: "Automatically")
        case .ask: String(localized: "Ask First")
        case .off: String(localized: "Off")
        }
    }
}
