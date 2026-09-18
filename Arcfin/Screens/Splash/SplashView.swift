import SwiftUI

struct SplashView: View {
    var onComplete: () -> Void

    @State private var logoScale: CGFloat = 0.55
    @State private var logoOpacity: Double = 0
    @State private var logoBlur: CGFloat = 14
    @State private var glowOpacity: Double = 0
    @State private var glowPulse: CGFloat = 1.0
    @State private var ringTrim: CGFloat = 0
    @State private var ringOpacity: Double = 0
    @State private var ringRotation: Angle = .degrees(-90)
    @State private var creditOpacity: Double = 0
    @State private var sceneOpacity: Double = 1
    @State private var sceneScale: CGFloat = 1

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

                ZStack {
                    // A single accent arc draws in around the logo — a quiet "the app is
                    // alive" cue that doesn't need a wordmark to feel intentional.
                    Circle()
                        .trim(from: 0, to: ringTrim)
                        .stroke(
                            AngularGradient(
                                colors: [DT.Color.accent, DT.Color.accentDeep, DT.Color.accent.opacity(0)],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round)
                        )
                        .frame(width: logoSize + 34, height: logoSize + 34)
                        .rotationEffect(ringRotation)
                        .opacity(ringOpacity)

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
                }

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

        // 3. Accent ring draws in around the logo
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            ringOpacity = 1
            withAnimation(.easeInOut(duration: 0.9)) {
                ringTrim = 1
            }
            withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                ringRotation = .degrees(270)
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
                sceneScale = 0.94
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
