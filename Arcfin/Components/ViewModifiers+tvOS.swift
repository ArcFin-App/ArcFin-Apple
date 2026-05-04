import SwiftUI

extension View {
    @ViewBuilder
    func arcfinListStyle() -> some View {
#if os(tvOS)
        self.listStyle(.plain)
#else
        self.listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
#endif
    }

    @ViewBuilder
    func arcfinNavTitleLarge(_ title: String) -> some View {
#if os(tvOS)
        self.navigationTitle(title)
#else
        self.navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
#endif
    }

    @ViewBuilder
    func arcfinRowSeparatorHidden() -> some View {
#if os(tvOS)
        self
#else
        self.listRowSeparator(.hidden)
#endif
    }

    // Replaces ultraThinMaterial + white overlay — tvOS material renders light/white
    @ViewBuilder
    func arcfinFieldBackground() -> some View {
#if os(tvOS)
        self.background(DT.Color.backgroundSecondary)
#else
        self
            .background(.white.opacity(0.06))
            .background(.ultraThinMaterial)
#endif
    }
}
