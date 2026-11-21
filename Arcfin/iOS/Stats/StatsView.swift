// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI
import AuthCore

/// Watch stats worked out from the server's own record of what this profile has watched.
struct StatsView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage("statsPeriod") private var period = StatsPeriod.month
    @State private var model = StatsModel()
    /// Landscape, iPad and TV: the cards go in two columns instead of one long, stretched one.
    @State private var isWide = false
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var showShare = false

    var body: some View {
        NavigationStack {
            content
                .screenBackground()
                .arcfinNavTitleLarge("Stats")
                .toolbar {
                    if let stats = model.stats, !stats.isEmpty {
                        ToolbarItem(placement: .primaryAction) {
                            Button { showShare = true } label: {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                        }
                    }
                }
                .sheet(isPresented: $showShare) {
                    if let stats = model.stats {
                        StatsShareSheet(stats: stats, name: authManager.state.credential?.displayName)
                    }
                }
                .navigationDestination(for: MediaItem.self) { item in
                    MediaDetailView(item: item)
                }
                .navigationDestination(for: MediaPerson.self) { PersonDetailView(person: $0) }
        }
        .task(id: authManager.state.credential?.id) { await model.load(authManager: authManager) }
        .task(id: model.input(period: period)) { await model.compute(period: period, reduceMotion: reduceMotion) }
        .onChange(of: period) { model.offset = 0 }
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
                .frame(maxWidth: isWide ? 1300 : 900)
                .frame(maxWidth: .infinity)
            }
            .refreshable { await model.load(authManager: authManager) }
            .onGeometryChange(for: Bool.self) { $0.size.width >= 700 } action: { isWide = $0 }
        }
    }

    private var periodPicker: some View {
        Picker("Period", selection: $period) {
            ForEach(StatsPeriod.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
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
    }

    private func stepButton(_ icon: String, label: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(.body, weight: .semibold))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .disabled(disabled)
        .accessibilityLabel(label)
    }
}

#Preview {
    StatsView()
        .environment(MediaRepository())
}
