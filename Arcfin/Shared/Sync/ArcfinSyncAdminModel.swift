// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import JellyfinAPI
import SyncEngine

/// A user's lock for one setting: the one everyone has, or their own either way.
enum PolicyLockChoice: String, CaseIterable, Identifiable {
    case inherited, locked, unlocked
    var id: String { rawValue }
}

/// Arcfin for Everyone: the administrator's defaults and locks, everyone's devices, and the
/// plugin's own settings, all on the server's Arcfin Sync.
@MainActor @Observable
final class ArcfinSyncAdminModel {
    private(set) var schema = SettingsSchema.bundled
    var policy = ArcfinSyncPolicy()
    private(set) var savedPolicy = ArcfinSyncPolicy()
    private(set) var users: [ArcfinSyncAdminUser] = []
    private(set) var config: ArcfinSyncAdminConfig?
    private(set) var isLoading = true
    private(set) var errorMessage: String?
    private(set) var isSaving = false
    var actionError: String?

    private let client = ArcfinSyncClient()

    var hasChanges: Bool { policy != savedPolicy }

    private func session(_ authManager: AuthManager) -> (credential: ServerCredential, header: String)? {
        guard authManager.isAdmin else { return nil }
        return authManager.arcfinSyncDevicesSession
    }

    func load(authManager: AuthManager) async {
        guard let access = session(authManager) else {
            errorMessage = String(localized: "This profile isn't an admin, or the server can't be reached.")
            isLoading = false
            return
        }
        // The server's copy, so settings a newer plugin knows about show too.
        if let data = try? await client.fetchSchema(credential: access.credential, authHeader: access.header),
           let served = try? SettingsSchema.decode(data) {
            schema = served
        }
        async let policy = client.fetchPolicy(credential: access.credential, authHeader: access.header)
        async let users = client.fetchAdminUsers(credential: access.credential, authHeader: access.header)
        async let config = client.fetchAdminConfig(credential: access.credential, authHeader: access.header)
        do {
            let loaded = try await policy
            if !hasChanges { self.policy = loaded }
            savedPolicy = loaded
            errorMessage = nil
        } catch {
            errorMessage = String(localized: "Couldn't load Arcfin Sync's settings. Check your connection, and that this profile is still an admin.")
        }
        if let users = try? await users { self.users = users.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
        if let config = try? await config { self.config = config }
        isLoading = false
    }

    func save(authManager: AuthManager) async {
        guard let access = session(authManager) else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let saved = try await client.updatePolicy(credential: access.credential, authHeader: access.header, policy)
            policy = saved
            savedPolicy = saved
            // The admin's own devices pick up a new lock straight away.
            authManager.syncArcfinNow()
        } catch {
            actionError = String(localized: "The changes weren't saved. Check your connection and try again.")
        }
    }

    func discardChanges() { policy = savedPolicy }

    func saveConfig(_ update: ArcfinSyncAdminConfigUpdate, authManager: AuthManager) async -> Bool {
        guard let access = session(authManager) else { return false }
        do {
            if let saved = try await client.updateAdminConfig(credential: access.credential, authHeader: access.header, update) {
                config = saved
            } else {
                config = try await client.fetchAdminConfig(credential: access.credential, authHeader: access.header)
            }
            return true
        } catch {
            actionError = String(localized: "The changes weren't saved. Check your connection and try again.")
            return false
        }
    }

    func renameDevice(_ device: ArcfinSyncDevice, of user: ArcfinSyncAdminUser, to name: String, authManager: AuthManager) async {
        guard let access = session(authManager) else { return }
        do {
            _ = try await client.adminRenameDevice(credential: access.credential, authHeader: access.header, userID: user.userId,
                                                   deviceID: device.deviceId, name: name.trimmingCharacters(in: .whitespacesAndNewlines))
            await reloadUsers(access)
        } catch {
            actionError = String(localized: "The new name wasn't saved. Check your connection and try again.")
        }
    }

    func forgetDevice(_ device: ArcfinSyncDevice, of user: ArcfinSyncAdminUser, authManager: AuthManager) async -> Bool {
        guard let access = session(authManager) else { return false }
        do {
            try await client.adminForgetDevice(credential: access.credential, authHeader: access.header,
                                               userID: user.userId, deviceID: device.deviceId)
            await reloadUsers(access)
            return true
        } catch {
            actionError = String(localized: "The device wasn't forgotten. Check your connection and try again.")
            return false
        }
    }

    private func reloadUsers(_ access: (credential: ServerCredential, header: String)) async {
        if let users = try? await client.fetchAdminUsers(credential: access.credential, authHeader: access.header) {
            self.users = users.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    func user(_ id: String) -> ArcfinSyncAdminUser? { users.first { $0.userId == id } }

    // MARK: Editing the policy

    func entry(_ key: String, user: String?) -> ArcfinSyncPolicySetting? {
        if let user {
            return policy.users.first { $0.userId == user }?.settings.first { $0.key == key }
        }
        return policy.settings.first { $0.key == key }
    }

    func defaultValue(_ key: String, user: String?) -> String? { entry(key, user: user)?.defaultValue }

    func setDefault(_ value: String?, for key: String) {
        var setting = entry(key, user: nil) ?? ArcfinSyncPolicySetting(key: key, defaultValue: nil, locked: false)
        setting.defaultValue = value
        store(setting, user: nil, keep: value != nil || setting.locked)
    }

    func isLocked(_ key: String) -> Bool { entry(key, user: nil)?.locked ?? false }

    func setLocked(_ locked: Bool, for key: String) {
        var setting = entry(key, user: nil) ?? ArcfinSyncPolicySetting(key: key, defaultValue: nil, locked: false)
        setting.locked = locked
        store(setting, user: nil, keep: locked || setting.defaultValue != nil)
    }

    func lockChoice(_ key: String, user: String) -> PolicyLockChoice {
        guard let setting = entry(key, user: user) else { return .inherited }
        return setting.locked ? .locked : .unlocked
    }

    /// A user's own entry overrides everyone's lock; without one they have everyone's.
    func setLockChoice(_ choice: PolicyLockChoice, for key: String, user: String) {
        let current = entry(key, user: user)
        switch choice {
        case .inherited:
            if let value = current?.defaultValue {
                store(ArcfinSyncPolicySetting(key: key, defaultValue: value, locked: isLocked(key)), user: user, keep: true)
            } else {
                store(ArcfinSyncPolicySetting(key: key, defaultValue: nil, locked: false), user: user, keep: false)
            }
        case .locked, .unlocked:
            store(ArcfinSyncPolicySetting(key: key, defaultValue: current?.defaultValue, locked: choice == .locked),
                  user: user, keep: true)
        }
    }

    /// A user's own default; clearing it leaves their lock as it is.
    func setUserDefault(_ value: String?, for key: String, user: String) {
        let current = entry(key, user: user)
        guard value != nil || current != nil else { return }
        store(ArcfinSyncPolicySetting(key: key, defaultValue: value, locked: current?.locked ?? isLocked(key)),
              user: user, keep: true)
    }

    func overrideCount(user: String) -> Int {
        policy.users.first { $0.userId == user }?.settings.count ?? 0
    }

    private func store(_ setting: ArcfinSyncPolicySetting, user: String?, keep: Bool) {
        if let user {
            var users = policy.users
            var override = users.first { $0.userId == user } ?? ArcfinSyncUserPolicy(userId: user, settings: [])
            override.settings.removeAll { $0.key == setting.key }
            if keep { override.settings.append(setting) }
            users.removeAll { $0.userId == user }
            if !override.settings.isEmpty { users.append(override) }
            policy.users = users
        } else {
            policy.settings.removeAll { $0.key == setting.key }
            if keep { policy.settings.append(setting) }
        }
    }
}
