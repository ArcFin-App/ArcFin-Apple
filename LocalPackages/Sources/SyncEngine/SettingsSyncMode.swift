// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// How this device takes part in settings sync. Kept per device, never synced.
public enum SettingsSyncMode: String, Sendable, CaseIterable, Identifiable {
    /// Before plugin v2 this was the only behaviour, and it stays exactly the same.
    case automatic
    /// Settings changed on another device wait for a yes here.
    case ask
    /// Nothing is sent or taken, but admin locks still apply.
    case off

    public static let key = "settingsSyncMode"

    public var id: String { rawValue }

    public static func current(defaults: UserDefaults = .standard) -> SettingsSyncMode {
        defaults.string(forKey: key).flatMap(SettingsSyncMode.init(rawValue:)) ?? .automatic
    }
}
