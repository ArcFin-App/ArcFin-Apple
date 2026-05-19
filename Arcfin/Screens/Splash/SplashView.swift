import SwiftUI

struct SplashView: View {
    var onComplete: () -> Void

    // Box
    @State private var boxOpacity: Double = 0
    @State private var boxScale: CGFloat = 0.55
    // Stroke draw
    @State private var finTrim: CGFloat = 0
    @State private var crossbarTrim: CGFloat = 0
    // Text
    @State private var wordmarkOpacity: Double = 0
    @State private var wordmarkOffset: CGFloat = 14
    // Ambient glow
    @State private var glowOpacity: Double = 0
    @State private var glowPulse: CGFloat = 1.0
    // Credit
    @State private var creditOpacity: Double = 0
    // Exit
    @State private var sceneOpacity: Double = 1
    @State private var sceneScale: CGFloat = 1

    private let iconSize: CGFloat = 124

    var body: some View {
        ZStack {
            DT.Color.backgroundPrimary.ignoresSafeArea()

            // Ambient radial glow — pulses during hold
            RadialGradient(
                colors: [DT.Color.accent.opacity(0.22), DT.Color.accentDeep.opacity(0.10), .clear],
                center: .center, startRadius: 0, endRadius: 300
            )
            .frame(width: 600, height: 600)
            .scaleEffect(glowPulse)
            .opacity(glowOpacity)
            .blur(radius: 24)
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

                // Icon box + strokes
                ZStack {
                    RoundedRectangle(cornerRadius: iconSize * 0.25)
                        .fill(LinearGradient(
                            colors: [DT.Color.accentDeep, DT.Color.accent.opacity(0.9)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .frame(width: iconSize, height: iconSize)
                        .shadow(color: DT.Color.accent.opacity(0.55), radius: 48)
                        .shadow(color: .black.opacity(0.65), radius: 24, y: 12)

                    let is2 = iconSize * 0.60
                    FinIconShape()
                        .trim(from: 0, to: finTrim)
                        .stroke(.white, style: StrokeStyle(
                            lineWidth: 3.2 * (is2 / 28), lineCap: .round, lineJoin: .round))
                        .frame(width: is2, height: is2)

                    FinCrossbarShape()
                        .trim(from: 0, to: crossbarTrim)
                        .stroke(.white.opacity(0.92), style: StrokeStyle(
                            lineWidth: 2.8 * (is2 / 28), lineCap: .round))
                        .frame(width: is2, height: is2)
                }
                .scaleEffect(boxScale)
                .opacity(boxOpacity)

                // "arcfin" wordmark
                Text("arcfin")
                    .font(.system(size: iconSize * 0.40, weight: .heavy, design: .default))
                    .foregroundStyle(.white)
                    .tracking(-1)
                    .opacity(wordmarkOpacity)
                    .offset(y: wordmarkOffset)
                    .padding(.top, 22)

                Spacer()
            }

            // Credit
            VStack {
                Spacer()
                Text("by PSMattas")
                    .font(.system(size: 10, weight: .medium))
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
    }

    private func runSequence() {
        // 1. Glow fades in
        withAnimation(.easeOut(duration: 0.5)) {
            glowOpacity = 1
        }

        // 2. Icon box springs in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.spring(response: 0.52, dampingFraction: 0.68)) {
                boxOpacity = 1
                boxScale   = 1
            }
        }

        // 3. Fin stroke draws
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
            withAnimation(.easeInOut(duration: 0.62)) {
                finTrim = 1
            }
        }

        // 4. Crossbar draws
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.76) {
            withAnimation(.easeInOut(duration: 0.38)) {
                crossbarTrim = 1
            }
        }

        // 5. "arcfin" rises in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.88) {
            withAnimation(.easeOut(duration: 0.45)) {
                wordmarkOpacity = 1
                wordmarkOffset  = 0
            }
        }

        // 6. Credit line
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            withAnimation(.easeIn(duration: 0.4)) {
                creditOpacity = 1
            }
        }

        // 7. Glow pulse loop (starts while holding)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                glowPulse = 1.18
            }
        }

        // 8. Exit — gentle zoom-out + fade
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
            withAnimation(.easeInOut(duration: 0.48)) {
                sceneOpacity = 0
                sceneScale   = 0.94
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.48) {
                onComplete()
            }
        }
    }
}

#Preview {
    SplashView(onComplete: {})
}
