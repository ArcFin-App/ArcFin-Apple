// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
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
    @FocusState private var focusedProfile: UUID?

    private var activeID: UUID? { authManager.state.credential?.id }

    // Fixed, not .adaptive — an adaptive grid resolves its column count from measured width
    // across layout passes, which is what caused the picker to visibly jump from left-packed
    // to centered right after appearing. A size-class-driven fixed count never has to guess.
    private var columnCount: Int { sizeClass == .compact ? 2 : 3 }
    private let tileWidth: CGFloat = 220
    private let avatarSize: CGFloat = 180
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
                    .buttonStyle(TVCardButtonStyle())
                    .focusEffectDisabled()
                    .tvFocusRing(cornerRadius: DT.Radius.lg, prominent: true)
                    .focused($focusedProfile, equals: profile.id)
                }
            }
            .frame(maxWidth: gridMaxWidth)
            // The last profile used, rather than whichever tile comes first; set as well, as
            // the screens kept under the lock may still hold focus.
            .defaultFocus($focusedProfile, activeID)
            .task { focusedProfile = activeID }

            Spacer()
            Spacer()
        }
    }

}
