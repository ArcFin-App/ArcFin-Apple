// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

enum SecurityConfirm {
    case newKey(pem: String?, endsRotation: Bool)
    case command(ServerCommandKind, ArcfinSyncAdminUser)
    case replaceKey

    var title: LocalizedStringKey {
        switch self {
        case .newKey(_, true): "Use Your Own Key?"
        case .newKey: "Make a New Signing Key?"
        case .replaceKey: "Replace the signing key completely?"
        case .command(.resetPin, let user): "Clear \(user.name)'s PIN?"
        case .command(.lock, let user): "Lock \(user.name)?"
        case .command(.unlock, let user): "Unlock \(user.name)?"
        case .command(.wipe, let user), .command(.policy, let user): "Send this to \(user.name)?"
        }
    }

    var action: LocalizedStringKey {
        switch self {
        case .newKey(nil, _): "Make a New Key"
        case .newKey: "Use This Key"
        case .replaceKey: "Continue"
        case .command(.resetPin, _): "Clear PIN"
        case .command(.lock, _): "Lock"
        case .command(.unlock, _): "Unlock"
        case .command(.wipe, _), .command(.policy, _): "Send"
        }
    }

    var message: LocalizedStringKey {
        switch self {
        case .newKey(_, true): "Automatic rotation only works with keys the plugin makes, so it turns off. Devices move to your key automatically."
        case .newKey: "Devices move to it automatically."
        case .replaceKey: "This can't be undone. The old key stops working, and every device has to trust the new one again; over plain HTTP that means checking its fingerprint on each device."
        case .command(.resetPin, _): "It's cleared on all their devices. They can set a new one in Arcfin."
        case .command(.lock, _): "It's locked on all their devices. Arcfin won't open this profile until you unlock it. Older Arcfin versions can't show a lock, so they're signed out."
        case .command(.unlock, _): "It's unlocked on all their devices."
        case .command(.wipe, _), .command(.policy, _): ""
        }
    }

    var isDestructive: Bool {
        switch self {
        case .command(.unlock, _): false
        default: true
        }
    }
}

struct SigningKeySection: View {
    let key: SecurityAdmin.Key?
    let isBusy: Bool
    let onMake: () -> Void

    var body: some View {
        Section {
            if let key {
                LabeledContent {
                    Text(verbatim: key.fingerprint)
                        .font(.system(.footnote, design: .monospaced))
                        .multilineTextAlignment(.trailing)
                } label: {
                    TVRowLabelText(title: "Fingerprint")
                }
                .tvReadOnlyRow()
                LabeledContent {
                    Text(key.created, format: .relative(presentation: .named))
                } label: {
                    TVRowLabelText(title: "Made")
                }
                .tvReadOnlyRow()
            } else {
                Text("No key yet. Make one to send commands.")
                    .foregroundStyle(DT.Color.textSecondary)
                    .tvReadOnlyRow()
            }
            Button(key == nil ? LocalizedStringKey("Make a Key") : "Make a New Key", action: onMake)
                .formRowButton()
                .disabled(isBusy)
        } header: {
            Text("Signing Key")
        } footer: {
            if key != nil {
                Text("A device reaching this server over plain HTTP shows this fingerprint in Settings › Server; check it matches before confirming. Devices that already know this server move to a new key on their own: the old key signs the new one.")
            }
        }
    }
}

/// An admin's own P-256 key, pasted in. It's sent once and can't be read back.
struct OwnKeySection: View {
    @Binding var pem: String
    let isBusy: Bool
    let onUse: () -> Void

    var body: some View {
        Section {
            KeyTextEditor(text: $pem)
            Button("Use This Key", action: onUse)
                .formRowButton()
                .disabled(isBusy || pem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } header: {
            Text("Use Your Own Key")
        } footer: {
            Text("An EC P-256 private key in PEM, for example from openssl ecparam -name prime256v1 -genkey -noout | openssl pkcs8 -topk8 -nocrypt. It's stored encrypted and can't be read back. A key of your own can't be rotated automatically, so using one turns rotation off: for the strongest setup, let the plugin make and rotate its keys.")
        }
    }
}

/// One profile: whether it's locked, the last command sent to it, and the commands.
struct SecurityUserSection: View {
    let user: ArcfinSyncAdminUser
    let admin: SecurityAdmin
    let isBusy: Bool
    let onCommand: (ServerCommandKind) -> Void

    private var isLocked: Bool { admin.isLocked(user.userId) }

    private var lastCommand: LocalizedStringKey? {
        let id = ArcfinCompanionClient.normalized(user.userId)
        guard let last = admin.commands.first(where: { ArcfinCompanionClient.normalized($0.userId) == id && $0.kind != ServerCommandKind.policy.rawValue })
        else { return nil }
        switch ServerCommandKind(rawValue: last.kind) {
        case .resetPin: return "Last sent: PIN cleared"
        case .lock: return "Last sent: Locked"
        case .unlock: return "Last sent: Unlocked"
        case .wipe: return "Last sent: Device wiped"
        case .policy, nil: return "Last sent: \(last.kind)"
        }
    }

    var body: some View {
        Section {
            Button("Clear PIN") { onCommand(.resetPin) }
                .formRowButton()
            if isLocked {
                Button("Unlock") { onCommand(.unlock) }
                    .formRowButton()
            } else {
                Button(role: .destructive) { onCommand(.lock) } label: {
                    Text("Lock")
                        .foregroundStyle(DT.Color.palette("F43F5E"))
                }
                .formRowButton()
            }
        } header: {
            HStack(spacing: DT.Spacing.xs) {
                Text(verbatim: user.name)
                if isLocked {
                    AdminBadge("Locked", isProminent: true)
                }
                if admin.isDisabled(user.userId) {
                    AdminBadge("Account disabled", isProminent: true)
                }
            }
        } footer: {
            if let lastCommand { Text(lastCommand) }
        }
        .disabled(isBusy)
    }
}

/// For a key that may have leaked: a new key the old one doesn't vouch for.
struct ReplaceKeySection: View {
    let isBusy: Bool
    let onReplace: () -> Void

    var body: some View {
        Section {
            Button(role: .destructive, action: onReplace) {
                Text("Replace the Key Completely")
                    .foregroundStyle(DT.Color.palette("F43F5E"))
            }
            .formRowButton()
            .disabled(isBusy)
        } footer: {
            Text("For a key you think has leaked. Makes an entirely new key that the old one doesn't vouch for, and deletes the record of past keys, so the old key can't move any device anywhere. Locks and other commands stay in force. Every device has to trust the new key again: over HTTPS that happens by itself, and over plain HTTP someone has to check the new fingerprint in Settings › Server on that device. Until then, those devices ignore your commands.")
        }
    }
}

/// The last step before something that can't be undone: typing a word, such as REPLACE or WIPE.
struct TypedConfirmSheet: View {
    @Environment(\.dismiss) private var dismiss
    let word: String
    let title: LocalizedStringKey
    let action: LocalizedStringKey
    let onConfirm: () -> Void
    @State private var typed = ""

    var body: some View {
        NavigationStack {
            SettingsForm {
                Section {
                    TextField("Type \(word)", text: $typed)
                        .autocorrectionDisabled()
                        .tvListRow()
                } footer: {
                    Text("Type \(word) to confirm.")
                }
                Section {
                    Button(role: .destructive) {
                        dismiss()
                        onConfirm()
                    } label: {
                        Text(action)
                            .foregroundStyle(DT.Color.palette("F43F5E"))
                    }
                    .formRowButton()
                    .disabled(typed.trimmingCharacters(in: .whitespaces) != word)
                    Button("Cancel", role: .cancel) { dismiss() }
                        .formRowButton()
                }
            }
            .arcfinListStyle()
            .screenBackground()
            .sheetTitle(title)
        }
    }
}
