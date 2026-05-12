import SwiftUI

struct SplashView: View {
    var onComplete: () -> Void

    @State private var shimmerPhase: CGFloat = -1
    @State private var opacity: Double = 0
    @State private var logoScale: CGFloat = 0.85

    var body: some View {
        ZStack {
            DT.Color.backgroundPrimary.ignoresSafeArea()

            // Ambient radial glow
            RadialGradient(
                colors: [DT.Color.accent.opacity(0.12), .clear],
                center: .center,
                startRadius: 0,
                endRadius: 200
            )
            .frame(width: 260, height: 260)
            .blur(radius: 40)
            .offset(y: -80)

            // Subtle scan lines
            Canvas { context, size in
                for y in stride(from: 0, through: size.height, by: 4) {
                    let line = Path(CGRect(x: 0, y: y, width: size.width, height: 1))
                    context.fill(line, with: .color(.white.opacity(0.012)))
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                Spacer()

                ArcfinLogoView(size: 72)
                    .scaleEffect(logoScale)

                // Shimmer loading bar
                GeometryReader { geo in
                    let barWidth: CGFloat = 120
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.white.opacity(0.08))
                            .frame(width: barWidth, height: 2)

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [.clear, DT.Color.accent, .clear],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: barWidth * 0.4, height: 2)
                            .offset(x: shimmerPhase * barWidth * 1.5)
                    }
                    .frame(width: barWidth)
                    .frame(maxWidth: .infinity)
                }
                .frame(height: 2)
                .padding(.top, 52)

                Spacer()
            }

            // "By PSMattas" wordmark
            VStack {
                Spacer()
                Text("By PSMattas")
                    .font(.system(size: 10, weight: .medium))
                    .tracking(1.5)
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.2))
                    .padding(.bottom, 36)
            }
        }
        .opacity(opacity)
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) {
                opacity = 1
                logoScale = 1
            }
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                shimmerPhase = 1.4
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                withAnimation(.easeInOut(duration: 0.4)) {
                    opacity = 0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    onComplete()
                }
            }
        }
    }
}

#Preview {
    SplashView(onComplete: {})
}
