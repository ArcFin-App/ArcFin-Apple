// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import JellyfinAPI
import SyncEngine

/// A user's lock for one setting: the one everyone has (and keeps following), or their own
/// either way.
enum PolicyLockChoice: String, CaseIterable, Identifiable {
    case inherited, locked, unlocked
    var id: String { rawValue }
}

/// Arcfin for Everyone: the administrator's defaults and locks, and everyone's devices, all on
/// the server's Arcfin Sync.
@MainActor @Observable
final class ArcfinSyncAdminModel {
    private(set) var schema = SettingsSchema.bundled
    var policy = ArcfinSyncPolicy()
    private(set) var savedPolicy = ArcfinSyncPolicy()
    private(set) var users: [ArcfinSyncAdminUser] = []
    /// Each Arcfin device's key status, with signed commands on the server.
    private(set) var security: SecurityAdmin?
    private(set) var isLoading = true
    private(set) var errorMessage: String?
    private(set) var isSaving = false
    var actionError: String?

    private let client = ArcfinSyncClient()
    private let companion = ArcfinCompanionClient()

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
        do {
            let loaded = try await policy
            if !hasChanges { self.policy = loaded }
            savedPolicy = loaded
            errorMessage = nil
        } catch {
            errorMessage = String(localized: "Couldn't load Arcfin Sync's settings. Check your connection, and that this profile is still an admin.")
        }
        if let users = try? await users { self.users = users.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
        if authManager.arcfinSyncStatus?.features.contains("signedCommands") == true {
            security = try? await companion.securityAdmin(credential: access.credential, authHeader: access.header)
        } else {
            security = nil
        }
        isLoading = false
    }

    // MARK: Key status

    private static func same(_ a: String, _ b: String) -> Bool {
        ArcfinCompanionClient.normalized(a) == ArcfinCompanionClient.normalized(b)
    }

    func keyRecord(user userID: String, device deviceID: String) -> SecurityAdmin.Device? {
        security?.devices.first { Self.same($0.userId, userID) && Self.same($0.deviceId, deviceID) }
    }

    /// Key records for devices that aren't in the user's Arcfin devices list.
    func keyOnlyRecords(user: ArcfinSyncAdminUser) -> [SecurityAdmin.Device] {
        (security?.devices ?? []).filter { record in
            Self.same(record.userId, user.userId) && !user.devices.contains { Self.same($0.deviceId, record.deviceId) }
        }
    }

    func olderDevices(user userID: String) -> [SecurityAdmin.OlderDevice] {
        (security?.olderDevices ?? []).filter { Self.same($0.userId, userID) }
    }

    /// Signed commands are on, so trust requests, lock reasons and wiping apply.
    var securityOn: Bool { security?.settings.enabled == true }

    func trustRequests(user userID: String) -> [SecurityAdmin.TrustRequest] {
        securityOn ? (security?.trustRequests ?? []).filter { Self.same($0.userId, userID) } : []
    }

    func isWipePending(user userID: String, device deviceID: String) -> Bool {
        security?.pendingWipes.contains { Self.same($0.userId, userID) && Self.same($0.deviceId, deviceID) } == true
    }

    func answerTrust(_ trust: Bool, request: SecurityAdmin.TrustRequest, authManager: AuthManager) async {
        guard let access = session(authManager) else { return }
        do {
            security = try await companion.adminAnswerTrust(trust, requestID: request.id, credential: access.credential, authHeader: access.header)
            HapticManager.success()
        } catch {
            HapticManager.error()
            actionError = AdminSyncError.message(error)
        }
    }

    func wipe(user userID: String, device deviceID: String, authManager: AuthManager) async {
        guard let access = session(authManager) else { return }
        do {
            security = try await companion.wipeDevice(userID: userID, deviceID: deviceID, credential: access.credential, authHeader: access.header)
            HapticManager.success()
        } catch {
            HapticManager.error()
            actionError = AdminSyncError.message(error)
        }
    }

    /// A registered device that's also signed in with an Arcfin too old to check in.
    func isTooOld(user userID: String, device deviceID: String) -> Bool {
        olderDevices(user: userID).contains { Self.same($0.deviceId, deviceID) }
    }

    /// Older sign-ins that never registered as a device: mostly leftovers from old installs.
    func leftoverOlderDevices(user: ArcfinSyncAdminUser) -> [SecurityAdmin.OlderDevice] {
        olderDevices(user: user.userId).filter { older in !user.devices.contains { Self.same($0.deviceId, older.deviceId) } }
    }

    /// Signs out one older sign-in, or with nil all of the user's.
    func signOutOlder(user userID: String, device deviceID: String?, authManager: AuthManager) async {
        guard let access = session(authManager) else { return }
        do {
            security = try await companion.signOutOlder(userID: userID, deviceID: deviceID,
                                                        credential: access.credential, authHeader: access.header)
            HapticManager.success()
        } catch {
            HapticManager.error()
            actionError = AdminSyncError.message(error)
        }
    }

    /// "2 need a look · 1 too old", or nil when nothing does.
    func keyFlags(user: ArcfinSyncAdminUser) -> String? {
        let flagged = (security?.devices ?? []).filter {
            Self.same($0.userId, user.userId) && ($0.mismatchAt != nil || $0.locked || !$0.upToDate)
        }.count
        let leftover = leftoverOlderDevices(user: user).count
        let tooOld = olderDevices(user: user.userId).count - leftover
        let waiting = trustRequests(user: user.userId).count
        let parts = [
            waiting > 0 ? String(localized: "\(waiting) waiting") : nil,
            flagged == 1 ? String(localized: "1 needs a look") : flagged > 1 ? String(localized: "\(flagged) need a look") : nil,
            tooOld == 1 ? String(localized: "1 device too old") : tooOld > 1 ? String(localized: "\(tooOld) devices too old") : nil,
            leftover == 1 ? String(localized: "1 old sign-in") : leftover > 1 ? String(localized: "\(leftover) old sign-ins") : nil,
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    func unlockKeyDevice(_ device: SecurityAdmin.Device, authManager: AuthManager) async {
        guard let access = session(authManager) else { return }
        do {
            security = try await companion.unlockDevice(userID: device.userId, deviceID: device.deviceId,
                                                        credential: access.credential, authHeader: access.header)
            HapticManager.success()
        } catch {
            HapticManager.error()
            actionError = AdminSyncError.message(error)
        }
    }

    func save(authManager: AuthManager) async {
        guard let access = session(authManager) else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let saved = try await client.updatePolicy(credential: access.credential, authHeader: access.header, policy)
            policy = saved
            savedPolicy = saved
            HapticManager.success()
            // The admin's own devices pick up a new lock straight away.
            authManager.syncArcfinNow()
        } catch {
            HapticManager.error()
            actionError = String(localized: "The changes weren't saved. Check your connection and try again.")
        }
    }

    func discardChanges() { policy = savedPolicy }

    func renameDevice(_ device: ArcfinSyncDevice, of user: ArcfinSyncAdminUser, to name: String, authManager: AuthManager) async {
        guard let access = session(authManager) else { return }
        do {
            _ = try await client.adminRenameDevice(credential: access.credential, authHeader: access.header, userID: user.userId,
                                                   deviceID: device.deviceId, name: name.trimmingCharacters(in: .whitespacesAndNewlines))
            await reloadUsers(access)
        } catch {
            HapticManager.error()
            actionError = String(localized: "The new name wasn't saved. Check your connection and try again.")
        }
    }

    func forgetDevice(_ device: ArcfinSyncDevice, of user: ArcfinSyncAdminUser, authManager: AuthManager) async -> Bool {
        guard let access = session(authManager) else { return false }
        do {
            try await client.adminForgetDevice(credential: access.credential, authHeader: access.header,
                                               userID: user.userId, deviceID: device.deviceId)
            await reloadUsers(access)
            HapticManager.success()
            return true
        } catch {
            HapticManager.error()
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
        store(setting, user: nil, keep: value != nil || setting.locked == true)
    }

    func isLocked(_ key: String) -> Bool { entry(key, user: nil)?.locked == true }

    func setLocked(_ locked: Bool, for key: String) {
        var setting = entry(key, user: nil) ?? ArcfinSyncPolicySetting(key: key, defaultValue: nil, locked: false)
        setting.locked = locked
        store(setting, user: nil, keep: locked || setting.defaultValue != nil)
    }

    func lockChoice(_ key: String, user: String) -> PolicyLockChoice {
        switch entry(key, user: user)?.locked {
        case nil: .inherited
        case true?: .locked
        case false?: .unlocked
        }
    }

    /// A user's own lock overrides everyone's; without one they follow everyone's, even with a
    /// default of their own.
    func setLockChoice(_ choice: PolicyLockChoice, for key: String, user: String) {
        let value = entry(key, user: user)?.defaultValue
        let locked: Bool? = switch choice {
        case .inherited: nil
        case .locked: true
        case .unlocked: false
        }
        store(ArcfinSyncPolicySetting(key: key, defaultValue: value, locked: locked), user: user,
              keep: value != nil || locked != nil)
    }

    /// A user's own default; setting or clearing it leaves their lock as it is.
    func setUserDefault(_ value: String?, for key: String, user: String) {
        let locked = entry(key, user: user)?.locked
        store(ArcfinSyncPolicySetting(key: key, defaultValue: value, locked: locked), user: user,
              keep: value != nil || locked != nil)
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
