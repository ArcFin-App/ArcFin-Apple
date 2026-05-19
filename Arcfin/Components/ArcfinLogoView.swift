import SwiftUI

struct ArcfinLogoView: View {
    var size: CGFloat = 52

    private var cornerRadius: CGFloat { size * 0.31 }
    private var iconSize: CGFloat { size * 0.56 }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(
                        LinearGradient(
                            colors: [DT.Color.accentDeep, DT.Color.accent],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size, height: size)
                    .shadow(color: DT.Color.accent.opacity(0.4), radius: size * 0.4)
                    .shadow(color: .black.opacity(0.6), radius: size * 0.25, y: size * 0.08)

                FinIconShape()
                    .stroke(.white, style: StrokeStyle(lineWidth: 2.5 * (iconSize / 28), lineCap: .round, lineJoin: .round))
                    .frame(width: iconSize, height: iconSize)

                FinCrossbarShape()
                    .stroke(.white, style: StrokeStyle(lineWidth: 2.2 * (iconSize / 28), lineCap: .round))
                    .frame(width: iconSize, height: iconSize)
            }

            Text("arcfin")
                .font(.system(size: size * 0.42, weight: .heavy))
                .foregroundStyle(.white)
                .tracking(-0.8)
        }
    }
}

// MARK: - Icon paths (viewBox 0 0 28 28)

struct FinIconShape: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 28
        let sy = rect.height / 28
        var p = Path()
        p.move(to: CGPoint(x: 5 * sx, y: 22 * sy))
        p.addLine(to: CGPoint(x: 14 * sx, y: 6 * sy))
        p.addLine(to: CGPoint(x: 23 * sx, y: 22 * sy))
        return p
    }
}

struct FinCrossbarShape: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 28
        let sy = rect.height / 28
        var p = Path()
        p.move(to: CGPoint(x: 8 * sx, y: 17 * sy))
        p.addLine(to: CGPoint(x: 20 * sx, y: 17 * sy))
        return p
    }
}

// MARK: - Compact logo (icon only, no text)

struct ArcfinIconView: View {
    var size: CGFloat = 20

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.31)
                .fill(LinearGradient(
                    colors: [DT.Color.accentDeep, DT.Color.accent],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: size, height: size)

            let iconSize = size * 0.56
            FinIconShape()
                .stroke(.white, style: StrokeStyle(lineWidth: 1.5 * (iconSize / 28), lineCap: .round, lineJoin: .round))
                .frame(width: iconSize, height: iconSize)

            FinCrossbarShape()
                .stroke(.white, style: StrokeStyle(lineWidth: 1.4 * (iconSize / 28), lineCap: .round))
                .frame(width: iconSize, height: iconSize)
        }
    }
}

#Preview {
    ZStack {
        DT.Color.backgroundPrimary.ignoresSafeArea()
        ArcfinLogoView(size: 72)
    }
}
