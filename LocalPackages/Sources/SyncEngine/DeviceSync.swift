// SPDX-License-Identifier: AGPL-3.0-or-later

import AuthCore
import Foundation
import JellyfinAPI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - This device

public enum ArcfinDeviceInfo {
    /// The platform names the plugin knows.
    @MainActor
    public static var platform: String {
        #if os(tvOS)
        "tvOS"
        #elseif os(macOS)
        "macOS"
        #elseif os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad ? "iPadOS" : "iOS"
        #else
        "iOS"
        #endif
    }

    /// The hardware model, such as iPhone17,1 or Mac16,10.
    public static var model: String {
        #if os(macOS)
        let name = "hw.model"
        #else
        let name = "hw.machine"
        #endif
        var size = 0
        sysctlbyname(name, nil, &size, nil, 0)
        guard size > 0 else { return "" }
        var bytes = [CChar](repeating: 0, count: size)
        sysctlbyname(name, &bytes, &size, nil, 0)
        return String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    public static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? version : "\(version) (\(build))"
    }

    /// A schema's platform list says "iOS" for iPhone and iPad alike.
    public static func schemaPlatform(_ platform: String) -> String {
        platform == "iPadOS" ? "iOS" : platform
    }
}

// MARK: - Settings changed on another device

/// What Ask First holds until the person answers.
public struct RemoteSettingsChange: Sendable, Equatable, Codable {
    public let profile: String
    public let deviceName: String
    public let updatedAt: Date
    public let values: [String: String]
    /// Settings the other device cleared.
    public let cleared: Set<String>

    public init(profile: String, deviceName: String, updatedAt: Date, values: [String: String], cleared: Set<String> = []) {
        self.profile = profile
        self.deviceName = deviceName
        self.updatedAt = updatedAt
        self.values = values
        self.cleared = cleared
    }
}

/// What a plugin v2 sync found.
public struct DeviceSyncResult: Sendable {
    /// Every locked key, synced and device ones.
    public let locked: Set<String>
    /// Ask First: changes from another device waiting for an answer.
    public let pending: RemoteSettingsChange?
    /// The record the server keeps for this device, nil when it couldn't be sent.
    public let device: ArcfinSyncDevice?
}

/// Ask First's "Keep This Device's": what was turned down, so it isn't offered again while the
/// other device still has it.
struct DeclinedSettings: Codable, Equatable {
    var values: [String: String] = [:]
    var cleared: Set<String> = []
}

extension SettingsSyncEngine {
    private static func handledKey(profile: String) -> String { "arcfin.settingsSync.handledRemote.\(profile)" }
    private static func pendingKey(profile: String) -> String { "arcfin.settingsSync.pendingRemote.\(profile)" }
    private static func declinedKey(profile: String) -> String { "arcfin.settingsSync.declinedRemote.\(profile)" }

    /// The plugin's limit on one value, in UTF-16 units as .NET counts a string.
    static let maxValueLength = 4096

    static func fitsOnServer(_ value: String) -> Bool { value.utf16.count <= maxValueLength }

    /// Leaves out what the server can't keep, rather than sending it to be skipped.
    public static func withinServerLimits(_ values: [String: String]) -> [String: String] {
        values.filter { fitsOnServer($0.value) }
    }

    // MARK: Ask First, kept through a relaunch

    /// The question still waiting for `profile`. It's kept, since after this device's own next
    /// change the server says this device changed settings last and there'd be nothing to ask.
    public static func savedPending(profile: String, defaults: UserDefaults = .standard) -> RemoteSettingsChange? {
        defaults.data(forKey: pendingKey(profile: profile)).flatMap { try? JSONDecoder().decode(RemoteSettingsChange.self, from: $0) }
    }

    static func savePending(_ change: RemoteSettingsChange?, profile: String, defaults: UserDefaults) {
        if let change, let data = try? JSONEncoder().encode(change) {
            defaults.set(data, forKey: pendingKey(profile: profile))
        } else {
            defaults.removeObject(forKey: pendingKey(profile: profile))
        }
    }

    public static func forgetPending(profile: String, defaults: UserDefaults = .standard) {
        savePending(nil, profile: profile, defaults: defaults)
    }

    /// A removed profile's Ask First records.
    public static func forgetAskFirst(profile: String, defaults: UserDefaults = .standard) {
        forgetPending(profile: profile, defaults: defaults)
        defaults.removeObject(forKey: declinedKey(profile: profile))
    }

    static func declined(profile: String, defaults: UserDefaults) -> DeclinedSettings {
        defaults.data(forKey: declinedKey(profile: profile))
            .flatMap { try? JSONDecoder().decode(DeclinedSettings.self, from: $0) } ?? DeclinedSettings()
    }

    static func saveDeclined(_ declined: DeclinedSettings, profile: String, defaults: UserDefaults) {
        if declined == DeclinedSettings() {
            defaults.removeObject(forKey: declinedKey(profile: profile))
        } else if let data = try? JSONEncoder().encode(declined) {
            defaults.set(data, forKey: declinedKey(profile: profile))
        }
    }

    /// What's still worth offering: a value turned down is left out while the other device has
    /// that same value, and forgotten once it changes.
    static func offer(_ held: [String: String], cleared: Set<String>, declined: DeclinedSettings)
        -> (values: [String: String], cleared: Set<String>, declined: DeclinedSettings) {
        var still = DeclinedSettings()
        still.values = declined.values.filter { held[$0.key] == $0.value }
        still.cleared = declined.cleared.intersection(cleared)
        return (held.filter { still.values[$0.key] != $0.value }, cleared.subtracting(still.cleared), still)
    }

    // MARK: Pure decisions

    /// Every schema setting this device has a value for, in the wire format. Only schema keys, so
    /// nothing secret or private is ever in it.
    public static func snapshot(schema: SettingsSchema = .bundled, scope: SettingsSchema.Scope? = nil,
                                defaults: UserDefaults = .standard) -> [String: String] {
        var values: [String: String] = [:]
        for setting in schema.settings where scope == nil || setting.scope == scope {
            if let value = setting.type.read(setting.key, from: defaults) { values[setting.key] = value }
        }
        return values
    }

    /// Writes schema settings typed by the schema; a key it doesn't know is skipped.
    static func write(_ values: [String: String], clearing: Set<String> = [], schema: SettingsSchema,
                      defaults: UserDefaults) {
        for (key, value) in values {
            guard let stored = schema.setting(key)?.type.stored(value) else { continue }
            defaults.set(stored, forKey: key)
        }
        for key in clearing where schema.setting(key) != nil { defaults.removeObject(forKey: key) }
    }

    /// Ask First asks once per change made on another device.
    public static func shouldAsk(state: ArcfinSyncState, deviceID: String, lastHandled: Date?,
                                 changes: [String: String], cleared: Set<String> = []) -> Bool {
        guard !changes.isEmpty || !cleared.isEmpty, let updatedAt = state.updatedAt,
              let by = state.updatedByDeviceId, !by.isEmpty, by != deviceID
        else { return false }
        return lastHandled.map { updatedAt > $0 } ?? true
    }

    /// The Seerr sign-in goes with its password, which never syncs: taking another device's
    /// Seerr server without it would leave this one signed out, so it's never cleared.
    static let neverCleared = ProfileSettings.swappedWithSeerr

    /// Another device's settings, to use here: its synced values are set, and a synced setting it
    /// doesn't have goes back to the default, but only where that device shows the setting (an
    /// Apple TV says nothing about downloads). Locked settings stay as the administrator set them.
    public static func replacement(source: [String: String], sourcePlatform: String, local: [String: String],
                                   locked: Set<String>, schema: SettingsSchema = .bundled)
        -> (set: [String: String], clear: Set<String>) {
        let platform = ArcfinDeviceInfo.schemaPlatform(sourcePlatform)
        var set: [String: String] = [:]
        var clear: Set<String> = []
        for setting in schema.settings where setting.scope == .synced && !locked.contains(setting.key) {
            if let value = source[setting.key] {
                if local[setting.key] != value { set[setting.key] = value }
            } else if local[setting.key] != nil, setting.platforms.contains(platform), !neverCleared.contains(setting.key) {
                clear.insert(setting.key)
            }
        }
        return (set, clear)
    }

    /// What "Send This Device's Settings" puts on the server with Replace. The server clears
    /// every synced setting not sent, so one this platform never shows, and the Seerr sign-in, keep
    /// the server's current value instead of being reset.
    public static func replacePayload(local: [String: String], remote: [String: String], platform: String,
                                      locked: Set<String>, schema: SettingsSchema = .bundled) -> [String: String] {
        let platform = ArcfinDeviceInfo.schemaPlatform(platform)
        var values: [String: String] = [:]
        for setting in schema.settings where setting.scope == .synced && !locked.contains(setting.key) {
            let localValue = local[setting.key]
            if let localValue, fitsOnServer(localValue) {
                values[setting.key] = localValue
            } else if localValue != nil || !setting.platforms.contains(platform) || neverCleared.contains(setting.key),
                      let value = remote[setting.key] {
                values[setting.key] = value
            }
        }
        return values
    }

    /// The administrator's defaults and locks for settings that stay on each device: a lock
    /// always applies, a default only where this device hasn't set it.
    public static func devicePolicy(_ settings: [ArcfinSyncSetting], local: [String: String],
                                    schema: SettingsSchema = .bundled) -> (apply: [String: String], locked: Set<String>) {
        var apply: [String: String] = [:]
        var locked: Set<String> = []
        for setting in settings where schema.setting(setting.key)?.scope == .device {
            if setting.isLocked { locked.insert(setting.key) }
            guard let value = setting.value else { continue }
            if setting.isLocked || setting.source == .locked {
                if local[setting.key] != value { apply[setting.key] = value }
            } else if setting.source == .default, local[setting.key] == nil {
                apply[setting.key] = value
            }
        }
        return (apply, locked)
    }

    // MARK: Plugin v2 sync

    /// A sync with plugin v2. Automatic merges as `sync` does, then updates this device's record.
    /// Ask First sends what changed here but holds what changed on another device for a yes. Off
    /// only takes locked settings. In every mode the device's record is updated and device locks
    /// apply, before the mode is read, so a sync mode the admin just locked counts straight away.
    /// Runs on the main actor: see `sync` for `isCurrent`.
    @MainActor
    public static func syncDevice(credential: ServerCredential, authHeader: String, deviceID: String,
                                  registration: @MainActor ([String: String]) -> ArcfinSyncDeviceRegistration,
                                  defaults: UserDefaults = .standard,
                                  isCurrent: @MainActor () -> Bool = { true }) async -> DeviceSyncResult? {
        let client = ArcfinSyncClient()
        let profile = credential.id.uuidString
        guard let state = try? await client.fetchSync(credential: credential, authHeader: authHeader), isCurrent()
        else { return nil }
        let devicePolicy = devicePolicy(state.settings, local: snapshot(scope: .device, defaults: defaults))
        write(devicePolicy.apply, schema: .bundled, defaults: defaults)
        let syncedLocked = state.lockedKeys.intersection(SettingsSyncRegistry.allKeys)
        var pending: RemoteSettingsChange?

        switch SettingsSyncMode.current(defaults: defaults) {
        case .automatic:
            guard let synced = await syncSettings(credential: credential, authHeader: authHeader, state: state,
                                                  defaults: defaults, isCurrent: isCurrent)
            else { return nil }
            // Seen here already, so switching to Ask First doesn't ask about it.
            markHandled(synced.updatedAt, profile: profile, defaults: defaults)
        case .ask:
            let found = await askFirst(state: state, client: client, credential: credential, authHeader: authHeader,
                                       deviceID: deviceID, locked: syncedLocked, defaults: defaults, isCurrent: isCurrent)
            pending = stillPending(savedPending(profile: profile, defaults: defaults), found: found, profile: profile)
        case .off:
            let local = collectLocalPayload(defaults: defaults).settings
            let taken = state.values.filter { syncedLocked.contains($0.key) && local[$0.key] != $0.value }
            apply(SyncPayload(settings: taken), defaults: defaults)
        }
        guard isCurrent() else { return nil }
        savePending(pending, profile: profile, defaults: defaults)
        let locked = syncedLocked.union(devicePolicy.locked)
        defaults.set(locked.sorted(), forKey: lockedKey(profile: profile))

        let body = registration(snapshot(defaults: defaults))
        let device = try? await client.registerDevice(credential: credential, authHeader: authHeader, body)
        return DeviceSyncResult(locked: locked, pending: pending, device: device)
    }

    @MainActor
    private static func askFirst(state: ArcfinSyncState, client: ArcfinSyncClient, credential: ServerCredential,
                                 authHeader: String, deviceID: String, locked: Set<String>, defaults: UserDefaults,
                                 isCurrent: @MainActor () -> Bool) async -> RemoteSettingsChange? {
        let profile = credential.id.uuidString
        let local = collectLocalPayload(defaults: defaults).settings
        let (base, adoptRemote) = startingPoint(profile: profile, defaults: defaults)
        let merged = merge(local: local, remote: state.values, base: base, locked: locked, adoptRemote: adoptRemote,
                           canClearOnServer: true)

        // Another profile's values are on this device: this one's are taken, as in sync().
        let taken = adoptRemote ? merged.apply : merged.apply.filter { locked.contains($0.key) }
        let offered = offer(adoptRemote ? [:] : merged.apply.filter { !locked.contains($0.key) }, cleared: merged.clear,
                            declined: declined(profile: profile, defaults: defaults))
        apply(SyncPayload(settings: taken), defaults: defaults)

        var agreed = base ?? [:]
        for (key, value) in taken { agreed[key] = value }
        if !merged.push.isEmpty || !merged.clearOnServer.isEmpty,
           let saved = try? await client.updateSync(credential: credential, authHeader: authHeader, values: merged.push,
                                                    clearing: merged.clearOnServer, replace: false) {
            let kept = saved.values
            for (key, value) in merged.push where kept[key] == value { agreed[key] = value }
            for key in merged.clearOnServer { agreed[key] = nil }
        }
        guard isCurrent() else { return nil }
        defaults.set(agreed, forKey: lastSyncedKey(profile: profile))
        defaults.set(profile, forKey: lastProfileKey)
        saveDeclined(offered.declined, profile: profile, defaults: defaults)

        let lastHandled = defaults.object(forKey: handledKey(profile: profile)) as? Date
        guard shouldAsk(state: state, deviceID: deviceID, lastHandled: lastHandled, changes: offered.values,
                        cleared: offered.cleared),
              let updatedAt = state.updatedAt
        else { return nil }
        return RemoteSettingsChange(profile: profile, deviceName: state.updatedByDeviceName ?? "",
                                    updatedAt: updatedAt, values: offered.values, cleared: offered.cleared)
    }

    /// A question still waiting keeps waiting through later syncs (one that changed settings here
    /// finds nothing new to ask), until it's answered or a newer change replaces it.
    public static func stillPending(_ current: RemoteSettingsChange?, found: RemoteSettingsChange?,
                                    profile: String) -> RemoteSettingsChange? {
        if let found { return found }
        guard let current, current.profile == profile else { return nil }
        return current
    }

    static func markHandled(_ date: Date?, profile: String, defaults: UserDefaults) {
        guard let date else { return }
        defaults.set(date, forKey: handledKey(profile: profile))
    }

    /// The answer to Ask First. Taking them counts them as agreed with the server, so they aren't
    /// sent back as this device's change.
    public static func answer(_ change: RemoteSettingsChange, useThem: Bool, defaults: UserDefaults = .standard) {
        markHandled(change.updatedAt, profile: change.profile, defaults: defaults)
        forgetPending(profile: change.profile, defaults: defaults)
        var declined = declined(profile: change.profile, defaults: defaults)
        if useThem {
            for key in change.values.keys { declined.values[key] = nil }
            declined.cleared.subtract(change.cleared)
        } else {
            declined.values.merge(change.values) { _, new in new }
            declined.cleared.formUnion(change.cleared)
        }
        saveDeclined(declined, profile: change.profile, defaults: defaults)
        guard useThem else { return }
        let locked = lockedKeys(profile: change.profile, defaults: defaults)
        let values = change.values.filter { !locked.contains($0.key) }
        let cleared = change.cleared.subtracting(locked)
        apply(SyncPayload(settings: values), defaults: defaults)
        for key in cleared { defaults.removeObject(forKey: key) }
        var agreed = lastSynced(profile: change.profile, defaults: defaults) ?? [:]
        for (key, value) in values { agreed[key] = value }
        for key in cleared { agreed[key] = nil }
        defaults.set(agreed, forKey: lastSyncedKey(profile: change.profile))
    }

    /// "Use These Settings Here", from another device's record.
    public static func useSettings(of device: ArcfinSyncDevice, profile: String, defaults: UserDefaults = .standard) {
        let locked = lockedKeys(profile: profile, defaults: defaults)
        let local = collectLocalPayload(defaults: defaults).settings
        let (set, clear) = replacement(source: device.settings, sourcePlatform: device.platform, local: local, locked: locked)
        write(set, clearing: clear, schema: .bundled, defaults: defaults)
        forgetPending(profile: profile, defaults: defaults)
    }

    /// "Send This Device's Settings to My Other Devices". A profile switch while it waits on the
    /// server stops it before it reads or records the next profile's settings.
    @MainActor
    public static func sendToAll(credential: ServerCredential, authHeader: String, platform: String,
                                 defaults: UserDefaults = .standard, isCurrent: @MainActor () -> Bool = { true }) async throws {
        let client = ArcfinSyncClient()
        let profile = credential.id.uuidString
        let state = try await client.fetchSync(credential: credential, authHeader: authHeader)
        guard isCurrent() else { throw CancellationError() }
        let locked = state.lockedKeys
        let values = replacePayload(local: collectLocalPayload(defaults: defaults).settings, remote: state.values,
                                    platform: platform, locked: locked)
        let saved = try await client.updateSync(credential: credential, authHeader: authHeader, values: values, replace: true)
        guard isCurrent() else { throw CancellationError() }
        var agreed = saved.values.filter { SettingsSyncRegistry.allKeys.contains($0.key) }
        for (key, value) in collectLocalPayload(defaults: defaults).settings where !locked.contains(key) { agreed[key] = value }
        defaults.set(agreed, forKey: lastSyncedKey(profile: profile))
        markHandled(saved.updatedAt, profile: profile, defaults: defaults)
        forgetPending(profile: profile, defaults: defaults)
    }
}
