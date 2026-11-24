// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore

extension View {
    /// Asks before a profile is signed out or removed, since its PIN and Seerr sign-in go
    /// with it. Apple TV gets an alert, which keeps focus on the prompt. Removing a profile
    /// with a PIN also takes that PIN, or `confirmOwner` (Face ID or Touch ID) when given.
    func confirmingProfileRemoval(_ profile: Binding<ServerCredential?>, signingOut: Bool, isLastProfile: Bool,
                                  confirmOwner: ((String) async -> Bool)? = nil,
                                  perform: @escaping (ServerCredential) -> Void) -> some View {
        modifier(ProfileRemovalConfirmation(profile: profile, signingOut: signingOut, isLastProfile: isLastProfile,
                                            confirmOwner: confirmOwner, perform: perform))
    }
}

private struct ProfileRemovalConfirmation: ViewModifier {
    @Binding var profile: ServerCredential?
    let signingOut: Bool
    let isLastProfile: Bool
    let confirmOwner: ((String) async -> Bool)?
    let perform: (ServerCredential) -> Void

    @Environment(AuthManager.self) private var authManager
    @State private var pinTarget: ServerCredential?
    @State private var pinError: String?
    @State private var pinResetToken = 0

    private var isPresented: Binding<Bool> {
        Binding(get: { profile != nil }, set: { if !$0 { profile = nil } })
    }

    private var title: Text {
        let name = profile?.displayName ?? ""
        return signingOut ? Text("Sign Out of \(name)?") : Text("Remove \(name)?")
    }

    private var message: Text {
        isLastProfile
            ? Text("This is the last profile on this device, so its PIN, the Seerr sign-in, the TMDB key and the custom headers are all removed. Downloads stay.")
            : Text("This profile's PIN and Seerr sign-in are removed from this device. Downloads stay.")
    }

    @ViewBuilder
    private func actions(_ target: ServerCredential) -> some View {
        if signingOut {
            Button("Sign Out", role: .destructive) { perform(target) }
        } else {
            Button("Remove Profile", role: .destructive) { remove(target) }
        }
        Button("Cancel", role: .cancel) {}
    }

    private func remove(_ target: ServerCredential) {
        Task {
            let stored = await authManager.storedPIN(for: target.id)
            guard stored != .none else { return perform(target) }
            if let confirmOwner, await confirmOwner(String(localized: "Remove \(target.displayName)")) {
                PINAttempts.reset(for: target.id)
                return perform(target)
            }
            pinError = AuthManager.PINCheck.message(opening: stored, for: target.id)
            pinResetToken = 0
            pinTarget = target
        }
    }

    func body(content: Content) -> some View {
        content
            .confirmationPrompt(title, isPresented: isPresented, presenting: profile) { actions($0) } message: { _ in message }
            .onChange(of: profile?.id) { _, new in if new != nil { HapticManager.warning() } }
            .appSheet(item: $pinTarget) { target in
                PINEntrySheet(
                    title: String(localized: "Enter PIN"),
                    subtitle: target.displayName,
                    pinLength: PINLength.stored(target.id),
                    resetToken: pinResetToken,
                    errorMessage: pinError,
                    onCancel: { pinTarget = nil },
                    onComplete: { entered in
                        Task {
                            let result = await authManager.checkPIN(entered, for: target.id)
                            guard pinTarget?.id == target.id else { return }
                            guard result == .correct else {
                                pinError = result.message
                                pinResetToken += 1
                                return
                            }
                            pinTarget = nil
                            perform(target)
                        }
                    }
                )
            }
    }
}
