// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// Free space on the device.
enum PlatformStorage {
    /// Apple TV doesn't keep music downloads.
    static let keepsMusicDownloads = false

    /// Apple TV has no measure that includes space the system can clear, so this is what's
    /// free right now.
    static func freeBytes(at url: URL) -> Int64? {
        (try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey]))?.volumeAvailableCapacity.map(Int64.init)
    }
}
