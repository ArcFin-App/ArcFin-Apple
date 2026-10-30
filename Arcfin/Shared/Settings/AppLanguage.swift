// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// An in-app choice writes AppleLanguages into Arcfin's own defaults, the same key the
/// system's per-app language setting uses; Foundation reads it at launch.
enum AppLanguage {
    private static let key = "AppleLanguages"

    static let available = Bundle.main.localizations
        .filter { $0 != "Base" }
        .sorted { name(of: $0).localizedStandardCompare(name(of: $1)) == .orderedAscending }

    static var isChoosable: Bool { available.count > 1 }

    /// The choice this launch is running with, so a change can say it applies next time.
    static let atLaunch = override ?? ""

    static var override: String? {
        get {
            let domain = Bundle.main.bundleIdentifier.flatMap(UserDefaults.standard.persistentDomain(forName:))
            return (domain?[key] as? [String])?.first.flatMap { available.contains($0) ? $0 : nil }
        }
        set {
            if let newValue { UserDefaults.standard.set([newValue], forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
    }

    /// Each language in its own words, as language pickers show them.
    static func name(of code: String) -> String {
        let locale = Locale(identifier: code)
        return locale.localizedString(forIdentifier: code)?.capitalized(with: locale) ?? code
    }
}
