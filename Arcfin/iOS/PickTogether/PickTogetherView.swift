// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

/// Pick Together: people on the same server swipe through titles until they agree on one.
/// Full screen on iPhone and iPad, and made for holding the device upright.
struct PickTogetherView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss
    /// A code from a scanned QR code, joined as soon as Pick Together opens.
    var joinCode: String?

    @State private var model: PickTogetherModel?
    @State private var path: [PickRoute] = []
    @State private var landscapeSkipped = false

    var body: some View {
        GeometryReader { proxy in
            NavigationStack(path: $path) {
                Group {
                    if let model {
                        PickTogetherContent(model: model, path: $path, joinCode: joinCode) { dismiss() }
                    } else {
                        ProgressView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DT.Color.backgroundPrimary)
                .navigationDestination(for: PickRoute.self) { route in
                    if let model {
                        switch route {
                        case .setup: PickSetupView(model: model) { path.removeAll() }
                        case .scan: PickScanView(model: model) { path.removeAll() }
                        case .matches: PickMatchesList(model: model) { close in open(close, model: model) }
                        }
                    }
                }
            }
            .overlay {
                if proxy.size.width > proxy.size.height, !landscapeSkipped {
                    PickRotatePrompt { landscapeSkipped = true }
                }
            }
        }
        .task {
            if model == nil { model = PickTogetherModel(authManager: authManager) }
        }
    }

    /// Opens a matched title's page, where it can be played here, on another device or with SharePlay.
    private func open(_ card: PickCard, model: PickTogetherModel) {
        model.newMatch = nil
        dismiss()
        Task {
            try? await Task.sleep(for: .seconds(0.4))
            ArcfinRouting.openItem(id: card.id)
        }
    }
}

enum PickRoute: Hashable {
    case setup, scan, matches
}

private struct PickTogetherContent: View {
    @Bindable var model: PickTogetherModel
    @Binding var path: [PickRoute]
    var joinCode: String?
    var close: () -> Void

    @State private var showEnterCode = false
    @State private var code = ""
    @State private var showLeave = false

    var body: some View {
        content
            .navigationTitle("Pick Together")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(model.state == nil ? "Close" : "Leave") {
                        if model.state == nil { close() } else { showLeave = true }
                    }
                }
            }
            .alert("Leave This Session?", isPresented: $showLeave) {
                Button("Leave", role: .destructive) {
                    model.leave()
                    close()
                }
                Button("Stay", role: .cancel) {}
            } message: {
                Text("Your swipes stop counting. You can join again with the code.")
            }
            .alert("Pick Together", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.error ?? "")
            }
            .alert("Enter the Code", isPresented: $showEnterCode) {
                TextField("Code", text: $code)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Button("Join") { Task { await model.join(code: code) } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("It's shown under the QR code on the phone or iPad that started the session.")
            }
            .onAppear { model.start(joinCode: joinCode) }
    }

    @ViewBuilder private var content: some View {
        if let availability = model.availability, !availability.enabled {
            ContentUnavailableView("Pick Together Is Off", systemImage: "person.2.slash",
                                   description: Text("Your server's admin has turned off Pick Together for you."))
        } else if model.availability == nil && model.error == nil {
            ProgressView()
        } else if model.state != nil {
            PickSessionView(model: model) { path.append(.matches) }
        } else {
            start
        }
    }

    private var start: some View {
        ScrollView {
            VStack(spacing: DT.Spacing.lg) {
                Image(systemName: "rectangle.stack.badge.person.crop")
                    .font(.system(size: 64, weight: .regular))
                    .foregroundStyle(DT.Color.accent)
                    .padding(.top, DT.Spacing.xxl)
                    .accessibilityHidden(true)
                VStack(spacing: DT.Spacing.xs) {
                    Text("Can't Decide What to Watch?")
                        .font(DT.Font.hero)
                        .multilineTextAlignment(.center)
                    Text("Everyone swipes right on what they'd watch and left on what they wouldn't. When you all like the same title, it's a match.")
                        .font(DT.Font.body)
                        .foregroundStyle(DT.Color.textSecondary)
                        .multilineTextAlignment(.center)
                }
                VStack(spacing: DT.Spacing.sm) {
                    Button { path.append(.setup) } label: {
                        Label("Start a Session", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    if PickScanView.isAvailable {
                        Button { path.append(.scan) } label: {
                            Label("Scan a Code to Join", systemImage: "qrcode.viewfinder")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                    Button { code = ""; showEnterCode = true } label: {
                        Label("Enter a Code", systemImage: "keyboard")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .tint(DT.Color.accent)
                Text("Everyone needs Arcfin on an iPhone or iPad, signed in to this server.")
                    .font(DT.Font.caption)
                    .foregroundStyle(DT.Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, DT.Spacing.pagePad)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Portrait

/// Pick Together is made for holding the device upright; this asks once, and can be skipped.
private struct PickRotatePrompt: View {
    var skip: () -> Void

    private var device: String {
        UIDevice.current.userInterfaceIdiom == .pad ? String(localized: "iPad") : String(localized: "iPhone")
    }

    var body: some View {
        ZStack {
            DT.Color.backgroundPrimary.ignoresSafeArea()
            VStack(spacing: DT.Spacing.md) {
                Image(systemName: "rectangle.portrait.rotate")
                    .font(.system(size: 56))
                    .foregroundStyle(DT.Color.accent)
                    .symbolEffect(.wiggle, options: .repeat(.periodic(delay: 2)))
                    .accessibilityHidden(true)
                Text("Turn Your \(device) Upright")
                    .font(DT.Font.sectionTitle)
                    .multilineTextAlignment(.center)
                Text("Pick Together works best in portrait, with one title at a time to swipe.")
                    .font(DT.Font.body)
                    .foregroundStyle(DT.Color.textSecondary)
                    .multilineTextAlignment(.center)
                Button("Continue in Landscape", action: skip)
                    .buttonStyle(.bordered)
                    .tint(DT.Color.accent)
                    .padding(.top, DT.Spacing.xs)
            }
            .padding(DT.Spacing.xl)
            .frame(maxWidth: 480)
        }
    }
}

// MARK: - Setup

private struct PickSetupView: View {
    @Bindable var model: PickTogetherModel
    var started: () -> Void

    private enum Kind: String, CaseIterable, Identifiable {
        case movies, shows, both
        var id: Self { self }
        var label: LocalizedStringKey {
            switch self {
            case .movies: "Movies"
            case .shows: "Shows"
            case .both: "Both"
            }
        }
    }

    private var kind: Binding<Kind> {
        Binding {
            model.setup.movies && model.setup.shows ? .both : (model.setup.shows ? .shows : .movies)
        } set: { new in
            model.setup.movies = new != .shows
            model.setup.shows = new != .movies
        }
    }

    var body: some View {
        Form {
            Section {
                Picker("Watch", selection: kind) {
                    ForEach(Kind.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            if !model.genres.isEmpty {
                Section {
                    GenreChips(genres: model.genres, selected: $model.setup.genres)
                        .listRowInsets(EdgeInsets(top: DT.Spacing.sm, leading: DT.Spacing.sm, bottom: DT.Spacing.sm, trailing: DT.Spacing.sm))
                } header: {
                    Text("Genres")
                } footer: {
                    Text(model.setup.genres.isEmpty ? "Any genre." : "Titles in any of these genres.")
                }
            }
            Section {
                Toggle("Include Titles You've Watched", isOn: $model.setup.includeWatched)
            } footer: {
                Text("Off: only titles nobody in the session has watched.")
            }
            Section("More Options") {
                Picker("Show First", selection: $model.setup.order) {
                    Text("Highest Rated").tag(PickOrder.topRated)
                    Text("Recently Added").tag(PickOrder.recentlyAdded)
                    Text("Anything").tag(PickOrder.random)
                }
                Picker("It's a Match When", selection: $model.setup.rule) {
                    Text("Everyone Likes It").tag(PickRule.everyone)
                    Text("Most People Like It").tag(PickRule.most)
                }
                Toggle("Same Order for Everyone", isOn: $model.setup.sameOrder)
            }
        }
        .frame(maxWidth: 640)
        .frame(maxWidth: .infinity)
        .navigationTitle("New Session")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Start") {
                    Task {
                        await model.create()
                        if model.state != nil { started() }
                    }
                }
                .disabled(model.isBusy)
            }
        }
        .tint(DT.Color.accent)
    }
}

private struct GenreChips: View {
    let genres: [String]
    @Binding var selected: [String]

    var body: some View {
        FlowLayout(spacing: DT.Spacing.xs) {
            ForEach(genres, id: \.self) { genre in
                let on = selected.contains(genre)
                Button {
                    if on { selected.removeAll { $0 == genre } } else { selected.append(genre) }
                } label: {
                    Text(genre)
                        .font(DT.Font.button)
                        .padding(.horizontal, DT.Spacing.sm)
                        .padding(.vertical, DT.Spacing.xs)
                        .foregroundStyle(on ? DT.Color.onAccent : DT.Color.textPrimary)
                        .background(on ? DT.Color.accent : DT.Color.backgroundTertiary, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// Lays chips out in rows, wrapping to the next row when one is full.
private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row { var items: [Int] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].items.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
            }
            var row = rows[rows.count - 1]
            row.width += (row.items.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.items.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
