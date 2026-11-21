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
        SettingsForm {
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
        .task { hasPIN = await authManager.storedPIN(for: profile.id) != .none }
        .appSheet(item: $pinFlow) { flow in
            PINFlowSheet(profile: profile, flow: flow) {
                hasPIN = await authManager.storedPIN(for: profile.id) != .none
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

    enum Stage { case first, second, confirmNew }

    private var firstTitle: String {
        switch flow {
        case .setNew:                   return String(localized: "Enter new PIN")
        case .changeVerifyCurrent:      return String(localized: "Enter current PIN")
        case .disableVerifyCurrent:     return String(localized: "Enter PIN to disable")
        }
    }

    private var secondTitle: String {
        switch flow {
        case .setNew:              return String(localized: "Confirm PIN")
        case .changeVerifyCurrent: return String(localized: "Enter new PIN")
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
            .task {
                guard flow != .setNew else { return }
                let stored = await authManager.storedPIN(for: profile.id)
                errorMessage = AuthManager.PINCheck.message(opening: stored, for: profile.id)
            }

        case .second:
            PINPadView(
                title: secondTitle,
                subtitle: profile.displayName,
                errorMessage: errorMessage,
                resetToken: resetToken,
                onCancel: { stage = .first; errorMessage = nil },
                onComplete: handleSecond
            )

        case .confirmNew:
            PINPadView(
                title: String(localized: "Confirm PIN"),
                subtitle: profile.displayName,
                errorMessage: errorMessage,
                resetToken: resetToken,
                onCancel: { stage = .second; errorMessage = nil },
                onComplete: handleConfirmNew
            )
        }
    }

    private func handleFirst(_ entered: String) {
        switch flow {
        case .setNew:
            pendingPIN = entered
            errorMessage = nil
            stage = .second

        case .changeVerifyCurrent, .disableVerifyCurrent:
            Task {
                let result = await authManager.checkPIN(entered, for: profile.id)
                guard stage == .first else { return }
                guard result == .correct else {
                    errorMessage = result.message
                    resetToken += 1
                    return
                }
                errorMessage = nil
                if flow == .changeVerifyCurrent {
                    pendingPIN = nil
                    stage = .second
                } else {
                    authManager.removePin(for: profile.id)
                    await onDone()
                    dismiss()
                }
            }
        }
    }

    private func handleSecond(_ entered: String) {
        switch flow {
        case .setNew:
            if entered == pendingPIN {
                Task {
                    // Offered before the screen had read the PIN: one already set is only
                    // changed with it.
                    if await authManager.storedPIN(for: profile.id) == .none {
                        authManager.savePin(entered, for: profile.id)
                    }
                    await onDone()
                    dismiss()
                }
            } else {
                errorMessage = String(localized: "PINs don't match")
                resetToken += 1
            }

        case .changeVerifyCurrent:
            pendingPIN = entered
            errorMessage = nil
            stage = .confirmNew

        default: break
        }
    }

    private func handleConfirmNew(_ entered: String) {
        guard entered == pendingPIN else {
            pendingPIN = nil
            errorMessage = String(localized: "PINs don't match")
            stage = .second
            return
        }
        authManager.savePin(entered, for: profile.id)
        Task { await onDone(); dismiss() }
    }
}

// MARK: - PIN entry sheet (for switching profiles)

struct PINEntrySheet: View {
    let title: String
    var subtitle: String? = nil
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
