// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

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
    static let streamQualityKey = "musicStreamQuality"
    /// Empty: the same as on Wi-Fi.
    static let mobileStreamQualityKey = "musicMobileStreamQuality"
    static let downloadQualityKey = "musicDownloadQuality"
    static let downloadOnMobileDataKey = "musicDownloadOnMobileData"

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
