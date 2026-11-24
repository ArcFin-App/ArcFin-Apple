// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import JellyfinAPI

/// Shown in place of the app outside the hours the profile's parental controls allow. The
/// server refuses the profile's requests then too; this says why, and when it opens again.
struct AccessScheduleView: View {
    var onSwitchProfile: () -> Void

    @Environment(AuthManager.self) private var authManager
    @State private var settingPIN: ServerCredential?
    @State private var changingPIN: ServerCredential?
    private var rules: ProfileRules { .shared }
    private var block: ServerCompanion.Block? { ServerCompanion.shared.block() }

    private var title: LocalizedStringKey {
        switch block {
        case .awaitingTrust: "Waiting for Approval"
        case .pinRequired: "Set a PIN to Continue"
        case .pinTooShort: "Choose a Longer PIN"
        case .httpsRequired: "Secure Connection Needed"
        default: "Not Available Right Now"
        }
    }

    private var symbol: String {
        switch block {
        case .awaitingTrust: "checkmark.shield"
        case .pinRequired: "lock.circle"
        case .pinTooShort: "lock.rotation"
        case .httpsRequired: "lock.trianglebadge.exclamationmark"
        case .adminLock: "lock.fill"
        default: "moon.zzz.fill"
        }
    }

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 52))
                .foregroundStyle(DT.Color.accent)
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text(title)
                    .font(.title2.bold())
                    .foregroundStyle(DT.Color.textPrimary)
                Text(message)
                    .font(.callout)
                    .foregroundStyle(DT.Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
            if case .awaitingTrust(let code?) = block {
                Text(code)
                    .font(.system(size: 44, weight: .bold, design: .monospaced))
                    .tracking(6)
                    .foregroundStyle(DT.Color.textPrimary)
                    .accessibilityLabel(Text("Code \(code.map(String.init).joined(separator: " "))"))
            }
            if case .pinTooShort = block, let credential = authManager.state.credential {
                Button { changingPIN = credential } label: {
                    Text("Change PIN").font(.headline).frame(maxWidth: 340, minHeight: 30)
                }
                .buttonStyle(.glassProminent)
                .tint(DT.Color.accent)
                .foregroundStyle(DT.Color.onAccent)
                .controlSize(.large)
            }
            if block == .pinRequired, let credential = authManager.state.credential {
                Button { settingPIN = credential } label: {
                    Text("Set PIN").font(.headline).frame(maxWidth: 340, minHeight: 30)
                }
                .buttonStyle(.glassProminent)
                .tint(DT.Color.accent)
                .foregroundStyle(DT.Color.onAccent)
                .controlSize(.large)
            }
            if !rules.policy.accessSchedules.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Allowed times")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(DT.Color.textSecondary)
                    ForEach(Array(rules.policy.accessSchedules.enumerated()), id: \.offset) { _, schedule in
                        Label(ProfileRules.describe(schedule), systemImage: "clock")
                            .font(.callout)
                            .foregroundStyle(DT.Color.textPrimary)
                    }
                }
                .frame(maxWidth: 340, alignment: .leading)
                .padding(16)
                .background(DT.Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            Spacer()
            if authManager.profiles.count > 1 {
                Button(action: onSwitchProfile) {
                    Text("Switch Profile").font(.headline).frame(maxWidth: 340, minHeight: 30)
                }
                .buttonStyle(.glassProminent)
                .tint(DT.Color.accent)
                .foregroundStyle(DT.Color.onAccent)
                .controlSize(.large)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .screenBackground()
        .appSheet(item: $settingPIN) { profile in
            PINFlowSheet(profile: profile, flow: .setNew) {
                await ServerCompanion.shared.refreshPINState(authManager: authManager)
            }
        }
        .appSheet(item: $changingPIN) { profile in
            PINFlowSheet(profile: profile, flow: .changeVerifyCurrent) {
                await ServerCompanion.shared.refreshPINState(authManager: authManager)
            }
        }
    }

    private var message: String {
        let name = rules.profile?.name ?? String(localized: "This profile")
        let companion = ServerCompanion.shared
        switch block {
        case .awaitingTrust(let code):
            return code.map { String(localized: "Open Arcfin on one of your trusted iPhones or iPads to approve this device. Code: \($0).") }
                ?? String(localized: "Open Arcfin on one of your trusted iPhones or iPads to approve this device.")
        case .adminLock(let reason) where reason == "pinTries":
            return String(localized: "Locked after too many wrong PINs. Ask your server's admin to unlock it.")
        case .pinRequired:
            return String(localized: "Your server's admin requires a PIN for this profile.")
        case .pinTooShort(let minimum):
            return String(localized: "Your server's admin now requires a PIN of at least \(minimum) digits. Enter your current PIN, then choose a new one.")
        case .httpsRequired(let secure):
            let base = String(localized: "Your server's admin requires a secure connection away from home. Connect to your home network, or ask your admin for the server's HTTPS address.")
            return secure.map { base + " " + String(localized: "This profile has an HTTPS address saved: \($0.host() ?? $0.absoluteString).") } ?? base
        default:
            break
        }
        if companion.isLocked(authManager.state.credential?.id) {
            return String(localized: "Your server's admin has locked \(name). Ask them to unlock it.")
        }
        if !companion.allowsWatching(), let status = companion.watchTime {
            let until = status.until.map { next in
                Calendar.current.isDate(next, inSameDayAs: Date())
                    ? next.formatted(date: .omitted, time: .shortened)
                    : next.formatted(.dateTime.weekday(.wide).hour().minute())
            }
            if status.isBedtime, let until { return String(localized: "It's bedtime for \(name). Watching starts again at \(until).") }
            return String(localized: "\(name) has used today's watch time.")
        }
        guard let next = rules.nextAllowedTime() else {
            return String(localized: "\(name) can't use this server at the moment.")
        }
        let when = Calendar.current.isDate(next, inSameDayAs: Date())
            ? next.formatted(date: .omitted, time: .shortened)
            : next.formatted(.dateTime.weekday(.wide).hour().minute())
        return String(localized: "\(name) can watch again from \(when).")
    }
}
