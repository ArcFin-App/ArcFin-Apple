// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// Launch animation: behind everything, a tilted wall of the library's recently added posters
/// drifts into view (when someone has signed in before); in front, the logo resolves out of a
/// blur as a backlight glows up behind it, and a highlight sweeps across it.
struct SplashView: View {
    /// Reflects real work still happening (e.g. auth check) — not just a fixed timer. The
    /// exit animation waits for this to go false in addition to the minimum presentation time.
    var isLoading: Bool
    var onComplete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var posters = SplashMosaicStore.loadImages()
    @State private var mosaicReveal: Double = 0
    @State private var mosaicScale: CGFloat = 1.08
    @State private var glowOpacity: Double = 0
    @State private var glowScale: CGFloat = 0.8
    @State private var backlightOpacity: Double = 0
    @State private var backlightScale: CGFloat = 0.6
    @State private var logoScale: CGFloat = 0.78
    @State private var logoOpacity: Double = 0
    @State private var logoBlur: CGFloat = 16
    @State private var shineOffset: CGFloat = -1
    @State private var breathing = false
    @State private var spinnerOpacity: Double = 0
    @State private var creditOpacity: Double = 0
    @State private var sceneOpacity: Double = 1
    @State private var sceneScale: CGFloat = 1
    @State private var minimumTimeElapsed = false
    @State private var isExiting = false

    private let logoSize: CGFloat = 132 * scale

    var body: some View {
        bodyContent.alwaysDark()
    }

    @ViewBuilder
    private var bodyContent: some View {
        ZStack {
            DT.Color.backgroundPrimary.ignoresSafeArea()

            if !posters.isEmpty {
                SplashMosaicView(posters: posters, reveal: mosaicReveal, isAnimated: !reduceMotion)
                    .blur(radius: 1.5)
                    .scaleEffect(mosaicScale)
                    .opacity(0.6)
                    .ignoresSafeArea()
                // Darken toward the middle and the edges so the mark reads clearly on top.
                RadialGradient(
                    colors: [DT.Color.backgroundPrimary.opacity(0.92), DT.Color.backgroundPrimary.opacity(0.25)],
                    center: .center, startRadius: 40 * Self.scale, endRadius: 360 * Self.scale
                )
                .ignoresSafeArea()
                LinearGradient(
                    colors: [DT.Color.backgroundPrimary.opacity(0.7), .clear, DT.Color.backgroundPrimary.opacity(0.9)],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()
            }

            // Soft light that blooms behind the mark
            RadialGradient(
                colors: [DT.Color.accent.opacity(0.32), DT.Color.accentDeep.opacity(0.10), .clear],
                center: .center, startRadius: 0, endRadius: 280 * Self.scale
            )
            .frame(width: 560 * Self.scale, height: 560 * Self.scale)
            .scaleEffect(glowScale * (breathing ? 1.12 : 1))
            .opacity(glowOpacity)
            .blur(radius: 24)
            .allowsHitTesting(false)

            VStack(spacing: 30) {
                ZStack {
                    // Backlight: a heavily blurred copy of the logo itself, so the glow takes
                    // the mark's own colours and seems to shine from behind it.
                    Image("ArcfinLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: logoSize, height: logoSize)
                        .saturation(1.6)
                        .blur(radius: 34 * Self.scale)
                        .scaleEffect(backlightScale * (breathing ? 1.1 : 1))
                        .opacity(backlightOpacity * (breathing ? 0.85 : 1))
                        .blendMode(.plusLighter)
                        .allowsHitTesting(false)

                    logo
                }
                .frame(height: logoSize * 1.42)

                ProgressView()
                    .tint(.white)
                    .opacity(spinnerOpacity)
            }

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

    private var logo: some View {
        Image("ArcfinLogo")
            .resizable()
            .scaledToFit()
            .frame(width: logoSize, height: logoSize)
            .clipShape(RoundedRectangle(cornerRadius: logoSize * 0.25, style: .continuous))
            .overlay {
                // A diagonal highlight passing over the mark once, clipped to its shape
                LinearGradient(
                    colors: [.clear, .white.opacity(0.55), .clear],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: logoSize * 0.5)
                .rotationEffect(.degrees(20))
                .offset(x: shineOffset * logoSize)
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: logoSize * 0.25, style: .continuous))
            .shadow(color: DT.Color.accent.opacity(0.5), radius: 40 * Self.scale)
            .shadow(color: .black.opacity(0.6), radius: 22 * Self.scale, y: 12 * Self.scale)
            .blur(radius: logoBlur)
            .scaleEffect(logoScale)
            .opacity(logoOpacity)
    }

    private func runSequence() {
        guard !reduceMotion else {
            // No drawing, spinning, sweeping or drifting: everything simply fades in.
            withAnimation(.easeOut(duration: 0.4)) {
                mosaicReveal = 1; mosaicScale = 1
                glowOpacity = 1; glowScale = 1
                logoScale = 1; logoOpacity = 1; logoBlur = 0
                backlightOpacity = 1; backlightScale = 1.35
            }
            schedule(after: 0.5) { withAnimation(.easeIn(duration: 0.3)) { creditOpacity = 1 } }
            scheduleSpinnerAndExit()
            return
        }

        // 0. The poster wall fades in column by column and settles from a slight zoom
        withAnimation(.easeOut(duration: 1.2)) { mosaicReveal = 1 }
        withAnimation(.easeOut(duration: 2.2)) { mosaicScale = 1 }

        // 1. Light blooms in the background
        withAnimation(.easeOut(duration: 0.7)) { glowOpacity = 1; glowScale = 1 }

        // 2. The logo resolves out of a blur while its backlight swells up behind it
        schedule(after: 0.3) {
            withAnimation(.easeOut(duration: 0.9)) {
                backlightOpacity = 1
                backlightScale = 1.35
            }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.72)) {
                logoScale = 1
                logoOpacity = 1
            }
            withAnimation(.easeOut(duration: 0.55)) { logoBlur = 0 }
        }

        // 3. Highlight sweeps across the mark
        schedule(after: 0.85) {
            withAnimation(.easeInOut(duration: 0.7)) { shineOffset = 1.4 }
        }

        // 4. The backlight settles into a slow breathe.
        schedule(after: 1.05) {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { breathing = true }
        }

        schedule(after: 1.2) { withAnimation(.easeIn(duration: 0.4)) { creditOpacity = 1 } }
        // The poster wall needs a moment longer to be seen.
        scheduleSpinnerAndExit(exitAfter: posters.isEmpty ? 1.8 : 2.2)
    }

    private func scheduleSpinnerAndExit(exitAfter: Double = 1.2) {
        // Still loading once the entrance settles: a plain spinner, so the screen doesn't
        // sit there with nothing indicating that work is happening.
        schedule(after: exitAfter + 0.2) {
            if isLoading { withAnimation(.easeIn(duration: 0.3)) { spinnerOpacity = 1 } }
        }
        // Exit after the minimum presentation time; authentication continues in the
        // background and SessionCheckingView covers a slow check.
        schedule(after: exitAfter) {
            minimumTimeElapsed = true
            attemptFinish(force: true)
        }
    }

    private func schedule(after delay: Double, _ work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func attemptFinish(force: Bool = false) {
        guard minimumTimeElapsed, !isExiting, force || !isLoading else { return }
        isExiting = true
        withAnimation(.easeInOut(duration: 0.48)) {
            sceneOpacity = 0
            sceneScale = reduceMotion ? 1 : 1.06
            // The wall pushes past the viewer a little faster than the mark.
            if !reduceMotion { mosaicScale = 1.14 }
        }
        schedule(after: 0.48) { onComplete() }
    }
}

#Preview {
    SplashView(isLoading: false, onComplete: {})
}
