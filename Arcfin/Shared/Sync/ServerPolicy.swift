// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// The server admin's security rules for a profile, from the latest signed `policy` command.
/// Kept on this device, so they hold offline too.
nonisolated struct ServerPolicy: Codable, Equatable {
    var pinRequired = false
    var pinMinLength = 4
    var pinMaxLength = 4
    var pinMaxTries: Int?
    var requireHttps = false

    static let allowedLengths = 4...8

    init(data: [String: String]) {
        func flag(_ key: String) -> Bool { ["true", "1", "yes"].contains(data[key]?.lowercased() ?? "") }
        func number(_ key: String) -> Int? { data[key].flatMap { Int($0) } }
        pinRequired = flag("pinRequired")
        requireHttps = flag("requireHttps")
        func within(_ value: Int) -> Int { min(max(value, Self.allowedLengths.lowerBound), Self.allowedLengths.upperBound) }
        let minimum = within(number("pinMinLength") ?? 4)
        pinMinLength = minimum
        pinMaxLength = max(minimum, within(number("pinMaxLength") ?? minimum))
        pinMaxTries = number("pinMaxTries").flatMap { $0 > 0 ? $0 : nil }
    }

    var pinLengths: ClosedRange<Int> { pinMinLength...pinMaxLength }

    private static func key(_ profile: UUID) -> String { "arcfin.serverPolicy.\(profile.uuidString)" }

    static func load(profile: UUID) -> ServerPolicy? {
        UserDefaults.standard.data(forKey: key(profile)).flatMap { try? JSONDecoder().decode(ServerPolicy.self, from: $0) }
    }

    static func save(_ policy: ServerPolicy, profile: UUID) {
        UserDefaults.standard.set(try? JSONEncoder().encode(policy), forKey: key(profile))
    }

    static func forget(profile: UUID) {
        UserDefaults.standard.removeObject(forKey: key(profile))
    }

    /// The lengths a new PIN for the profile may have: 4 digits unless the admin says otherwise.
    static func pinLengths(for profile: UUID?) -> ClosedRange<Int> {
        profile.flatMap(load)?.pinLengths ?? 4...4
    }

    // MARK: Away from home

    /// Plain HTTP to an address outside the home network.
    static func isInsecureAway(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "http", let host = url.host() else { return false }
        return !isLocal(host: host)
    }

    static func isLocal(host raw: String) -> Bool {
        let host = raw.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if host == "localhost" || host.hasSuffix(".local") { return true }
        let octets = host.split(separator: ".").compactMap { UInt8($0) }
        if octets.count == 4, host.split(separator: ".").count == 4 {
            switch (octets[0], octets[1]) {
            case (10, _), (127, _), (192, 168), (169, 254): return true
            case (172, let second): return (16...31).contains(second)
            default: return false
            }
        }
        guard host.contains(":") else { return false }
        if host == "::1" { return true }
        let first = host.split(separator: ":", omittingEmptySubsequences: false).first.map(String.init) ?? ""
        guard let word = UInt16(first, radix: 16) else { return false }
        // fc00::/7 (unique local) and fe80::/10 (link local).
        return word & 0xFE00 == 0xFC00 || word & 0xFFC0 == 0xFE80
    }
}

/// How many digits each profile's PIN has, so the pad knows when it's complete.
nonisolated enum PINLength {
    private static func key(_ profile: UUID) -> String { "arcfin.pinLength.\(profile.uuidString)" }

    static func stored(_ profile: UUID?) -> Int {
        guard let profile else { return 4 }
        let length = UserDefaults.standard.integer(forKey: key(profile))
        return ServerPolicy.allowedLengths.contains(length) ? length : 4
    }

    static func set(_ length: Int, profile: UUID) {
        UserDefaults.standard.set(length, forKey: key(profile))
    }

    static func forget(profile: UUID) {
        UserDefaults.standard.removeObject(forKey: key(profile))
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
