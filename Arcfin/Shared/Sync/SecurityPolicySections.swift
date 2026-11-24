// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

/// Signed commands and everything built on them. Off until the admin turns it on.
struct SignedCommandsSection: View {
    let isOn: Bool
    let isBusy: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { isOn }, set: onChange)) {
                TVRowLabelText(title: "Signed Commands")
            }
            .tvListRow()
            .disabled(isBusy)
        } footer: {
            Text("Turns on the signing key, PIN clearing, locks, wiping devices and the rules below. Until it's on, no key is made and devices don't check in.")
        }
    }
}

struct TrustedDevicesSection: View {
    @Binding var settings: SecuritySettings

    var body: some View {
        Section {
            Toggle(isOn: $settings.requireTrustedDevices) {
                TVRowLabelText(title: "New Arcfin Devices Need Approving")
            }
            .tvListRow()
        } header: {
            Text("Trusted Devices")
        } footer: {
            Text("A new device shows a code and waits; the person approves it on one of their trusted iPhones or iPads, or you approve it under Users & Devices. Devices already signed in when you turn this on are trusted, and so is someone's first device.")
        }
    }
}

struct HTTPSAwaySection: View {
    @Binding var settings: SecuritySettings

    var body: some View {
        Section {
            Toggle(isOn: $settings.requireHttpsAway) {
                TVRowLabelText(title: "Require HTTPS Away from Home")
            }
            .tvListRow()
        } footer: {
            Text("Arcfin won't use plain HTTP unless the address is on the local network (like 192.168.x.x or a .local name). This rule is signed, so nothing on the network can turn it off.")
        }
    }
}

struct PinRulesSection: View {
    @Binding var pins: PinRules
    let users: [ArcfinSyncAdminUser]

    private static let lengths = Array(4...PinRules.longest)
    private static let tries: [Int?] = [nil] + Array(3...10).map(Optional.some)

    var body: some View {
        Section {
            SettingsPicker("Require a PIN For", selection: $pins.requiredFor, options: ["none", "everyone", "chosen"]) { value in
                switch value {
                case "everyone": Text("Everyone")
                case "chosen": Text("Chosen People")
                default: Text("None")
                }
            }
            if pins.requiredFor == "chosen" {
                ForEach(users) { user in
                    Toggle(isOn: chosen(user.userId)) {
                        TVRowLabelText(verbatim: user.name)
                    }
                    .tvListRow()
                }
            }
            SettingsPicker("Minimum Length", selection: $pins.minLength, options: Self.lengths) { Text("\($0) digits") }
            SettingsPicker("Lock After Wrong Tries", selection: $pins.maxTries, options: Self.tries) { value in
                if let value { Text("\(value) tries") } else { Text("Off") }
            }
        } header: {
            Text("PIN Rules")
        } footer: {
            Text("The longest a PIN can be is 8 digits. With a number of tries set, a profile locks on that device after that many wrong PINs, until you unlock it under Users & Devices.")
        }
    }

    private func chosen(_ userID: String) -> Binding<Bool> {
        let id = ArcfinCompanionClient.normalized(userID)
        return Binding(
            get: { pins.users.contains { ArcfinCompanionClient.normalized($0) == id } },
            set: { on in
                pins.users.removeAll { ArcfinCompanionClient.normalized($0) == id }
                if on { pins.users.append(userID) }
            })
    }
}

/// Each person's own security rules: trusted devices, and devices that fall behind.
struct SecurityPeopleSection: View {
    @Binding var settings: SecuritySettings
    let users: [ArcfinSyncAdminUser]

    var body: some View {
        Section {
            ForEach(users) { user in
                NavigationLink {
                    SecurityPersonView(name: user.name, override: override(user.userId)).tvSettingsPage()
                } label: {
                    TVRowLabelText(verbatim: user.name, detail: "\(summary(user.userId))")
                }
                .tvListRow()
            }
        } header: {
            Text("For One Person")
        }
    }

    private func index(_ userID: String) -> Int? {
        settings.users.firstIndex { ArcfinCompanionClient.normalized($0.userId) == ArcfinCompanionClient.normalized(userID) }
    }

    private func override(_ userID: String) -> Binding<SecuritySettings.UserOverride> {
        Binding(
            get: { index(userID).map { settings.users[$0] } ?? SecuritySettings.UserOverride(userId: userID) },
            set: { value in
                if let i = index(userID) { settings.users[i] = value } else { settings.users.append(value) }
            })
    }

    private func summary(_ userID: String) -> String {
        let own = override(userID).wrappedValue
        var parts: [String] = []
        switch own.trustedDevices {
        case "on": parts.append(String(localized: "New devices need approving"))
        case "off": parts.append(String(localized: "New devices don't need approving"))
        default: break
        }
        if own.staleAction != "inherit" || own.staleAfterDays != nil {
            let action: String = switch own.staleAction {
            case "off": String(localized: "Falling behind: off")
            case "signOut": String(localized: "Falling behind: sign out")
            case "lock": String(localized: "Falling behind: sign out and lock")
            default: String(localized: "Falling behind: same as everyone")
            }
            parts.append(own.staleAfterDays.map { action + " " + String(localized: "after \($0) days") } ?? action)
        }
        return parts.isEmpty ? String(localized: "Same as Everyone") : parts.joined(separator: " · ")
    }
}

/// One person's own rules. Saved with the rest on the Security page.
private struct SecurityPersonView: View {
    let name: String
    @Binding var override: SecuritySettings.UserOverride

    var body: some View {
        SettingsForm {
            Section {
                SettingsPicker("New Devices Need Approving", selection: $override.trustedDevices, options: ["inherit", "on", "off"]) { value in
                    switch value {
                    case "on": Text("On")
                    case "off": Text("Off")
                    default: Text("Same as Everyone")
                    }
                }
            } header: {
                Text("Trusted Devices")
            }
            Section {
                SettingsPicker("When a Device Falls Behind", selection: $override.staleAction, options: StaleAction.oneUser) {
                    StaleAction.label($0)
                }
                if override.staleAction != "off" {
                    WholeNumberRow(title: "After (Days)", prompt: "Same", value: Binding(
                        get: { override.staleAfterDays }, set: { override.staleAfterDays = $0.map { max($0, 1) } }), maximum: 3650)
                }
            } header: {
                Text("Devices That Fall Behind")
            } footer: {
                Text("Leave the days empty to use everyone's. Save on the Security page to keep the change.")
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge(name)
    }
}
