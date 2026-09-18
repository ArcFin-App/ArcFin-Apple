import SwiftUI

struct SplashView: View {
    var onComplete: () -> Void

    @State private var logoScale: CGFloat  = 0.55
    @State private var logoOpacity: Double = 0
    @State private var glowOpacity: Double = 0
    @State private var glowPulse: CGFloat  = 1.0
    @State private var textOpacity: Double = 0
    @State private var textOffset: CGFloat = 14
    @State private var creditOpacity: Double = 0
    @State private var sceneOpacity: Double = 1
    @State private var sceneScale: CGFloat  = 1

    private let logoSize: CGFloat = 130

    var body: some View {
        ZStack {
            DT.Color.backgroundPrimary.ignoresSafeArea()

            // Pulsing ambient glow behind the logo
            RadialGradient(
                colors: [DT.Color.accent.opacity(0.24), DT.Color.accentDeep.opacity(0.10), .clear],
                center: .center, startRadius: 0, endRadius: 280
            )
            .frame(width: 560, height: 560)
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

                // App logo image
                Image("ArcfinLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: logoSize, height: logoSize)
                    .clipShape(RoundedRectangle(cornerRadius: logoSize * 0.25))
                    .shadow(color: DT.Color.accent.opacity(0.55), radius: 48)
                    .shadow(color: .black.opacity(0.65), radius: 24, y: 12)
                    .scaleEffect(logoScale)
                    .opacity(logoOpacity)

                // "Arcfin" wordmark
                Text("Arcfin")
                    .font(.system(size: logoSize * 0.40, weight: .heavy))
                    .foregroundStyle(.white)
                    .tracking(-1)
                    .opacity(textOpacity)
                    .offset(y: textOffset)
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

        // 2. Logo springs in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.spring(response: 0.52, dampingFraction: 0.68)) {
                logoOpacity = 1
                logoScale   = 1
            }
        }

        // 3. "arcfin" wordmark rises
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            withAnimation(.easeOut(duration: 0.45)) {
                textOpacity = 1
                textOffset  = 0
            }
        }

        // 4. Credit line
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
            withAnimation(.easeIn(duration: 0.4)) {
                creditOpacity = 1
            }
        }

        // 5. Glow pulse loop
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                glowPulse = 1.18
            }
        }

        // 6. Exit
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
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
