// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// Free space on the device.
enum PlatformStorage {
    /// Whether music can be saved here for listening offline.
    static let keepsMusicDownloads = true

    /// As the system's storage screen counts it: including what the system clears on demand
    /// (caches, offloadable data), which plain available capacity leaves out.
    static func freeBytes(at url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? values?.volumeAvailableCapacity.map(Int64.init)
    }
}
