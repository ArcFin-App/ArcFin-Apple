// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore

// MARK: - Profile row content

struct ProfileRowContent: View {
    let profile: ServerCredential
    let isActive: Bool
    let hasPIN: Bool

    var body: some View {
        HStack(spacing: 12) {
            ProfileAvatar(profile: profile)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName)
                    .foregroundStyle(DT.Color.textPrimary)
                Text(profile.baseURL.host ?? profile.baseURL.absoluteString)
                    .font(.subheadline)
                    .foregroundStyle(DT.Color.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            if hasPIN {
                Image(systemName: "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(DT.Color.textSecondary)
                    .accessibilityLabel("PIN protected")
            }
            if isActive {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DT.Color.accent)
                    .accessibilityLabel("Current profile")
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Profile detail (PIN management)

struct ProfileDetailView: View {
    let profile: ServerCredential
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    @State private var hasPIN = false
    @State private var pinFlow: PINFlow? = nil
    @State private var removeTarget: ServerCredential?

    enum PINFlow: Identifiable {
        case setNew, changeVerifyCurrent, disableVerifyCurrent
        var id: Int { hashValue }
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Name") {
                    Text(profile.displayName).foregroundStyle(.secondary)
                }
                LabeledContent("Server") {
                    Text(profile.baseURL.host ?? profile.baseURL.absoluteString)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } header: { Text("Profile") }

            Section {
                if hasPIN {
                    Button("Change PIN") { pinFlow = .changeVerifyCurrent }
                    Button("Turn Off PIN", role: .destructive) {
                        pinFlow = .disableVerifyCurrent
                    }
                } else {
                    Button("Turn On PIN") { pinFlow = .setNew }
                }
            } header: {
                Text("Security")
            } footer: {
                Text(hasPIN
                     ? "A 4-digit PIN is required when switching to this profile."
                     : "Add a PIN to require verification before switching to this profile.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }

            if authManager.state.credential?.id != profile.id {
                Section {
                    Button("Remove Profile", role: .destructive) {
                        removeTarget = profile
                    }
                }
            }
        }
        .confirmingProfileRemoval($removeTarget, signingOut: false, isLastProfile: false) { target in
            authManager.removeProfile(id: target.id)
            dismiss()
        }
        .arcfinListStyle()
        .screenBackground()
        .tint(DT.Color.accent)
        .navigationTitle(profile.displayName)
        .inlineNavigationTitle()
        .task { hasPIN = await authManager.pin(for: profile.id) != nil }
        .sheet(item: $pinFlow) { flow in
            PINFlowSheet(profile: profile, flow: flow) {
                hasPIN = await authManager.pin(for: profile.id) != nil
            }
        }
    }

}

// MARK: - PIN flow sheet (set / change / disable)

private struct PINFlowSheet: View {
    let profile: ServerCredential
    let flow: ProfileDetailView.PINFlow
    var onDone: () async -> Void

    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    // Stage machine
    @State private var stage: Stage = .first
    @State private var pendingPIN: String? = nil
    @State private var resetToken = 0
    @State private var errorMessage: String? = nil
    @State private var storedPIN: String? = nil

    enum Stage { case first, second }

    private var firstTitle: String {
        switch flow {
        case .setNew:                   return "Enter new PIN"
        case .changeVerifyCurrent:      return "Enter current PIN"
        case .disableVerifyCurrent:     return "Enter PIN to disable"
        }
    }

    private var secondTitle: String {
        switch flow {
        case .setNew:              return "Confirm PIN"
        case .changeVerifyCurrent: return "Enter new PIN"
        default:                   return ""
        }
    }

    var body: some View {
        switch stage {
        case .first:
            PINPadView(
                title: firstTitle,
                subtitle: profile.displayName,
                errorMessage: errorMessage,
                resetToken: resetToken,
                onCancel: { dismiss() },
                onComplete: handleFirst
            )
            .task { storedPIN = await authManager.pin(for: profile.id) }

        case .second:
            PINPadView(
                title: secondTitle,
                subtitle: profile.displayName,
                errorMessage: errorMessage,
                resetToken: resetToken,
                onCancel: { stage = .first; errorMessage = nil },
                onComplete: handleSecond
            )
        }
    }

    private func handleFirst(_ entered: String) {
        switch flow {
        case .setNew:
            pendingPIN = entered
            errorMessage = nil
            stage = .second

        case .changeVerifyCurrent:
            if entered == storedPIN {
                pendingPIN = nil
                errorMessage = nil
                stage = .second
            } else {
                errorMessage = "Incorrect PIN"
                resetToken += 1
            }

        case .disableVerifyCurrent:
            if entered == storedPIN {
                authManager.removePin(for: profile.id)
                Task { await onDone(); dismiss() }
            } else {
                errorMessage = "Incorrect PIN"
                resetToken += 1
            }
        }
    }

    private func handleSecond(_ entered: String) {
        switch flow {
        case .setNew:
            if entered == pendingPIN {
                authManager.savePin(entered, for: profile.id)
                Task { await onDone(); dismiss() }
            } else {
                errorMessage = "PINs don't match"
                resetToken += 1
            }

        case .changeVerifyCurrent:
            // Second stage = confirm new PIN (no repeat needed for simplicity — save directly)
            authManager.savePin(entered, for: profile.id)
            Task { await onDone(); dismiss() }

        default: break
        }
    }
}

// MARK: - PIN entry sheet (for switching profiles)

struct PINEntrySheet: View {
    let title: String
    var subtitle: String? = nil
    let storedPIN: String?
    var resetToken: Int
    var errorMessage: String?
    var onCancel: () -> Void
    var onComplete: (String) -> Void

    var body: some View {
        PINPadView(
            title: title,
            subtitle: subtitle,
            errorMessage: errorMessage,
            resetToken: resetToken,
            onCancel: onCancel,
            onComplete: onComplete
        )
    }
}

// MARK: - Add profile flow (pushed inside UsersView's NavigationStack)

struct AddProfileFlowView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let cred = authManager.state.credential {
            AuthView(
                serverURL: cred.baseURL,
                serverName: cred.baseURL.host ?? cred.baseURL.absoluteString,
                onBack: { dismiss() },
                onAuthenticated: { credential in
                    authManager.addProfile(credential)
                    dismiss()
                }
            )
            .navigationBarBackButtonHidden(true)
        }
    }
}
