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

    var body: some View {
        List {
            if let active = authManager.state.credential {
                Section {
                    tvProfileRow(active, isActive: true)
                        .listRowBackground(Color.clear)
                        .focusEffectDisabled()
                    if pins.hasPIN(active.id) {
                        Button("Change PIN") { pinTask = TVPINTask(profile: active, kind: .change) }
                            .tvListRow()
                        Button("Remove PIN") { pinTask = TVPINTask(profile: active, kind: .remove) }
                            .tvListRow()
                    } else {
                        Button("Set a PIN") { pinTask = TVPINTask(profile: active, kind: .set) }
                            .tvListRow()
                    }
                } header: { sectionLabel("Current Profile") } footer: {
                    Text("With a PIN, Arcfin asks for it when it opens and before switching to this profile.")
                }
            }

            if !otherProfiles.isEmpty {
                Section {
                    ForEach(otherProfiles) { profile in
                        Button {
                            if pins.hasPIN(profile.id) {
                                pinTask = TVPINTask(profile: profile, kind: .unlock)
                            } else {
                                authManager.switchTo(profile)
                                dismiss()
                            }
                        } label: {
                            tvProfileRow(profile, isActive: false)
                        }
                        .listRowBackground(Color.clear)
                    }
                } header: { sectionLabel("Switch To") }
            }

            Section {
                NavigationLink {
                    TVAddProfileFlowView(onProfileAdded: { dismiss() })
                } label: {
                    Text("Add Profile")
                        .foregroundStyle(DT.Color.accent)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 48, bottom: 8, trailing: 48))
            }

            Section {
                Button(role: .destructive) {
                    signOutTarget = authManager.state.credential
                } label: {
                    Text("Sign Out")
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .screenBackground()
        .navigationTitle("Profiles")
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

    private func sectionLabel(_ text: String) -> some View {
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
    @State private var storedPIN: String?
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
        .task { storedPIN = await authManager.pin(for: task.profile.id) }
    }

    private func handle(_ entered: String) {
        let needsCurrent = task.kind == .unlock || task.kind == .remove || (task.kind == .change && !verified)
        if needsCurrent {
            guard entered == storedPIN else { return fail("Incorrect PIN") }
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
            return
        }
        guard let first = firstEntry else {
            firstEntry = entered
            errorMessage = nil
            return
        }
        guard entered == first else {
            firstEntry = nil
            return fail("PINs don't match")
        }
        authManager.savePin(entered, for: task.profile.id)
        onDone(false)
    }

    private func fail(_ message: String) {
        errorMessage = message
        resetToken += 1
    }
}

// MARK: - tvOS add-profile flow (pushed within UsersView's NavigationStack)

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
            .navigationTitle("Add Profile")
        }
    }
}
