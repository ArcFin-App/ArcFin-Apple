#if !os(tvOS)
import SwiftUI
import LocalAuthentication
import AuthCore

/// Full-screen gate shown when the active profile has a PIN set and the app just launched or
/// returned from the background — reuses the same PINPadView/stored-PIN plumbing UsersView
/// already built for "PIN required to switch to this profile," just triggered by app
/// lifecycle instead of a profile switch. No cancel button — there's no bypass, only unlock.
struct AppLockView: View {
    @Environment(AuthManager.self) private var authManager
    let useFaceID: Bool
    let onUnlock: () -> Void

    @State private var storedPIN: String?
    @State private var errorMessage: String?
    @State private var resetToken = 0
    @State private var didAttemptBiometrics = false

    var body: some View {
        PINPadView(
            title: "Arcfin Locked",
            subtitle: authManager.state.credential?.displayName,
            errorMessage: errorMessage,
            resetToken: resetToken
        ) { entered in
            guard let storedPIN else { return }
            if entered == storedPIN {
                errorMessage = nil
                onUnlock()
            } else {
                errorMessage = "Incorrect PIN"
                resetToken += 1
            }
        }
        .task {
            if let cred = authManager.state.credential {
                storedPIN = await authManager.pin(for: cred.id)
            }
            if useFaceID, !didAttemptBiometrics {
                didAttemptBiometrics = true
                await attemptBiometrics()
            }
        }
    }

    private func attemptBiometrics() async {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return }
        guard let success = try? await context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            localizedReason: "Unlock Arcfin"
        ), success else { return }
        onUnlock()
    }
}
#endif
