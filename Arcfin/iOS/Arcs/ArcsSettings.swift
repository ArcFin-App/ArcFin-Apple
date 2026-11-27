// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// Settings › Arcs, and what the feed reads from it.
enum ArcsSettings {
    static let watermarkKey = "arcsWatermark"
    static let spoilerSafeKey = "arcsSpoilerSafe"
    static let clipSecondsKey = "arcsClipSeconds"
    static let framingKey = "arcsFraming"
    static let clipEndKey = "arcsWhenClipEnds"
    static let showReasonsKey = "arcsShowReasons"
    static let subtitlesKey = "arcsSubtitles"
    static let dataSaverKey = "arcsDataSaver"
    static let clipOfTheDayKey = "arcsClipOfTheDay"
    static let preloadKey = "arcsPreload"
    static let showRequestsKey = "arcsShowRequests"
    static let youTubeTrailersKey = "arcsYouTubeTrailers"

    static let clipSecondsOptions = [15, 30, 45, 60]
}

/// How a scene that's wider than the screen fills it.
enum ArcsFraming: String, CaseIterable, Identifiable {
    case fill, blur, fit
    var id: String { rawValue }

    var label: LocalizedStringResource {
        switch self {
        case .fill: "Fill the Screen"
        case .blur: "Whole Picture, Blurred Behind"
        case .fit:  "Whole Picture"
        }
    }
}

enum ArcsClipEnd: String, CaseIterable, Identifiable {
    case loop, next
    var id: String { rawValue }

    var label: LocalizedStringResource {
        switch self {
        case .loop: "Play It Again"
        case .next: "Go to the Next One"
        }
    }
}

/// When clips come in at the lower quality, to use less data.
enum ArcsDataSaver: String, CaseIterable, Identifiable {
    case mobile, always, off
    var id: String { rawValue }

    var label: LocalizedStringResource {
        switch self {
        case .mobile: "On Mobile Data"
        case .always: "Always"
        case .off:    "Off"
        }
    }
}
