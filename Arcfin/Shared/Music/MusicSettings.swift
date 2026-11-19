// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import MediaEngine

/// How music streams or downloads: the file as it is, or converted to MP3 at a rate.
enum MusicQuality: String, CaseIterable, Identifiable {
    case original, high = "320", good = "256", standard = "192", low = "128"

    var id: String { rawValue }

    var bitrate: Int? { self == .original ? nil : Int(rawValue).map { $0 * 1000 } }

    var label: String {
        self == .original ? String(localized: "Original") : String(localized: "\(rawValue) kbps")
    }
}

/// Settings › Music's keys, and what they come to now.
enum MusicSettings {
    static let visualizerKey = "musicVisualizer"
    static let visualizerTintKey = "musicVisualizerTint"
    static let streamQualityKey = "musicStreamQuality"
    /// Empty: the same as on Wi-Fi.
    static let mobileStreamQualityKey = "musicMobileStreamQuality"
    static let downloadQualityKey = "musicDownloadQuality"
    static let downloadOnMobileDataKey = "musicDownloadOnMobileData"
    static let soundCheckKey = "musicSoundCheck"
    static let equalizerKey = "musicEqualizer"
    static let crossfadeKey = "musicCrossfadeSeconds"
    static let autoplayKey = "musicAutoplay"
    static let rememberQueueKey = "musicRememberQueue"
    static let keepFavoritesDownloadedKey = "musicKeepFavoritesDownloaded"
    static let keepRecentCountKey = "musicKeepRecentCount"
    static let downloadNewAlbumsKey = "musicDownloadNewAlbums"
    static let storageLimitKey = "musicStorageLimitGB"
    static let keepRecentOptions = [0, 25, 50, 100, 200]
    static let storageLimitOptions = [0, 1, 2, 5, 10, 20, 50]
    static let notifyDownloadsKey = "musicNotifyDownloads"
    static let findsLyricsOnlineKey = "musicFindLyricsOnline"

    static var findsLyricsOnline: Bool { defaults.bool(forKey: findsLyricsOnlineKey) }

    static var notifiesDownloads: Bool { defaults.object(forKey: notifyDownloadsKey) as? Bool ?? true }

    /// Off where music isn't downloaded, even when the setting arrives synced from elsewhere.
    static var keepsFavoritesDownloaded: Bool {
        PlatformStorage.keepsMusicDownloads && defaults.bool(forKey: keepFavoritesDownloadedKey)
    }

    /// How many of the songs played last stay downloaded; 0 for none.
    static var keepRecentCount: Int {
        PlatformStorage.keepsMusicDownloads ? defaults.integer(forKey: keepRecentCountKey) : 0
    }

    static var downloadsNewAlbums: Bool {
        PlatformStorage.keepsMusicDownloads && defaults.bool(forKey: downloadNewAlbumsKey)
    }

    /// The most music downloads may take, nil for no limit.
    static var storageLimitBytes: Int64? {
        let gigabytes = defaults.integer(forKey: storageLimitKey)
        return gigabytes > 0 ? Int64(gigabytes) * 1_000_000_000 : nil
    }

    static var isAutoplayOn: Bool { defaults.object(forKey: autoplayKey) as? Bool ?? true }
    static var remembersQueue: Bool { defaults.object(forKey: rememberQueueKey) as? Bool ?? true }
    static let crossfadeOptions = [0, 1, 2, 3, 4, 5, 6, 8, 10, 12]

    private static var defaults: UserDefaults { .standard }

    private static func quality(_ key: String) -> MusicQuality? {
        defaults.string(forKey: key).flatMap(MusicQuality.init(rawValue:))
    }

    /// The cap for a song streamed now, nil for the file as it is.
    static var streamBitrate: Int? {
        let wifi = quality(streamQualityKey) ?? .original
        guard DownloadManager.isOnMobileDataNow else { return wifi.bitrate }
        return (quality(mobileStreamQualityKey) ?? wifi).bitrate
    }

    static var downloadBitrate: Int? { (quality(downloadQualityKey) ?? .original).bitrate }

    static var downloadsWaitForWiFi: Bool {
        !defaults.bool(forKey: downloadOnMobileDataKey) && DownloadManager.isOnMobileDataNow
    }
}

extension MusicEqualizer {
    var label: String {
        switch self {
        case .off: String(localized: "Off")
        case .bassBooster: String(localized: "Bass Booster")
        case .bassReducer: String(localized: "Bass Reducer")
        case .trebleBooster: String(localized: "Treble Booster")
        case .trebleReducer: String(localized: "Treble Reducer")
        case .vocalBooster: String(localized: "Vocal Booster")
        case .loudness: String(localized: "Loudness")
        case .smallSpeakers: String(localized: "Small Speakers")
        }
    }
}
