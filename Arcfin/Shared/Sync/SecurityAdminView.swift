// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import JellyfinAPI

/// Arcfin for Everyone › Security: the server's signing key, and the signed commands it sends
/// to Arcfin: clear a profile's PIN, or lock or unlock it on all its devices.
struct SecurityAdminView: View {
    @Environment(AuthManager.self) private var authManager
    let users: [ArcfinSyncAdminUser]

    @State private var admin: SecurityAdmin?
    @State private var error: String?
    @State private var actionError: String?
    @State private var pem = ""
    @State private var isBusy = false
    @State private var confirm: SecurityConfirm?
    @State private var disableAccountFor: ArcfinSyncAdminUser?
    @State private var typingReplace = false
    @State private var confirmTrustOverHTTP = false
    @State private var settings = SecuritySettings()
    private let client = ArcfinCompanionClient()

    var body: some View {
        SettingsForm {
            if admin != nil {
                AdminIntroSection(text: "PINs never leave people's devices. Instead, this server can send signed commands that Arcfin carries out: clear a profile's PIN, lock a profile on all its devices, or unlock it. Each device checks every command's signature against this server's key, so only this server can send them.")
                SignedCommandsSection(isOn: settings.enabled, isBusy: isBusy) { on in
                    Task { await saveNow(\.enabled, on) }
                }
            }
            if let admin, admin.settings.enabled {
                AdminIntroSection(text: "How a device learns the key: over HTTPS it trusts the key the first time, because the system has already checked the server's certificate. Over plain HTTP it can't be sure who answered, so Arcfin shows the key's fingerprint in Settings › Server and waits until someone confirms it matches the one below. A new key you make later is signed by the old one, so devices move to it on their own; any other change of key needs the fingerprint checked again.")
                SigningKeySection(key: admin.key, isBusy: isBusy) { ask(.newKey(pem: nil, endsRotation: false)) }
                if admin.key != nil {
                    ReplaceKeySection(isBusy: isBusy) { HapticManager.warning(); confirm = .replaceKey }
                }
                OwnKeySection(pem: $pem, isBusy: isBusy) {
                    let trimmed = pem.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { ask(.newKey(pem: trimmed, endsRotation: admin.settings.autoRotate)) }
                }
                PlainHTTPSection(isOn: settings.trustOverHttp, isBusy: isBusy) { on in
                    if on { confirmTrustOverHTTP = true } else { Task { await saveNow(\.trustOverHttp, false) } }
                }
                TrustedDevicesSection(settings: $settings)
                HTTPSAwaySection(settings: $settings)
                PinRulesSection(pins: $settings.pins, users: users)
                RotationSection(settings: $settings, admin: admin)
                StaleRuleSection(settings: $settings)
                OlderAppsSection(settings: $settings)
                SecurityPeopleSection(settings: $settings, users: users)
                Section {
                    Button {
                        Task { await saveSettings() }
                    } label: {
                        Text(isBusy ? "Saving…" : "Save")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .formRowButton()
                    .disabled(isBusy || !hasChanges(admin))
                } footer: {
                    Text("Saves trusted devices, HTTPS away from home, PIN rules, automatic rotation, the rules for devices that fall behind, what happens to older Arcfin versions, and each person's own rules.")
                }
                ForEach(users) { user in
                    SecurityUserSection(user: user, admin: admin, isBusy: isBusy) { kind in
                        if admin.key == nil {
                            actionError = String(localized: "Make or add a signing key first.")
                        } else {
                            HapticManager.warning()
                            confirm = .command(kind, user)
                        }
                    }
                }
            }
            if admin == nil {
                AdminPendingSection(error: error)
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge("Security")
        .task { await load() }
        .adminErrorAlert($actionError)
        .confirmationPrompt(Text(confirm?.title ?? ""), isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
                            presenting: confirm) { pending in
            Button(pending.action, role: pending.isDestructive ? .destructive : nil) { Task { await carryOut(pending) } }
            Button("Cancel", role: .cancel) {}
        } message: { pending in
            Text(pending.message)
        }
        .appSheet(isPresented: $typingReplace, title: "Replace the Key") {
            TypedConfirmSheet(word: "REPLACE", title: "Replace the Key", action: "Replace the Key") { Task { await run { try await client.resetSigningKey(credential: $0, authHeader: $1) } } }
        }
        .alert("Trust the key over plain HTTP without checking?", isPresented: $confirmTrustOverHTTP) {
            Button("Trust It", role: .destructive) { Task { await saveNow(\.trustOverHttp, true) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Devices stop asking for the fingerprint. On a network you don't trust, someone could pretend to be your server.")
        }
        .alert(Text(disableAccountTitle),
               isPresented: Binding(get: { disableAccountFor != nil }, set: { if !$0 { disableAccountFor = nil } }),
               presenting: disableAccountFor) { user in
            Button("Disable Account", role: .destructive) { Task { await lock(user, disableAccount: true) } }
            Button("Only Lock Arcfin") { Task { await lock(user, disableAccount: false) } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("They're signed out everywhere and can't use the server at all, in any app, until you unlock them here.")
        }
    }

    private var disableAccountTitle: LocalizedStringKey {
        "Also disable \(disableAccountFor?.name ?? "")'s Jellyfin account?"
    }

    /// The overrides worth sending: anything but "same as everyone" all through.
    private static func trimmed(_ settings: SecuritySettings) -> SecuritySettings {
        var next = settings
        next.users = next.users.filter { $0.staleAction != "inherit" || $0.staleAfterDays != nil || $0.trustedDevices != "inherit" }
        return next
    }

    private var settingsToSave: SecuritySettings { Self.trimmed(settings) }

    private func hasChanges(_ admin: SecurityAdmin) -> Bool {
        settingsToSave != Self.trimmed(admin.settings)
    }

    private func show(_ next: SecurityAdmin) {
        admin = next
        settings = next.settings
    }

    private func saveSettings() async {
        await run { try await client.saveSecuritySettings(settingsToSave, credential: $0, authHeader: $1) }
    }

    /// Saved straight away with the rest of the settings as they were loaded, so unsaved edits
    /// elsewhere on the page stay unsaved.
    private func saveNow(_ field: WritableKeyPath<SecuritySettings, Bool>, _ on: Bool) async {
        guard var saved = admin?.settings, let access = authManager.arcfinSyncDevicesSession else { return }
        saved[keyPath: field] = on
        isBusy = true
        defer { isBusy = false }
        do {
            let next = try await client.saveSecuritySettings(saved, credential: access.credential, authHeader: access.header)
            admin = next
            settings[keyPath: field] = next.settings[keyPath: field]
            HapticManager.success()
        } catch {
            actionError = AdminSyncError.message(error)
        }
    }

    private func lock(_ user: ArcfinSyncAdminUser, disableAccount: Bool) async {
        await run { try await client.sendCommand(.lock, userID: user.userId, disableAccount: disableAccount, credential: $0, authHeader: $1) }
    }

    private func run(_ call: (ServerCredential, String) async throws -> SecurityAdmin) async {
        guard let access = authManager.arcfinSyncDevicesSession else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            show(try await call(access.credential, access.header))
            HapticManager.success()
        } catch {
            actionError = AdminSyncError.message(error)
        }
    }

    /// A first key needs no confirming; replacing one does.
    private func ask(_ pending: SecurityConfirm) {
        if admin?.key == nil, case .newKey = pending {
            Task { await carryOut(pending) }
        } else {
            confirm = pending
        }
    }

    private func load() async {
        guard let access = authManager.arcfinSyncDevicesSession else { return }
        do {
            show(try await client.securityAdmin(credential: access.credential, authHeader: access.header))
        } catch {
            self.error = AdminSyncError.loadMessage()
        }
    }

    /// Lock then asks whether to disable the Jellyfin account too; Replace the Key asks for REPLACE typed.
    private func carryOut(_ pending: SecurityConfirm) async {
        switch pending {
        case .newKey(let key, _):
            await run { try await client.makeSigningKey(pem: key, credential: $0, authHeader: $1) }
            if key != nil, actionError == nil { pem = "" }
        case .command(.lock, let user):
            disableAccountFor = user
        case .replaceKey:
            typingReplace = true
        case .command(let kind, let user):
            await run { try await client.sendCommand(kind, userID: user.userId, credential: $0, authHeader: $1) }
        }
    }
}
