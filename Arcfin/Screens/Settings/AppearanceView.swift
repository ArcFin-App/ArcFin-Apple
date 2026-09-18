import SwiftUI

struct AppearanceView: View {
    @AppStorage("showStatsTab") private var showStatsTab = true
    @AppStorage("reduceMotion") private var reduceMotion = false
    @AppStorage("compactLibraryGrid") private var compactLibraryGrid = false
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @AppStorage("mergeContinueWatchingAndUpNext") private var mergeContinueWatchingAndUpNext = false

    var body: some View {
        List {
            Section {
                Toggle("Merge Continue Watching & Up Next", isOn: $mergeContinueWatchingAndUpNext)
            } header: {
                Label("Home", systemImage: "house")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DT.Color.textSecondary)
                    .textCase(nil)
            } footer: {
                Text("Shows Continue Watching and Up Next as a single combined row instead of two separate ones.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }

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

            Section {
                Toggle("Reduce Motion", isOn: $reduceMotion)
            } header: {
                Label("Motion", systemImage: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DT.Color.textSecondary)
                    .textCase(nil)
            } footer: {
                Text("Minimizes animations and transitions throughout the app.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }

            Section {
                Toggle("Compact Grid", isOn: $compactLibraryGrid)
            } header: {
                Label("Library", systemImage: "square.grid.3x3")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DT.Color.textSecondary)
                    .textCase(nil)
            } footer: {
                Text("Shows more, smaller posters per row in Library grids.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }

            Section {
                Toggle("Haptic Feedback", isOn: $hapticsEnabled)
            } header: {
                Label("Feedback", systemImage: "iphone.radiowaves.left.and.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DT.Color.textSecondary)
                    .textCase(nil)
            } footer: {
                Text("Taps a light vibration on key interactions like requesting a title.")
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
