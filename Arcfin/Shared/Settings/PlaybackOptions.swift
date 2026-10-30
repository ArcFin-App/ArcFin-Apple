// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

enum VideoQuality: String, CaseIterable, Identifiable {
    case max = "Max", auto, p4k = "4K", p1080 = "1080p", p720 = "720p", p480 = "480p"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .max:   String(localized: "Max Quality")
        case .auto:  String(localized: "Auto (Recommended)")
        case .p4k:   String(localized: "4K Ultra HD")
        case .p1080: String(localized: "1080p HD")
        case .p720:  String(localized: "720p")
        case .p480:  String(localized: "480p")
        }
    }
    /// Source pixel height this tier requires — nil for Auto/Max, which have no fixed
    /// resolution floor. Used to hide tiers the current item's source can't actually supply
    /// (no point offering 4K for a 1080p source).
    var minSourceHeight: Int? {
        switch self {
        case .max, .auto: nil
        case .p4k:   2160
        case .p1080: 1080
        case .p720:  720
        case .p480:  480
        }
    }
}

/// Settings › Playback › When Resuming: what Play does for a title that's part-watched.
enum ResumeBehavior: String, CaseIterable, Identifiable {
    case ask, resume, startOver
    static let key = "resumeBehavior"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .ask: String(localized: "Ask")
        case .resume: String(localized: "Resume")
        case .startOver: String(localized: "Start Over")
        }
    }
    static var current: ResumeBehavior {
        ResumeBehavior(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .resume
    }
}

/// Settings › Playback › Mark as Watched: how far in closing the player counts as finished.
enum WatchedThreshold: String, CaseIterable, Identifiable {
    case server, credits, eighty, eightyFive
    static let key = "markWatchedAt"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .server: String(localized: "Server Default")
        case .credits: String(localized: "When Credits Start")
        case .eighty: String(localized: "At \(0.8.formatted(.percent))")
        case .eightyFive: String(localized: "At \(0.85.formatted(.percent))")
        }
    }
    static var current: WatchedThreshold {
        WatchedThreshold(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .server
    }

    /// Whether stopping at `seconds` of `duration` counts, given where the credits start.
    func isReached(seconds: Double, duration: Double, creditsStart: Double?) -> Bool {
        guard duration > 0 else { return false }
        switch self {
        case .server: return false
        case .credits: return seconds >= (creditsStart ?? duration * 0.95)
        case .eighty: return seconds / duration >= 0.8
        case .eightyFive: return seconds / duration >= 0.85
        }
    }
}
