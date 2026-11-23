// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

/// Every setting the Arcfin apps show, as the Arcfin Sync plugin knows them: the synced ones
/// (exactly SettingsSyncRegistry) and the ones that stay on each device. The same file ships in
/// the plugin, which serves it from /ArcfinSync/Schema.
public struct SettingsSchema: Sendable, Decodable, Equatable {
    public struct Group: Sendable, Decodable, Equatable, Identifiable {
        public let id: String
        public let title: String
    }

    public struct Option: Sendable, Decodable, Equatable, Hashable {
        public let value: String
        public let title: String
    }

    public enum Scope: String, Sendable, Decodable {
        case synced, device
    }

    public struct Setting: Sendable, Decodable, Equatable, Identifiable {
        public let key: String
        public let type: SettingsSyncValueType
        public let scope: Scope
        public let group: String
        public let title: String
        public let detail: String?
        /// For a string or JSON setting: "csv" (a comma-separated list) or "json".
        public let format: String?
        public let `default`: String?
        public let options: [Option]?
        public let min: Int?
        public let max: Int?
        public let step: Int?
        public let platforms: [String]

        public var id: String { key }

        public func optionTitle(for value: String) -> String? {
            options?.first { $0.value == value }?.title
        }
    }

    public let version: Int
    public let groups: [Group]
    public let settings: [Setting]

    public var syncedKeys: Set<String> { Set(settings.filter { $0.scope == .synced }.map(\.key)) }
    public var deviceKeys: Set<String> { Set(settings.filter { $0.scope == .device }.map(\.key)) }
    public var allKeys: Set<String> { Set(settings.map(\.key)) }

    public func setting(_ key: String) -> Setting? { settings.first { $0.key == key } }

    public func settings(in group: Group) -> [Setting] { settings.filter { $0.group == group.id } }

    /// Takes the schema file as written, or a server's copy with PascalCase names.
    public static func decode(_ data: Data) throws -> SettingsSchema {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .custom { path in
            let name = path.last!.stringValue
            return CamelKey(name.prefix(1).lowercased() + name.dropFirst())
        }
        return try decoder.decode(SettingsSchema.self, from: data)
    }

    /// The copy built into the app.
    public static let bundled: SettingsSchema = {
        guard let url = Bundle.module.url(forResource: "settings-schema", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let schema = try? decode(data)
        else { preconditionFailure("settings-schema.json is missing from SyncEngine's resources or doesn't decode") }
        return schema
    }()

    private struct CamelKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(_ string: String) { stringValue = string }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}
