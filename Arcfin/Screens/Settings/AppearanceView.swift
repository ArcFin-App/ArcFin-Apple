import SwiftUI

struct AppearanceView: View {
    @AppStorage("showStatsTab") private var showStatsTab = true

    var body: some View {
        List {
            Section {
                Toggle("Show Stats Tab", isOn: $showStatsTab)
            } header: {
                Label("Bottom Navigation", systemImage: "rectangle.bottomthird.inset.filled")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DT.Color.textSecondary)
                    .textCase(nil)
            } footer: {
                Text("Hide the Stats tab from the bottom navigation bar.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }
        }
        .arcfinListStyle()
        .background(DT.Color.backgroundPrimary)
        .arcfinNavTitleLarge("Appearance")
    }
}

#Preview {
    NavigationStack { AppearanceView() }
}
