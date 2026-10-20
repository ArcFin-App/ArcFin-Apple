// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

struct SplashView: View {
    /// Reflects real work still happening (e.g. auth check) — not just a fixed timer. The
    /// exit animation waits for this to go false in addition to the minimum presentation time.
    var isLoading: Bool
    var onComplete: () -> Void

    @State private var logoScale: CGFloat = 0.55
    @State private var logoOpacity: Double = 0
    @State private var logoBlur: CGFloat = 14
    @State private var glowOpacity: Double = 0
    @State private var glowPulse: CGFloat = 1.0
    @State private var spinnerOpacity: Double = 0
    @State private var creditOpacity: Double = 0
    @State private var sceneOpacity: Double = 1
    @State private var sceneScale: CGFloat = 1
    @State private var minimumTimeElapsed = false

    private let logoSize: CGFloat = 140

    var body: some View {
        ZStack {
            DT.Color.backgroundPrimary.ignoresSafeArea()

            // Pulsing ambient glow behind the logo
            RadialGradient(
                colors: [DT.Color.accent.opacity(0.28), DT.Color.accentDeep.opacity(0.12), .clear],
                center: .center, startRadius: 0, endRadius: 300
            )
            .frame(width: 600, height: 600)
            .scaleEffect(glowPulse)
            .opacity(glowOpacity)
            .blur(radius: 28)
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // Subtle scan-line texture
            Canvas { ctx, size in
                for y in stride(from: 0, through: size.height, by: 4) {
                    ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                             with: .color(.white.opacity(0.012)))
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                Spacer()

                Image("ArcfinLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: logoSize, height: logoSize)
                    .clipShape(RoundedRectangle(cornerRadius: logoSize * 0.25))
                    .shadow(color: DT.Color.accent.opacity(0.55), radius: 48)
                    .shadow(color: .black.opacity(0.65), radius: 24, y: 12)
                    .blur(radius: logoBlur)
                    .scaleEffect(logoScale)
                    .opacity(logoOpacity)

                ProgressView()
                    .tint(.white)
                    .opacity(spinnerOpacity)
                    .padding(.top, 28)

                Spacer()
            }

            // Credit
            VStack {
                Spacer()
                Text("by PSMattas")
                    .font(.system(.caption2, design: .default, weight: .medium))
                    .tracking(2.5)
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.18))
                    .padding(.bottom, 40)
                    .opacity(creditOpacity)
            }
        }
        .scaleEffect(sceneScale)
        .opacity(sceneOpacity)
        .onAppear { runSequence() }
        .onChange(of: isLoading) { _, _ in attemptFinish() }
    }

    private func runSequence() {
        // 1. Glow fades in
        withAnimation(.easeOut(duration: 0.5)) {
            glowOpacity = 1
        }

        // 2. Logo springs in and sharpens
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.7)) {
                logoOpacity = 1
                logoScale = 1
            }
            withAnimation(.easeOut(duration: 0.6)) {
                logoBlur = 0
            }
        }

        // 3. Credit line
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
            withAnimation(.easeIn(duration: 0.4)) {
                creditOpacity = 1
            }
        }

        // 4. Glow pulse loop
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                glowPulse = 1.18
            }
        }

        // 5. If still loading once the entrance settles, fade in a plain spinner below the
        // logo instead of silently sitting there with no indication anything is happening.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            if isLoading {
                withAnimation(.easeIn(duration: 0.3)) { spinnerOpacity = 1 }
            }
        }

        // 6. Exit after the minimum presentation time; authentication continues in the
        // background. 1.2s is enough for the entrance animation to read (credit line
        // finishes fading in at 0.85 + 0.4 = 1.25s) without stalling an already-fast
        // session check — launching.md: "Launch instantly... people don't want to wait
        // more than a couple of seconds," which the previous 2.4s (+0.48s fade = ~2.9s
        // total) was already pushing regardless of whether anything was still loading.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            minimumTimeElapsed = true
            attemptFinish(force: true)
        }
    }

    private func attemptFinish(force: Bool = false) {
        guard minimumTimeElapsed, force || !isLoading else { return }
        withAnimation(.easeInOut(duration: 0.48)) {
            sceneOpacity = 0
            sceneScale = 0.94
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.48) {
            onComplete()
        }
    }
}

#Preview {
    SplashView(isLoading: false, onComplete: {})
}
