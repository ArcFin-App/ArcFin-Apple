// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI
import AuthCore

/// Watch stats worked out from the server's own record of what this profile has watched.
struct StatsView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @AppStorage("statsPeriod") private var period = StatsPeriod.month
    @State private var model = StatsModel()
    /// Landscape, iPad and TV: the cards go in two columns instead of one long, stretched one.
    private let isWide = true
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        NavigationStack {
            content
                .screenBackground()
                // The page carries its own heading, so it scrolls away with the cards
                // instead of staying over them.
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: MediaItem.self) { item in
                    MediaDetailView(item: item)
                }
                .navigationDestination(for: MediaPerson.self) { PersonDetailView(person: $0) }
        }
        .task(id: authManager.state.credential?.id) { await model.load(authManager: authManager) }
        .task(id: model.input(period: period)) { await model.compute(period: period, reduceMotion: reduceMotion) }
        .onChange(of: period) { model.offset = 0 }
        // No pull to refresh on Apple TV: pick up what's been watched since when the tab comes
        // back into view or the app comes back to the front.
        .onAppear { refresh() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
    }

    private func refresh() {
        guard model.phase != .loading else { return }
        Task { await model.load(authManager: authManager) }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading where model.stats == nil:
            ProgressView("Adding up what you've watched…")
                .foregroundStyle(DT.Color.textSecondary)
        case .failed where model.watched.isEmpty:
            ContentUnavailableView {
                Label("Couldn't Load Stats", systemImage: "wifi.exclamationmark")
            } description: {
                Text("Check your connection to the server, then try again.")
            } actions: {
                Button("Try Again") { Task { await model.load(authManager: authManager) } }
                    .buttonStyle(.glassProminent)
                    .tint(DT.Color.accent)
            }
        default:
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    Text("Stats")
                        .font(.title2.bold())
                        .foregroundStyle(DT.Color.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    periodPicker
                    if period != .allTime, let stats = model.stats { periodStepper(stats) }
                    if let stats = model.stats {
                        if stats.isEmpty {
                            StatsEmptyPeriod(period: period, stats: model.stats, offset: model.offset)
                        } else {
                            StatsSections(stats: stats, counts: model.counts, isWide: isWide,
                                          compactHero: verticalSizeClass == .compact)
                        }
                    }
                }
                .padding(.horizontal, DT.Spacing.pagePad)
                .padding(.top, 8)
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var periodPicker: some View {
        Picker("Period", selection: $period) {
            ForEach(StatsPeriod.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
        .syncLocked("statsPeriod", authManager)
        .focusSection()
    }

    /// Steps back through earlier weeks, months or years, and forward again to the current one.
    private func periodStepper(_ stats: WatchStats) -> some View {
        HStack(spacing: 12) {
            stepButton("chevron.left", label: period.previousLabel, disabled: !stats.hasEarlier) { model.offset -= 1 }
            VStack(spacing: 1) {
                Text(stats.periodName)
                    .font(.system(.headline))
                    .foregroundStyle(DT.Color.textPrimary)
                    .contentTransition(.numericText())
                Text(stats.periodHeading)
                    .font(.system(.caption))
                    .foregroundStyle(DT.Color.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            stepButton("chevron.right", label: period.nextLabel, disabled: model.offset == 0) { model.offset += 1 }
        }
        .focusSection()
    }

    private func stepButton(_ icon: String, label: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(.body, weight: .semibold))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.bordered)
        .disabled(disabled)
        .accessibilityLabel(label)
    }
}

#Preview {
    StatsView()
        .environment(MediaRepository())
}
