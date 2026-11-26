// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import LocalAuthentication
import AuthCore

/// Full-screen gate shown when the active profile has a PIN set and the app just launched or
/// returned from the background. Leads with a profile picker across every
/// saved profile (not just the active one), same as switching profiles from Settings — so
/// unlocking and switching who you are are the same screen instead of two. No cancel button
/// on the PIN pad itself — there's no bypass, only unlock or pick a different profile.
struct AppLockView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.horizontalSizeClass) private var sizeClass
    let useFaceID: Bool
    let onUnlock: () -> Void

    @State private var model = AppLockModel()
    @State private var signingOut: ServerCredential?
    @State private var didAttemptBiometricsFor: UUID?

    private var activeID: UUID? { authManager.state.credential?.id }

    // Fixed, not .adaptive — an adaptive grid resolves its column count from measured width
    // across layout passes, which is what caused the picker to visibly jump from left-packed
    // to centered right after appearing. A size-class-driven fixed count never has to guess.
    private var columnCount: Int { sizeClass == .compact ? 2 : 3 }
    private let tileWidth: CGFloat = 116
    private let avatarSize: CGFloat = 100
    private let gridSpacing: CGFloat = 24
    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: gridSpacing), count: columnCount)
    }
    private var gridMaxWidth: CGFloat {
        CGFloat(columnCount) * tileWidth + CGFloat(columnCount - 1) * gridSpacing
    }

    var body: some View {
        bodyContent.alwaysDark()
    }

    @ViewBuilder
    private var bodyContent: some View {
        ZStack {
            DT.Color.backgroundPrimary.ignoresSafeArea()

            if let target = model.pinTarget {
                PINPadView(
                    title: String(localized: "Enter PIN"),
                    subtitle: target.displayName,
                    pinLength: PINLength.stored(target.id),
                    errorMessage: model.errorMessage,
                    resetToken: model.resetToken,
                    onCancel: { model.cancelPIN() },
                    onSignOut: model.isPINUnreadable ? { signingOut = target } : nil
                ) { entered in
                    model.enter(entered, for: target, authManager: authManager, onUnlock: onUnlock)
                }
                .task(id: target.id) { await attemptBiometricsIfNeeded(for: target) }
            } else {
                pickerBody
            }
        }
        .task { await model.loadPINStates(authManager: authManager) }
        .confirmationPrompt(Text("Sign Out of \(signingOut?.displayName ?? "")?"),
                            isPresented: Binding(get: { signingOut != nil }, set: { if !$0 { signingOut = nil } }),
                            presenting: signingOut) { target in
            Button("Sign Out", role: .destructive) { model.signOut(target, authManager: authManager) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("You'll need this profile's password to sign in again.")
        }
    }

    // MARK: - Profile picker

    private var pickerBody: some View {
        VStack(spacing: 28) {
            Spacer()

            ArcfinLogoView(size: 84)

            AppLockGreeting()

            LazyVGrid(columns: gridColumns, spacing: gridSpacing) {
                ForEach(authManager.profiles) { profile in
                    Button { model.select(profile, authManager: authManager, onUnlock: onUnlock) } label: {
                        ProfileLockTile(profile: profile, isActive: profile.id == activeID, hasPIN: model.hasPIN(profile),
                                        tileWidth: tileWidth, avatarSize: avatarSize)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: gridMaxWidth)

            Spacer()
            Spacer()
        }
    }

    // MARK: - Actions

    private func attemptBiometricsIfNeeded(for profile: ServerCredential) async {
        // Only the already-active profile gets an automatic Face ID prompt — biometrics
        // enrolled on this device authenticate the device owner, not a specific Jellyfin
        // profile, so auto-prompting for a DIFFERENT profile the moment it's tapped would
        // let Face ID silently switch identities without the PIN ever being the real gate.
        guard useFaceID, profile.id == activeID, didAttemptBiometricsFor != profile.id else { return }
        // Started with the pad's first frame, the Face ID prompt left Cancel laid out off the
        // left edge on a cold start (#764): the pad settles first.
        guard (try? await Task.sleep(for: .milliseconds(450))) != nil else { return }
        didAttemptBiometricsFor = profile.id
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return }
        guard let success = try? await context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: String(localized: "Unlock Arcfin")
        ), success else { return }
        model.unlock(as: profile, authManager: authManager, onUnlock: onUnlock)
    }
}
