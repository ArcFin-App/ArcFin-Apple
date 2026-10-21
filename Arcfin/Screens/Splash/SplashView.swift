// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// Launch: a dark aurora wakes up behind a horizon of light; the library's recent posters
/// rise into a slowly turning 3D ring; the logo flips in at its centre and the name spells
/// itself out letter by letter. Leaving, the logo flies toward the viewer and everything else
/// falls away, so the app appears to open out of it.
struct SplashView: View {
    /// Reflects real work still happening (e.g. auth check) — not just a fixed timer. The
    /// exit animation waits for this to go false in addition to the minimum presentation time.
    var isLoading: Bool
    var onComplete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var posters = SplashMosaicStore.loadImages()
    @State private var auroraOpacity: Double = 0
    @State private var horizonWidth: CGFloat = 0
    @State private var horizonOpacity: Double = 0
    @State private var carouselReveal: Double = 0
    @State private var logoFlip: Double = 90
    @State private var logoScale: CGFloat = 0.4
    @State private var logoOpacity: Double = 0
    @State private var logoBlur: CGFloat = 12
    @State private var lettersShown = 0
    @State private var spinnerOpacity: Double = 0
    @State private var creditOpacity: Double = 0
    @State private var exiting = false
    @State private var minimumTimeElapsed = false

    private let logoSize: CGFloat = 116
    private let name = Array("Arcfin")

    var body: some View {
        ZStack {
            DT.Color.backgroundPrimary.ignoresSafeArea()

            aurora
                .opacity(auroraOpacity)
                .ignoresSafeArea()

            horizon

            if !posters.isEmpty {
                SplashPosterCarousel(posters: posters, reveal: carouselReveal, isAnimated: !reduceMotion)
                    .frame(height: logoSize * 3.2)
                    .offset(y: -logoSize * 0.35)
                    .opacity(exiting ? 0 : 1)
                    .scaleEffect(exiting ? 0.7 : 1)
            }

            VStack(spacing: 26) {
                Image("ArcfinLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: logoSize, height: logoSize)
                    .clipShape(RoundedRectangle(cornerRadius: logoSize * 0.25, style: .continuous))
                    .shadow(color: DT.Color.accent.opacity(0.6), radius: 36)
                    .shadow(color: .black.opacity(0.7), radius: 20, y: 10)
                    .rotation3DEffect(.degrees(logoFlip), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                    .blur(radius: logoBlur)
                    .scaleEffect(exiting && !reduceMotion ? 7 : logoScale)
                    .opacity(exiting ? 0 : logoOpacity)
                    .padding(.top, posters.isEmpty ? 0 : logoSize * 0.2)

                wordmark
                    .opacity(exiting ? 0 : 1)

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
                    .foregroundStyle(.white.opacity(0.22))
                    .padding(.bottom, 40)
                    .opacity(exiting ? 0 : creditOpacity)
            }
        }
        .onAppear { runSequence() }
        .onChange(of: isLoading) { _, _ in attemptFinish() }
    }

    // MARK: - Layers

    /// Brand-coloured light slowly shifting across a near-black field.
    private var aurora: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            let wobble = Float(sin(t * 0.6)) * 0.12
            let sway = Float(cos(t * 0.45)) * 0.1
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0, 0], [0.5 + sway, 0], [1, 0],
                    [0, 0.5 + wobble], [0.5 - sway, 0.55 + wobble], [1, 0.5 - wobble],
                    [0, 1], [0.5 + wobble, 1], [1, 1],
                ],
                colors: [
                    DT.Color.backgroundPrimary, Color(hex: "06303B"), DT.Color.backgroundPrimary,
                    Color(hex: "042A33"), DT.Color.accentDeep.opacity(0.55), Color(hex: "0B1E3A"),
                    DT.Color.backgroundPrimary, Color(hex: "05222B"), DT.Color.backgroundPrimary,
                ]
            )
        }
    }

    /// A thin line of light that opens out across the screen like a sunrise.
    private var horizon: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [.clear, DT.Color.accent, .white, DT.Color.accent, .clear],
                    startPoint: .leading, endPoint: .trailing)
            )
            .frame(width: horizonWidth, height: 2)
            .shadow(color: DT.Color.accent, radius: 12)
            .shadow(color: DT.Color.accent.opacity(0.6), radius: 40)
            .offset(y: logoSize * 1.25)
            .opacity(horizonOpacity)
            .allowsHitTesting(false)
    }

    /// "Arcfin", each letter rising out of a blur in turn.
    private var wordmark: some View {
        HStack(spacing: 2) {
            ForEach(Array(name.enumerated()), id: \.offset) { index, letter in
                let shown = index < lettersShown
                Text(String(letter))
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)
                    .opacity(shown ? 1 : 0)
                    .offset(y: shown ? 0 : 14)
                    .blur(radius: shown ? 0 : 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Arcfin")
    }

    // MARK: - Sequence

    private func runSequence() {
        guard !reduceMotion else {
            withAnimation(.easeOut(duration: 0.4)) {
                auroraOpacity = 1
                carouselReveal = 1
                logoFlip = 0; logoScale = 1; logoOpacity = 1; logoBlur = 0
                lettersShown = name.count
                creditOpacity = 1
            }
            scheduleSpinnerAndExit(exitAfter: 1.2)
            return
        }

        // 1. The aurora wakes and a horizon of light opens across the screen.
        withAnimation(.easeOut(duration: 1.2)) { auroraOpacity = 1 }
        withAnimation(.easeOut(duration: 0.25)) { horizonOpacity = 1 }
        withAnimation(.timingCurve(0.2, 0.9, 0.2, 1, duration: 0.9)) { horizonWidth = 520 }

        // 2. Posters rise into the turning ring.
        schedule(after: 0.25) {
            withAnimation(.spring(response: 1.1, dampingFraction: 0.85)) { carouselReveal = 1 }
        }

        // 3. The logo flips in at the centre and sharpens.
        schedule(after: 0.45) {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.68)) {
                logoFlip = 0
                logoScale = 1
                logoOpacity = 1
            }
            withAnimation(.easeOut(duration: 0.5)) { logoBlur = 0 }
        }

        // 4. The name spells itself out; the horizon settles to a faint glow.
        for index in name.indices {
            schedule(after: 0.95 + Double(index) * 0.07) {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) { lettersShown = index + 1 }
            }
        }
        schedule(after: 1.1) { withAnimation(.easeInOut(duration: 0.8)) { horizonOpacity = 0.35 } }
        schedule(after: 1.4) { withAnimation(.easeIn(duration: 0.4)) { creditOpacity = 1 } }

        scheduleSpinnerAndExit(exitAfter: posters.isEmpty ? 1.9 : 2.3)
    }

    private func scheduleSpinnerAndExit(exitAfter: Double) {
        // Still loading once the entrance settles: a plain spinner, so the screen doesn't sit
        // there with nothing showing that work is happening.
        schedule(after: exitAfter + 0.2) {
            if isLoading { withAnimation(.easeIn(duration: 0.3)) { spinnerOpacity = 1 } }
        }
        // Authentication continues in the background; SessionCheckingView covers a slow check.
        schedule(after: exitAfter) {
            minimumTimeElapsed = true
            attemptFinish(force: true)
        }
    }

    private func schedule(after delay: Double, _ work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func attemptFinish(force: Bool = false) {
        guard minimumTimeElapsed, !exiting, force || !isLoading else { return }
        let duration = reduceMotion ? 0.35 : 0.55
        withAnimation(.easeIn(duration: duration)) {
            exiting = true
            auroraOpacity = 0
            horizonOpacity = 0
            spinnerOpacity = 0
        }
        schedule(after: duration) { onComplete() }
    }
}

#Preview {
    SplashView(isLoading: false, onComplete: {})
}
