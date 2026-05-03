import SwiftUI

// Scaffold placeholder — replaced by HomeScreen module once packages are linked
// and design screenshots have been reviewed.
struct ContentView: View {
    var body: some View {
        ZStack {
            DT.Color.backgroundPrimary.ignoresSafeArea()
            VStack(spacing: DT.Spacing.md) {
                Image(systemName: "film.stack")
                    .font(.system(size: 56, weight: .thin))
                    .foregroundStyle(DT.Color.accent)
                Text("Arcfin")
                    .font(DT.Font.hero)
                    .foregroundStyle(DT.Color.textPrimary)
                Text("Scaffold complete — awaiting design screenshots.")
                    .font(DT.Font.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }
        }
    }
}

#Preview {
    ContentView()
}
