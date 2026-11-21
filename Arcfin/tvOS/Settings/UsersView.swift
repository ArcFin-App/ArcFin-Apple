// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore

struct UsersView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    @State private var pins = ProfilePINStates()
    @State private var pinTask: TVPINTask?
    @State private var signOutTarget: ServerCredential?

    private var activeID: UUID? { authManager.state.credential?.id }

    private var otherProfiles: [ServerCredential] {
        authManager.profiles.filter { $0.id != activeID }
    }

    /// The profile in use, its PIN and Sign Out on the left; the others to switch to and Add
    /// Profile on the right, across the screen.
    var body: some View {
        LoginSplitPage {
            Text("Profiles")
                .font(.title.bold())
                .foregroundStyle(DT.Color.textPrimary)
            if let active = authManager.state.credential {
                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("Current Profile")
                    tvProfileRow(active, isActive: true)
                        .padding(.horizontal, 24)
                }
                VStack(alignment: .leading, spacing: 8) {
                    if pins.hasPIN(active.id) {
                        Button("Change PIN") { pinTask = TVPINTask(profile: active, kind: .change) }
                        Button("Remove PIN") { pinTask = TVPINTask(profile: active, kind: .remove) }
                    } else {
                        Button("Set a PIN") { pinTask = TVPINTask(profile: active, kind: .set) }
                    }
                    Button(role: .destructive) {
                        signOutTarget = active
                    } label: {
                        Text("Sign Out").foregroundStyle(DT.Color.palette("F43F5E"))
                    }
                }
                .buttonStyle(TVSettingsRowStyle())
                Text("With a PIN, Arcfin asks for it when it opens and before switching to this profile.")
                    .font(.footnote)
                    .foregroundStyle(DT.Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } trailing: {
            VStack(alignment: .leading, spacing: 8) {
                if !otherProfiles.isEmpty {
                    sectionLabel("Switch To")
                    ForEach(otherProfiles) { profile in
                        Button {
                            choose(profile)
                        } label: {
                            tvProfileRow(profile, isActive: false)
                        }
                    }
                }
                NavigationLink {
                    TVAddProfileFlowView(onProfileAdded: { dismiss() })
                } label: {
                    Label("Add Profile", systemImage: "plus")
                }
            }
            .buttonStyle(TVSettingsRowStyle())
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await pins.load(authManager: authManager) }
        .confirmingProfileRemoval($signOutTarget, signingOut: true,
                                  isLastProfile: authManager.profiles.count <= 1) { _ in
            authManager.signOut()
            dismiss()
        }
        .fullScreenCover(item: $pinTask) { task in
            TVPINFlow(task: task) { switched in
                pinTask = nil
                Task { await pins.load(authManager: authManager) }
                if switched { dismiss() }
            }
        }
    }

    /// Decided from the PIN as read now; `pins` only draws the locks and may not have loaded.
    private func choose(_ profile: ServerCredential) {
        Task {
            guard await authManager.storedPIN(for: profile.id) == .none else {
                pinTask = TVPINTask(profile: profile, kind: .unlock)
                return
            }
            authManager.switchTo(profile)
            dismiss()
        }
    }

    private func tvProfileRow(_ cred: ServerCredential, isActive: Bool) -> some View {
        let initials = cred.displayName
            .split(separator: " ").prefix(2)
            .compactMap { $0.first.map { String($0).uppercased() } }
            .joined()

        return HStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [DT.Color.accent, DT.Color.accentDeep],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 52 * DT.Scale.font, height: 52 * DT.Scale.font)
                    .shadow(color: isActive ? DT.Color.accent.opacity(0.4) : .clear, radius: 8)
                Text(initials)
                    .scaledFont(size: 18, weight: .bold, design: .rounded)
                    .foregroundStyle(DT.Color.onAccent)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(cred.displayName)
                    .scaledFont(size: 18, weight: .semibold)
                Text(cred.baseURL.host ?? cred.baseURL.absoluteString)
                    .scaledFont(size: 14)
                    .opacity(0.6)
                    .lineLimit(1)
            }

            Spacer()

            if pins.hasPIN(cred.id) {
                Image(systemName: "lock.fill")
                    .scaledFont(size: 18)
                    .opacity(0.6)
                    .accessibilityLabel("PIN protected")
            }
            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .scaledFont(size: 26)
                    .foregroundStyle(DT.Color.accent)
            }
        }
        .padding(.vertical, 8)
    }

    private func sectionLabel(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(.caption, design: .default, weight: .semibold))
            .foregroundStyle(DT.Color.textSecondary)
            .textCase(nil)
    }
}

// MARK: - tvOS PINs

struct TVPINTask: Identifiable {
    enum Kind { case set, change, remove, unlock }
    let id = UUID()
    let profile: ServerCredential
    let kind: Kind
}

/// Setting, changing and removing a profile's PIN, and entering it to switch to that profile.
private struct TVPINFlow: View {
    let task: TVPINTask
    /// True when the flow ended by switching to the profile.
    let onDone: (Bool) -> Void

    @Environment(AuthManager.self) private var authManager
    @State private var verified = false
    @State private var firstEntry: String?
    @State private var errorMessage: String?
    @State private var resetToken = 0

    private var title: String {
        switch task.kind {
        case .unlock: String(localized: "Enter PIN")
        case .remove: String(localized: "Enter PIN to remove it")
        case .change where !verified: String(localized: "Enter current PIN")
        case .set, .change: firstEntry == nil ? String(localized: "Enter a new PIN") : String(localized: "Confirm the PIN")
        }
    }

    var body: some View {
        PINPadView(
            title: title,
            subtitle: task.profile.displayName,
            errorMessage: errorMessage,
            resetToken: resetToken,
            onCancel: { onDone(false) },
            onComplete: handle
        )
        .id(title)
        .task {
            guard needsCurrent else { return }
            let stored = await authManager.storedPIN(for: task.profile.id)
            errorMessage = AuthManager.PINCheck.message(opening: stored, for: task.profile.id)
        }
    }

    private var needsCurrent: Bool {
        task.kind == .unlock || task.kind == .remove || (task.kind == .change && !verified)
    }

    private func handle(_ entered: String) {
        if needsCurrent {
            Task { await checkCurrent(entered) }
            return
        }
        guard let first = firstEntry else {
            firstEntry = entered
            errorMessage = nil
            return
        }
        guard entered == first else {
            firstEntry = nil
            return fail(String(localized: "PINs don't match"))
        }
        Task {
            // Offered before the list had read the PIN: one already set is only changed with it.
            var canSave = true
            if task.kind == .set { canSave = await authManager.storedPIN(for: task.profile.id) == .none }
            if canSave { authManager.savePin(entered, for: task.profile.id) }
            onDone(false)
        }
    }

    private func checkCurrent(_ entered: String) async {
        let result = await authManager.checkPIN(entered, for: task.profile.id)
        guard needsCurrent else { return }
        guard result == .correct else { return fail(result.message) }
        errorMessage = nil
        switch task.kind {
        case .unlock:
            authManager.switchTo(task.profile)
            onDone(true)
        case .remove:
            authManager.removePin(for: task.profile.id)
            onDone(false)
        default:
            verified = true
        }
    }

    private func fail(_ message: String?) {
        errorMessage = message
        resetToken += 1
    }
}

// MARK: - tvOS add-profile flow (pushed within UsersView's NavigationStack, full screen)

private struct TVAddProfileFlowView: View {
    var onProfileAdded: () -> Void

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
                    onProfileAdded()
                }
            )
            .toolbar(.hidden, for: .navigationBar)
            // Another profile can be added from Arcfin on an iPhone or iPad too (#481).
            .hostsNearbySetup(onAdded: onProfileAdded)
        }
    }
}
