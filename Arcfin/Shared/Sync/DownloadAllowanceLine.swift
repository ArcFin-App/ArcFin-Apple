// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

/// The admin's download caps and how much of them is used on all the person's devices.
struct DownloadAllowanceLine: View {
    private var allowance: DownloadAllowance? {
        let companion = ServerCompanion.shared
        guard companion.has("downloadLimits"), let allowance = companion.downloadAllowance, allowance.limited else { return nil }
        return allowance
    }

    var body: some View {
        if let allowance, let text = Self.text(allowance) {
            Label(text, systemImage: "gauge.with.dots.needle.50percent")
                .font(.system(.caption))
                .foregroundStyle(DT.Color.textSecondary)
        }
    }

    static func text(_ allowance: DownloadAllowance) -> String? {
        var parts: [String] = []
        if let maxTitles = allowance.maxTitles {
            parts.append(String(localized: "\(allowance.usedTitles) of \(maxTitles) titles"))
        }
        if let maxBytes = allowance.maxBytes {
            let used = ByteCountFormatter.string(fromByteCount: allowance.usedBytes, countStyle: .file)
            let max = ByteCountFormatter.string(fromByteCount: maxBytes, countStyle: .file)
            parts.append(String(localized: "\(used) of \(max)"))
        }
        guard !parts.isEmpty else { return nil }
        return String(localized: "\(parts.joined(separator: " · ")) across your devices")
    }
}

/// The admin's music caps and how much of them is used on all the person's devices.
struct MusicAllowanceLine: View {
    var body: some View {
        let companion = ServerCompanion.shared
        if companion.has("downloadLimits"), let allowance = companion.downloadAllowance, allowance.musicLimited,
           let text = Self.text(allowance) {
            Label(text, systemImage: "gauge.with.dots.needle.50percent")
                .font(.caption)
                .foregroundStyle(DT.Color.textSecondary)
        }
    }

    static func text(_ allowance: DownloadAllowance) -> String? {
        var parts: [String] = []
        if let max = allowance.musicMaxAlbums { parts.append(String(localized: "\(allowance.musicUsedAlbums) of \(max) albums")) }
        if let max = allowance.musicMaxSongs { parts.append(String(localized: "\(allowance.musicUsedSongs) of \(max) songs")) }
        if let maxBytes = allowance.musicMaxBytes {
            let used = ByteCountFormatter.string(fromByteCount: allowance.musicUsedBytes, countStyle: .file)
            let max = ByteCountFormatter.string(fromByteCount: maxBytes, countStyle: .file)
            parts.append(String(localized: "\(used) of \(max)"))
        }
        guard !parts.isEmpty else { return nil }
        return String(localized: "\(parts.joined(separator: " · ")) across your devices")
    }
}
