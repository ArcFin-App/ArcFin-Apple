// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

/// One Arcfin device's key status, under it in Users & Devices: whether it holds the current
/// key, why it was flagged, and Unlock or Clear.
struct DeviceKeyStatusRows: View {
    @Environment(AuthManager.self) private var authManager
    let model: ArcfinSyncAdminModel
    let record: SecurityAdmin.Device
    @State private var isBusy = false

    private var state: AdminBadge {
        if record.mismatchAt != nil { return AdminBadge("Key didn't match", isProminent: true) }
        if record.locked {
            switch record.lockReason {
            case "trust": return AdminBadge("Waiting for approval", isProminent: true)
            case "pinTries": return AdminBadge("Locked after too many wrong PINs", isProminent: true)
            case "wipe":
                return model.isWipePending(user: record.userId, device: record.deviceId)
                    ? AdminBadge("Wipe pending", isProminent: true) : AdminBadge("Wiped", isProminent: true)
            default: return AdminBadge("Locked", isProminent: true)
            }
        }
        if let signedOut = record.signedOut {
            return AdminBadge("Signed out \(signedOut.formatted(.relative(presentation: .named)))", isProminent: !record.upToDate)
        }
        return record.upToDate ? AdminBadge("Key up to date") : AdminBadge("Key behind", isProminent: true)
    }

    private var detail: String {
        var parts: [String] = []
        if let version = record.appVersion, !version.isEmpty {
            parts.append(String(localized: "Arcfin \(version)") + (record.build.map { $0.isEmpty ? "" : " (\($0))" } ?? ""))
        }
        parts.append(String(localized: "checked in \(record.lastCheckIn.formatted(.relative(presentation: .named)))"))
        if let after = record.signOutAfter {
            parts.append(String(localized: "signed out \(LiveTime.when(after)) if it's still behind"))
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DT.Spacing.xxs) {
            HStack(alignment: .firstTextBaseline, spacing: DT.Spacing.xs) {
                state
                TVRowLabelText(verbatim: detail)
                    .font(.caption)
            }
            if let reported = record.mismatchAt {
                Text("Reported \(reported.formatted(.relative(presentation: .named))): it got a key with fingerprint \(record.mismatchFingerprint ?? "?"), not this server's. Something on that network may be pretending to be your server.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.palette("F43F5E"))
            }
        }
        .tvReadOnlyRow()
        if record.locked || record.signedOut != nil {
            Button(record.locked ? LocalizedStringKey("Unlock") : "Clear") {
                Task {
                    isBusy = true
                    await model.unlockKeyDevice(record, authManager: authManager)
                    isBusy = false
                }
            }
            .formRowButton()
            .disabled(isBusy)
        }
    }
}

/// A device that has checked in its key but isn't in the person's Arcfin devices list.
struct KeyOnlyDeviceRows: View {
    let model: ArcfinSyncAdminModel
    let record: SecurityAdmin.Device

    var body: some View {
        TVRowLabelText(verbatim: record.deviceName.isEmpty ? String(localized: "Arcfin device") : record.deviceName)
            .tvReadOnlyRow()
        DeviceKeyStatusRows(model: model, record: record)
    }
}

/// Under a registered device that's signed in with an Arcfin too old to check in.
struct TooOldDeviceRow: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DT.Spacing.xxs) {
            AdminBadge("Too old for security features", isProminent: true)
            TVRowLabelText(verbatim: String(localized: "This Arcfin can't follow key changes or show a lock. Updating it fixes that."))
                .font(.caption)
        }
        .tvReadOnlyRow()
    }
}

enum OlderSignOutConfirm: Identifiable {
    case one(SecurityAdmin.OlderDevice)
    case all(count: Int)

    var id: String {
        switch self {
        case .one(let device): device.id
        case .all: "all"
        }
    }
}

/// A person's older Arcfin sign-ins that never registered as a device.
struct OlderSignInsView: View {
    @Environment(AuthManager.self) private var authManager
    let model: ArcfinSyncAdminModel
    let userID: String
    @State private var confirm: OlderSignOutConfirm?
    @State private var isBusy = false

    private var user: ArcfinSyncAdminUser? { model.user(userID) }
    private var older: [SecurityAdmin.OlderDevice] { user.map(model.leftoverOlderDevices) ?? [] }

    var body: some View {
        SettingsForm {
            AdminIntroSection(text: "Sign-ins from older Arcfin versions that never registered here, often left over from old installs. They can't follow key changes or show a lock.")
            Section {
                if older.isEmpty {
                    Text("Nothing left.")
                        .foregroundStyle(DT.Color.textSecondary)
                        .tvReadOnlyRow()
                }
                ForEach(older) { device in
                    Button { confirm = .one(device) } label: {
                        HStack(alignment: .firstTextBaseline) {
                            TVRowLabelText(verbatim: name(device), detail: device.lastActivity.map {
                                "\(String(localized: "last used \($0.formatted(.relative(presentation: .named)))"))"
                            })
                            Spacer(minLength: DT.Spacing.xs)
                            AdminBadge("Arcfin \(device.appVersion)")
                            Text("Sign Out")
                                .foregroundStyle(DT.Color.palette("F43F5E"))
                        }
                        .contentShape(Rectangle())
                    }
                    .formRowButton()
                    .tvListRow()
                    .disabled(isBusy)
                }
            }
            if !older.isEmpty {
                Section {
                    Button(role: .destructive) { HapticManager.warning(); confirm = .all(count: older.count) } label: {
                        Text("Sign Out All \(older.count)")
                            .foregroundStyle(DT.Color.palette("F43F5E"))
                    }
                    .formRowButton()
                    .disabled(isBusy)
                }
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge("Other Arcfin Sign-Ins")
        .confirmationPrompt(Text(title), isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
                            presenting: confirm) { pending in
            Button("Sign Out", role: .destructive) { Task { await signOut(pending) } }
            Button("Cancel", role: .cancel) {}
        } message: { pending in
            switch pending {
            case .one: Text("It has to sign in again to use the server.")
            case .all: Text("Any still in use have to sign in again.")
            }
        }
    }

    private func name(_ device: SecurityAdmin.OlderDevice) -> String {
        device.deviceName.isEmpty ? String(localized: "Arcfin device") : device.deviceName
    }

    private var title: LocalizedStringKey {
        switch confirm {
        case .one(let device): "Sign out \(name(device))?"
        case .all(let count): "Sign out all \(count) older Arcfin sign-ins for \(user?.name ?? "")?"
        case nil: ""
        }
    }

    private func signOut(_ pending: OlderSignOutConfirm) async {
        isBusy = true
        defer { isBusy = false }
        switch pending {
        case .one(let device): await model.signOutOlder(user: userID, device: device.deviceId, authManager: authManager)
        case .all: await model.signOutOlder(user: userID, device: nil, authManager: authManager)
        }
    }
}

/// A person's new devices waiting for a trusted device or an admin to approve them.
struct TrustRequestsSection: View {
    @Environment(AuthManager.self) private var authManager
    let model: ArcfinSyncAdminModel
    let requests: [SecurityAdmin.TrustRequest]
    @State private var refusing: SecurityAdmin.TrustRequest?
    @State private var isBusy = false

    var body: some View {
        Section {
            ForEach(requests) { request in
                TVRowLabelText(verbatim: name(request),
                               detail: "\(String(localized: "Code \(request.code)") + " · " + String(localized: "asked \(request.created.formatted(.relative(presentation: .named)))"))")
                    .tvReadOnlyRow()
                Button("Trust") { Task { await answer(true, request) } }
                    .formRowButton()
                    .disabled(isBusy)
                Button(role: .destructive) { refusing = request } label: {
                    Text("Don't Trust")
                        .foregroundStyle(DT.Color.palette("F43F5E"))
                }
                .formRowButton()
                .disabled(isBusy)
            }
        } header: {
            Text("Waiting for Approval")
        } footer: {
            Text("Check the code matches the one on the device before you trust it.")
        }
        .alert(Text(refusalTitle), isPresented: Binding(get: { refusing != nil }, set: { if !$0 { refusing = nil } }),
               presenting: refusing) { request in
            Button("Don't Trust", role: .destructive) { Task { await answer(false, request) } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("It's signed out and has to sign in again.")
        }
    }

    private var refusalTitle: LocalizedStringKey {
        "Don't trust \(refusing.map(name) ?? "")?"
    }

    private func name(_ request: SecurityAdmin.TrustRequest) -> String {
        request.deviceName.isEmpty ? String(localized: "Arcfin device") : request.deviceName
    }

    private func answer(_ trust: Bool, _ request: SecurityAdmin.TrustRequest) async {
        isBusy = true
        await model.answerTrust(trust, request: request, authManager: authManager)
        isBusy = false
    }
}

/// Wiping a lost device: two steps, the second typing WIPE.
struct WipeDeviceSection: View {
    @Environment(AuthManager.self) private var authManager
    let model: ArcfinSyncAdminModel
    let userID: String
    let deviceID: String
    let name: String
    @State private var asking = false
    @State private var typing = false

    var body: some View {
        Section {
            Button(role: .destructive) { HapticManager.warning(); asking = true } label: {
                Text(model.isWipePending(user: userID, device: deviceID) ? "Wipe Pending" : "Wipe This Device")
                    .foregroundStyle(DT.Color.palette("F43F5E"))
            }
            .formRowButton()
            .disabled(model.isWipePending(user: userID, device: deviceID))
        } footer: {
            Text("Deletes its downloads, locks Arcfin on it and signs it out once it's done. A device that never comes back online is signed out after a week.")
        }
        .alert(Text("Wipe \(name)?"), isPresented: $asking) {
            Button("Continue", role: .destructive) { typing = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone. Deletes its downloads, locks Arcfin on it and signs it out once it's done. A device that never comes back online is signed out after a week.")
        }
        .appSheet(isPresented: $typing, title: "Wipe This Device") {
            TypedConfirmSheet(word: "WIPE", title: "Wipe This Device", action: "Wipe This Device") {
                Task { await model.wipe(user: userID, device: deviceID, authManager: authManager) }
            }
        }
    }
}
