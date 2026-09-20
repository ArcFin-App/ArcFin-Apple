import SwiftUI

struct AppearanceView: View {
    @AppStorage("reduceMotion") private var reduceMotion = false
    @AppStorage("hapticsEnabled") private var hapticsEnabled = true
    @AppStorage("mergeContinueWatchingAndUpNext") private var mergeContinueWatchingAndUpNext = false
    #if canImport(UIKit) && !os(tvOS)
    @AppStorage("heroVideoBackdropsEnabled") private var heroVideoBackdropsEnabled = true
    #endif

    var body: some View {
        List {
            Section {
                Toggle("Merge Continue Watching & Up Next", isOn: $mergeContinueWatchingAndUpNext)
                #if canImport(UIKit) && !os(tvOS)
                Toggle("Hero Video Backdrops", isOn: $heroVideoBackdropsEnabled)
                #endif
                NavigationLink {
                    HomeShelfSettingsView()
                } label: {
                    Text("Home Shelves")
                }
            } header: {
                Label("Home", systemImage: "house")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DT.Color.textSecondary)
                    .textCase(nil)
            } footer: {
                Text("Shows Continue Watching and Up Next as a single combined row instead of two separate ones. Hero Video Backdrops autoplays a muted trailer behind the featured title when the server has one available. Home Shelves lets you reorder or hide individual rows.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }

            Section {
                NavigationLink {
                    BottomNavSettingsView()
                } label: {
                    Text("Bottom Navigation")
                }
            } header: {
                Label("Bottom Navigation", systemImage: "rectangle.bottomthird.inset.filled")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DT.Color.textSecondary)
                    .textCase(nil)
            } footer: {
                Text("Choose which tabs show and in what order. Requests and Watchlist only appear when Seerr is connected, even if active here.")
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


            #if !os(macOS)
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
            #endif
        }
        .arcfinListStyle()
        .background(DT.Color.backgroundPrimary)
        .arcfinNavTitleLarge("Appearance")
    }
}

#Preview {
    NavigationStack { AppearanceView() }
}
