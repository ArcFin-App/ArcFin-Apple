// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// Launch animation: behind everything, a tilted wall of the library's recently added posters
/// drifts into view (when someone has signed in before); in front, a ring draws itself around
/// the mark, the logo resolves out of a blur inside it, a highlight sweeps across the logo,
/// and the wordmark tightens into place.
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
    @State private var ringTrim: CGFloat = 0
    @State private var ringRotation: Double = -90
    @State private var ringOpacity: Double = 1
    @State private var logoScale: CGFloat = 0.78
    @State private var logoOpacity: Double = 0
    @State private var logoBlur: CGFloat = 16
    @State private var shineOffset: CGFloat = -1
    @State private var wordOpacity: Double = 0
    @State private var wordTracking: CGFloat = 14
    @State private var spinnerOpacity: Double = 0
    @State private var creditOpacity: Double = 0
    @State private var sceneOpacity: Double = 1
    @State private var sceneScale: CGFloat = 1
    @State private var minimumTimeElapsed = false

    private let logoSize: CGFloat = 132

    var body: some View {
        ZStack {
            DT.Color.backgroundPrimary.ignoresSafeArea()

            if !posters.isEmpty {
                SplashMosaicView(posters: posters, reveal: mosaicReveal, isAnimated: !reduceMotion)
                    .scaleEffect(mosaicScale)
                    .opacity(0.55)
                    .ignoresSafeArea()
                // Darken toward the middle and the edges so the mark reads clearly on top.
                RadialGradient(
                    colors: [DT.Color.backgroundPrimary.opacity(0.92), DT.Color.backgroundPrimary.opacity(0.25)],
                    center: .center, startRadius: 40, endRadius: 360
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
                center: .center, startRadius: 0, endRadius: 280
            )
            .frame(width: 560, height: 560)
            .scaleEffect(glowScale)
            .opacity(glowOpacity)
            .blur(radius: 24)
            .allowsHitTesting(false)

            VStack(spacing: 30) {
                ZStack {
                    // The "arc": a bright head trailing a fading tail
                    Circle()
                        .trim(from: 0, to: ringTrim)
                        .stroke(
                            AngularGradient(
                                colors: [DT.Color.accent.opacity(0), DT.Color.accent, .white],
                                center: .center),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .frame(width: logoSize * 1.42, height: logoSize * 1.42)
                        .rotationEffect(.degrees(ringRotation))
                        .opacity(ringOpacity)
                        .shadow(color: DT.Color.accent.opacity(0.7), radius: 10)

                    logo
                }
                .frame(height: logoSize * 1.42)

                Text("Arcfin")
                    .font(.system(.title, design: .rounded, weight: .semibold))
                    .tracking(wordTracking)
                    .foregroundStyle(.white)
                    .opacity(wordOpacity)
                    .accessibilityHidden(true)

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
            .shadow(color: DT.Color.accent.opacity(0.5), radius: 40)
            .shadow(color: .black.opacity(0.6), radius: 22, y: 12)
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
                wordOpacity = 1; wordTracking = 2; ringOpacity = 0
            }
            schedule(after: 0.5) { withAnimation(.easeIn(duration: 0.3)) { creditOpacity = 1 } }
            scheduleSpinnerAndExit()
            return
        }

        // 0. The poster wall fades in column by column and settles from a slight zoom
        withAnimation(.easeOut(duration: 1.2)) { mosaicReveal = 1 }
        withAnimation(.easeOut(duration: 2.2)) { mosaicScale = 1 }

        // 1. Light blooms and the ring starts drawing, turning as it goes
        withAnimation(.easeOut(duration: 0.7)) { glowOpacity = 1; glowScale = 1 }
        withAnimation(.easeInOut(duration: 1.0)) { ringTrim = 1 }
        withAnimation(.easeInOut(duration: 1.0)) { ringRotation = 270 }

        // 2. The logo resolves out of a blur inside the ring
        schedule(after: 0.3) {
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

        // 4. The ring dissolves and the wordmark tightens into place
        schedule(after: 1.05) {
            withAnimation(.easeOut(duration: 0.45)) { ringOpacity = 0 }
            withAnimation(.easeOut(duration: 0.6)) {
                wordOpacity = 1
                wordTracking = 2
            }
        }

        schedule(after: 1.2) { withAnimation(.easeIn(duration: 0.4)) { creditOpacity = 1 } }
        // The poster wall needs a moment longer to be seen.
        scheduleSpinnerAndExit(exitAfter: posters.isEmpty ? 1.7 : 2.1)
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
        guard minimumTimeElapsed, force || !isLoading else { return }
        withAnimation(.easeInOut(duration: 0.48)) {
            sceneOpacity = 0
            sceneScale = reduceMotion ? 1 : 1.06
        }
        schedule(after: 0.48) { onComplete() }
    }
}

#Preview {
    SplashView(isLoading: false, onComplete: {})
}
