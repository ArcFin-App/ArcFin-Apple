// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI
import AuthCore

/// Watch and listening stats worked out from the server's own record of what this profile has
/// watched and played, and from ListenBrainz for music when the profile sends its listens there.
struct StatsView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(MediaRepository.self) private var mediaRepo
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage("statsPeriod") private var period = StatsPeriod.month
    @State private var model = StatsModel()
    @State private var kind = StatsKind.all
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
                    if shareContent != nil {
                        ToolbarItem(placement: .primaryAction) {
                            Button { showShare = true } label: {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                        }
                    }
                }
                .sheet(isPresented: $showShare) {
                    if let shareContent {
                        StatsShareSheet(content: shareContent, name: authManager.state.credential?.displayName)
                    }
                }
                .navigationDestination(for: MediaItem.self) { item in
                    MediaDetailView(item: item)
                }
                .navigationDestination(for: MediaPerson.self) { PersonDetailView(person: $0) }
        }
        .task(id: authManager.state.credential?.id) { await model.load(authManager: authManager) }
        .task(id: model.input(period: period)) { await model.compute(period: period, reduceMotion: reduceMotion) }
        .task(id: musicTaskID) { if shownKind != .video { await model.loadMusic(authManager: authManager) } }
        .task(id: model.musicInput(period: period)) { await model.computeMusic(period: period, reduceMotion: reduceMotion) }
        .onChange(of: period) { model.offset = 0 }
    }

    /// Music shows up only with a music library to play from.
    private var hasMusic: Bool { mediaRepo.libraries.contains { $0.collectionType == .music } }
    private var shownKind: StatsKind { hasMusic ? kind : .video }
    /// The Music tab shares the listening card; All and Movies & Shows share the watch card.
    private var shareContent: StatsShareContent? {
        if shownKind == .music {
            guard let music = model.music, !music.isEmpty else { return nil }
            return .music(music)
        }
        guard let stats = model.stats, !stats.isEmpty else { return nil }
        return .video(stats)
    }

    private var musicTaskID: String { "\(authManager.state.credential?.id.uuidString ?? "")-\(shownKind != .video)" }

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
                    .foregroundStyle(DT.Color.onAccent)
            }
        default:
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    if hasMusic { kindPicker }
                    periodPicker
                    if period != .allTime, let title = stepperTitle { periodStepper(title) }
                    StatsKindContent(kind: shownKind, model: model, period: period, isWide: isWide,
                                     compactHero: verticalSizeClass == .compact)
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

    private var kindPicker: some View {
        Picker("Show", selection: $kind) {
            ForEach(StatsKind.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    /// The period's name and heading, from whichever stats the tab shows.
    private var stepperTitle: StatsStepperTitle? {
        StatsStepperTitle(kind: shownKind, model: model)
    }

    private var periodPicker: some View {
        Picker("Period", selection: $period) {
            ForEach(StatsPeriod.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
        .syncLocked("statsPeriod", authManager)
    }

    /// Steps back through earlier weeks, months or years, and forward again to the current one.
    private func periodStepper(_ title: StatsStepperTitle) -> some View {
        HStack(spacing: 12) {
            stepButton("chevron.left", label: period.previousLabel, disabled: !model.hasEarlier(shownKind)) { model.offset -= 1 }
            VStack(spacing: 1) {
                Text(title.name)
                    .font(.system(.headline))
                    .foregroundStyle(DT.Color.textPrimary)
                    .contentTransition(.numericText())
                Text(title.heading)
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
