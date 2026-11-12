// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import JellyfinAPI

/// A Jellyfin server version, such as 10.11.2.
struct ServerVersion: Comparable, Sendable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int

    init(_ major: Int, _ minor: Int, _ patch: Int = 0) {
        self.major = major; self.minor = minor; self.patch = patch
    }

    init?(_ text: String) {
        let parts = text.split(separator: ".").prefix(3).map { Int($0.prefix { $0.isNumber }) ?? 0 }
        guard parts.count >= 2 else { return nil }
        self.init(parts[0], parts[1], parts.count > 2 ? parts[2] : 0)
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    var description: String { "\(major).\(minor).\(patch)" }
}

/// Which Jellyfin versions the screens that post the server's own data back (settings, user
/// permissions, metadata, tags) were checked against, and from which version each setting or
/// choice exists. Anything a server is too old for is left out.
enum ServerCompatibility {
    static let oldestTested = ServerVersion(10, 9, 0)
    /// The newest release line checked; a later one is editable after a warning.
    static let newestTested = ServerVersion(10, 11, 999)

    enum Status: Equatable {
        case unknown
        /// Older than anything checked: the screens show the settings but don't save them.
        case tooOld(ServerVersion)
        case tested(ServerVersion)
        /// Newer than anything checked: saving asks first.
        case newer(ServerVersion)

        var canSave: Bool { if case .tooOld = self { false } else { true } }
        var needsConfirmation: Bool { if case .newer = self { true } else { false } }
    }

    static func status(_ version: ServerVersion?) -> Status {
        guard let version else { return .unknown }
        if version < oldestTested { return .tooOld(version) }
        if version > newestTested { return .newer(version) }
        return .tested(version)
    }

    /// The first Jellyfin release with each setting, or each choice of one ("key=value").
    /// Settings older than `oldestTested` aren't listed: no editable server lacks them.
    static let minimum: [String: ServerVersion] = [
        "AllowAv1Encoding": ServerVersion(10, 9),
        "LibraryScanFanoutConcurrency": ServerVersion(10, 9),
        "ParallelImageEncodingLimit": ServerVersion(10, 9),
        "EnableDecodingColorDepth10HevcRext": ServerVersion(10, 10),
        "EnableDecodingColorDepth12HevcRext": ServerVersion(10, 10),
        "HardwareAccelerationType=rkmpp": ServerVersion(10, 9),
        "EnableLyricManagement": ServerVersion(10, 9),
        "EnableCollectionManagement": ServerVersion(10, 9),
    ]

    static func allows(_ key: String, on version: ServerVersion?) -> Bool {
        guard let needed = minimum[key] else { return true }
        guard let version else { return false }
        return version >= needed
    }
}

/// The servers' versions, read once per address.
@MainActor
enum ServerVersions {
    private static var known: [URL: ServerVersion] = [:]

    static func version(for credential: ServerCredential) async -> ServerVersion? {
        if let version = known[credential.baseURL] { return version }
        guard let text = try? await JellyfinAdminClient().version(baseURL: credential.baseURL),
              let version = ServerVersion(text) else { return nil }
        known[credential.baseURL] = version
        return version
    }
}

/// Checks on JSON edited and posted back to the server: a value can only be replaced by one of
/// the same kind, and after saving, what the server kept is compared with what was sent.
enum ServerEditGuard {
    enum Kind: Equatable { case bool, number, string, array, object, null }

    static func kind(_ value: Any?) -> Kind {
        switch value {
        case nil, is NSNull: return .null
        case let number as NSNumber:
            return CFGetTypeID(number) == CFBooleanGetTypeID() ? .bool : .number
        case is String: return .string
        case is [Any]: return .array
        case is [String: Any]: return .object
        default: return .object
        }
    }

    static func same(_ lhs: Any?, _ rhs: Any?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case let (l?, r?): return (l as AnyObject).isEqual(r)
        default: return kind(lhs) == .null && kind(rhs) == .null
        }
    }

    static func changedKeys(from original: [String: Any], to edited: [String: Any]) -> [String] {
        Set(original.keys).union(edited.keys).filter { !same(original[$0], edited[$0]) }.sorted()
    }

    /// Changed keys whose new value is a different kind from what the server sent, or that the
    /// server didn't send at all. Clearing a value (null) or filling an empty one is allowed.
    static func mismatches(from original: [String: Any], to edited: [String: Any]) -> [String] {
        changedKeys(from: original, to: edited).filter { key in
            guard original.keys.contains(key) else { return true }
            let before = kind(original[key]), after = kind(edited[key])
            return before != after && before != .null && after != .null
        }
    }

    /// Of the keys that were changed, the ones the server didn't keep as sent.
    static func notKept(_ keys: [String], sent: [String: Any], reread: [String: Any]) -> [String] {
        keys.filter { !same(sent[$0], reread[$0]) }
    }

    static func describe(_ keys: [String]) -> String {
        keys.prefix(4).joined(separator: ", ") + (keys.count > 4 ? "…" : "")
    }
}

/// Says when the server is older or newer than these screens were checked against.
struct AdminCompatibilityNote: View {
    let status: ServerCompatibility.Status

    var body: some View {
        switch status {
        case .tooOld(let version):
            Section {
                Label("Jellyfin \(version.description) is older than Arcfin supports for editing (\(ServerCompatibility.oldestTested.description) and later), so these settings can only be viewed here.",
                      systemImage: "lock")
                    .font(.system(.footnote))
                    .foregroundStyle(DT.Color.textSecondary)
            }
        case .newer(let version):
            Section {
                Label("Jellyfin \(version.description) is newer than Arcfin has been checked with. Saving still works, but Arcfin asks first.",
                      systemImage: "exclamationmark.triangle")
                    .font(.system(.footnote))
                    .foregroundStyle(.orange)
            }
        case .tested, .unknown:
            EmptyView()
        }
    }
}

extension View {
    /// Asks before saving to a server newer than Arcfin was checked with.
    func untestedServerConfirmation(isPresented: Binding<Bool>, status: ServerCompatibility.Status,
                                    save: @escaping () -> Void) -> some View {
        alert("Save to a Newer Server?", isPresented: isPresented) {
            Button("Save Anyway") { save() }
            Button("Cancel", role: .cancel) {}
        } message: {
            if case .newer(let version) = status {
                Text("Arcfin hasn't been checked with Jellyfin \(version.description). Only the settings you changed are different from what the server has, and Arcfin checks afterwards that it kept them.")
            }
        }
    }
}
