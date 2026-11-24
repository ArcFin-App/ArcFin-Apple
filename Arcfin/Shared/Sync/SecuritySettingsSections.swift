// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

/// What happens to a device that hasn't picked up the current key: off, signOut or lock, and
/// for one person also inherit.
enum StaleAction {
    static let everyone = ["off", "signOut", "lock"]
    static let oneUser = ["inherit"] + everyone

    static func label(_ action: String) -> Text {
        switch action {
        case "inherit": Text("Same as Everyone")
        case "off": Text("Off")
        case "signOut": Text("Sign Them Out")
        case "lock": Text("Sign Them Out and Lock Arcfin")
        default: Text(verbatim: action)
        }
    }
}

/// Whether devices on plain HTTP trust the key without anyone checking its fingerprint.
struct PlainHTTPSection: View {
    let isOn: Bool
    let isBusy: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        AdminIntroSection(text: "A device that reaches this server over plain HTTP can't be sure who answered, so it asks someone to check the key's fingerprint before it carries out your commands. It checks by itself where it can: if the app also has this server's HTTPS address saved, it fetches the key from there and trusts it when they match. Anyone can compare with the fingerprint shown in Settings › Server on a device that already trusts the key.")
        Section {
            Toggle(isOn: Binding(get: { isOn }, set: onChange)) {
                TVRowLabelText(title: "Trust the Key over Plain HTTP Without Checking")
            }
            .tvListRow()
            .disabled(isBusy)
        } header: {
            Text("Devices on Plain HTTP")
        } footer: {
            Text("For households where no one will check. This setting reaches devices over plain HTTP too, so on a network you don't trust it could be faked: keep it for your home network.")
        }
    }
}

struct RotationSection: View {
    @Binding var settings: SecuritySettings
    let admin: SecurityAdmin

    private var isImported: Bool { admin.key?.imported == true }

    var body: some View {
        Section {
            Toggle(isOn: $settings.autoRotate) {
                TVRowLabelText(title: "Rotate the Key Automatically")
            }
            .tvListRow()
            .disabled(isImported)
            if settings.autoRotate && !isImported {
                WholeNumberRow(title: "Every (Days)", prompt: "1", value: Binding(
                    get: { settings.rotateEveryDays }, set: { settings.rotateEveryDays = max($0 ?? 1, 1) }), maximum: 365)
            }
            if isImported {
                Text("Your own key is in use, so it isn't rotated. Make a key here to turn rotation on.")
                    .foregroundStyle(DT.Color.textSecondary)
                    .tvReadOnlyRow()
            } else if let next = admin.nextRotation {
                Text("Next new key: \(LiveTime.when(next)).")
                    .foregroundStyle(DT.Color.textSecondary)
                    .tvReadOnlyRow()
            }
        } header: {
            Text("Automatic Rotation")
        } footer: {
            Text("Makes a new key on a schedule, each signed by the last, so devices move over by themselves. A device that falls behind can't use an old key for long. The key is kept on this server, so rotation doesn't protect against someone who already has the server; what it does is put a limit on how long any one key is trusted. It only works with a key the plugin made: using your own key turns it off.")
        }
    }
}

struct StaleRuleSection: View {
    @Binding var settings: SecuritySettings

    var body: some View {
        Section {
            SettingsPicker("When a Device Falls Behind", selection: $settings.staleAction, options: StaleAction.everyone) {
                StaleAction.label($0)
            }
            if settings.staleAction != "off" {
                WholeNumberRow(title: "After (Days)", prompt: "14", value: Binding(
                    get: { settings.staleAfterDays }, set: { settings.staleAfterDays = max($0 ?? 1, 1) }), maximum: 3650)
            }
        } header: {
            Text("Devices That Fall Behind")
        } footer: {
            Text("Every Arcfin device tells the server which key it holds when it syncs. One that hasn't picked up the current key for this long is signed out, so it has to sign in again; or signed out and locked, so Arcfin won't open on it until you unlock it below. Only Arcfin devices that have checked in are counted, and the count starts from when you turn this on.")
        }
    }
}

/// Arcfin from before signed commands: it can't check in, follow key changes or show a lock.
struct OlderAppsSection: View {
    @Binding var settings: SecuritySettings

    var body: some View {
        Section {
            SettingsPicker("Older Arcfin Versions", selection: $settings.olderApps, options: ["allow", "signOut"]) { value in
                switch value {
                case "signOut": Text("Sign Them Out a Day After They're First Seen")
                case "allow": Text("Allow Them")
                default: Text(verbatim: value)
                }
            }
            Text("Each device's key status, and older Arcfin versions, are under Users & Devices, with the person they belong to.")
                .font(.subheadline)
                .foregroundStyle(DT.Color.textSecondary)
                .tvReadOnlyRow()
        } header: {
            Text("Older Arcfin Versions")
        } footer: {
            Text("Arcfin from before 0.5.0 build 3's security features can't check in, follow key changes or show a lock. Arcfin Sync tells them apart by whether they check in, not by version number, since every build of 0.5.0 reports the same version. Someone you lock is signed out of an older Arcfin straight away either way; to keep them off the server in every app, disable their account when you lock them.")
        }
    }
}
