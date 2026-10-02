// SPDX-License-Identifier: AGPL-3.0-or-later

#if os(iOS)
import SwiftUI

/// Shown on iOS/iPadOS in place of the Login screen while AuthManager.checkStoredAuth() is
/// still validating a stored session — SplashView always exits after its own fixed minimum
/// presentation time regardless of whether that check has concluded, so without this a slow
/// network previously meant the app dropped straight to Login while an already-valid session
/// was still being confirmed in the background. The check itself typically resolves within a
/// few seconds either way; this just keeps the user from being shown the wrong screen while
/// it does, and gives them a way out if it genuinely never does.
struct SessionCheckingView: View {
    let onSignInManually: () -> Void
    let onRetry: () -> Void

    @State private var showOptions = false

    var body: some View {
        ZStack {
            DT.Color.backgroundPrimary.ignoresSafeArea()

            VStack(spacing: 20) {
                ProgressView()
                    .tint(.white)
                Text("Connecting to your server…")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(DT.Color.textSecondary)

                if showOptions {
                    VStack(spacing: 12) {
                        Text("This is taking longer than usual.")
                            .font(.system(size: 13))
                            .foregroundStyle(DT.Color.textSecondary)
                        Button(action: onRetry) {
                            Text("Retry")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(DT.Color.accent)
                        Button(action: onSignInManually) {
                            Text("Sign In Instead")
                                .font(.system(size: 15, weight: .medium))
                        }
                        .foregroundStyle(DT.Color.textSecondary)
                    }
                    .frame(maxWidth: 240)
                    .padding(.top, 8)
                    .transition(.opacity)
                }
            }
        }
        .task {
            // Gives the in-flight check a real chance to resolve on its own before offering
            // a way out — AuthManager's own internal timeouts (keychain read + token
            // validation) normally conclude well before this.
            try? await Task.sleep(for: .seconds(8))
            withAnimation(DT.Animation.standard) { showOptions = true }
        }
    }
}

#Preview {
    SessionCheckingView(onSignInManually: {}, onRetry: {})
}
#endif
