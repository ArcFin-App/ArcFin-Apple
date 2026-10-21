// SPDX-License-Identifier: AGPL-3.0-or-later

#if !os(tvOS)
import SwiftUI
import LocalAuthentication
import AuthCore
import JellyfinAPI

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

    @State private var pinStates: [UUID: Bool] = [:]
    @State private var pinTarget: ServerCredential?
    @State private var storedPIN: String?
    @State private var errorMessage: String?
    @State private var resetToken = 0
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
        ZStack {
            DT.Color.backgroundPrimary.ignoresSafeArea()

            if let target = pinTarget {
                PINPadView(
                    title: "Enter PIN",
                    subtitle: target.displayName,
                    errorMessage: errorMessage,
                    resetToken: resetToken,
                    onCancel: { pinTarget = nil; errorMessage = nil }
                ) { entered in
                    guard entered == storedPIN else {
                        errorMessage = "Incorrect PIN"
                        resetToken += 1
                        return
                    }
                    errorMessage = nil
                    unlock(as: target)
                }
                .task(id: target.id) { await attemptBiometricsIfNeeded(for: target) }
            } else {
                pickerBody
            }
        }
        .task { await loadPINStates() }
    }

    // MARK: - Profile picker

    private var pickerBody: some View {
        VStack(spacing: 28) {
            Spacer()

            ArcfinLogoView(size: 84)

            VStack(spacing: 6) {
                Text("Welcome to Arcfin")
                    .font(.system(.title, design: .default, weight: .bold))
                    .foregroundStyle(DT.Color.textPrimary)
                Text("Please select your profile to continue")
                    .font(.system(.subheadline))
                    .foregroundStyle(DT.Color.textSecondary)
            }

            LazyVGrid(columns: gridColumns, spacing: gridSpacing) {
                ForEach(authManager.profiles) { profile in
                    Button { selectProfile(profile) } label: {
                        profileTile(profile)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: gridMaxWidth)

            Spacer()
            Spacer()
        }
    }

    private func initials(for profile: ServerCredential) -> String {
        profile.displayName
            .split(separator: " ").prefix(2)
            .compactMap { $0.first }
            .map { String($0).uppercased() }
            .joined()
    }

    @ViewBuilder
    private func avatarContent(_ profile: ServerCredential) -> some View {
        if let tag = profile.userImageTag {
            let url = JellyfinMediaClient.userImageURL(baseURL: profile.baseURL, userID: profile.userID, tag: tag, fillWidth: 200, token: profile.accessToken)
            CachedAsyncImage(url: url) { phase in
                if case .success(let img) = phase {
                    img.resizable().scaledToFill()
                } else {
                    avatarInitials(profile)
                }
            }
            .frame(width: avatarSize, height: avatarSize)
            .clipShape(Circle())
        } else {
            avatarInitials(profile)
        }
    }

    private func avatarInitials(_ profile: ServerCredential) -> some View {
        Text(initials(for: profile))
            .font(.system(.largeTitle, design: .rounded, weight: .bold))
            .foregroundStyle(.white)
    }

    private func profileTile(_ profile: ServerCredential) -> some View {
        let isActive = profile.id == activeID
        let hasPIN = pinStates[profile.id] == true
        let ringColor: Color = isActive ? DT.Color.accent : .clear

        return VStack(spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [DT.Color.accent, DT.Color.accentDeep],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .frame(width: avatarSize, height: avatarSize)
                    avatarContent(profile)
                }
                .overlay(Circle().stroke(ringColor, lineWidth: 3))

                if hasPIN {
                    Image(systemName: "lock.fill")
                        .font(.system(.footnote, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(7)
                        .background(Circle().fill(DT.Color.backgroundSecondary))
                }
            }

            Text(profile.displayName)
                .font(.system(.subheadline, design: .default, weight: .semibold))
                .foregroundStyle(DT.Color.textPrimary)
                .lineLimit(1)
            Text(profile.baseURL.host ?? "")
                .font(.system(.caption))
                .foregroundStyle(DT.Color.textSecondary)
                .lineLimit(1)
        }
        .frame(width: tileWidth)
    }

    // MARK: - Actions

    private func selectProfile(_ profile: ServerCredential) {
        HapticManager.impact(.light)
        guard pinStates[profile.id] == true else {
            unlock(as: profile)
            return
        }
        errorMessage = nil
        resetToken = 0
        Task {
            storedPIN = await authManager.pin(for: profile.id)
            pinTarget = profile
        }
    }

    private func unlock(as profile: ServerCredential) {
        if profile.id != activeID {
            authManager.switchTo(profile)
        }
        onUnlock()
    }

    private func loadPINStates() async {
        var states: [UUID: Bool] = [:]
        for profile in authManager.profiles {
            states[profile.id] = await authManager.pin(for: profile.id) != nil
        }
        pinStates = states
    }

    private func attemptBiometricsIfNeeded(for profile: ServerCredential) async {
        // Only the already-active profile gets an automatic Face ID prompt — biometrics
        // enrolled on this device authenticate the device owner, not a specific Jellyfin
        // profile, so auto-prompting for a DIFFERENT profile the moment it's tapped would
        // let Face ID silently switch identities without the PIN ever being the real gate.
        guard useFaceID, profile.id == activeID, didAttemptBiometricsFor != profile.id else { return }
        didAttemptBiometricsFor = profile.id
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return }
        guard let success = try? await context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: "Unlock Arcfin"
        ), success else { return }
        unlock(as: profile)
    }
}
#endif
