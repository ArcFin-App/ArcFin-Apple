// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import SeerrAPI

struct StreamingServicesView: View {
    @Environment(SeerrRepository.self) private var seerrRepo
    @AppStorage(StreamingServicePrefs.key) private var selectedData = Data()

    @State private var model = StreamingServicesModel()
    @AppStorage(SeerrRepository.regionOverrideKey) private var regionOverride = ""
    @State private var query = ""

    private var selected: [SeerrWatchProvider] { StreamingServicePrefs.decode(selectedData) }

    var body: some View {
        List {
            if query.isEmpty {
                Section {
                    SettingsPicker("Country", selection: $regionOverride,
                                   options: [""] + model.regions.map(\.code)) { code in
                        code.isEmpty
                            ? Text("Automatic (\(model.regionName(model.automaticRegion)))")
                            : Text(verbatim: model.regions.first { $0.code == code }?.name ?? model.regionName(code))
                    }
                } footer: {
                    Text("Automatic uses the region set in Seerr, the same one its own pages use. Choose a country to see what streams there instead.")
                }
            }
            if !selected.isEmpty && query.isEmpty {
                Section {
                    ForEach(Array(selected.enumerated()), id: \.element) { index, provider in
                        row(provider)
                            .contextMenu {
                                Button("Move Up") { moveService(at: index, by: -1) }.disabled(index == 0)
                                Button("Move Down") { moveService(at: index, by: 1) }.disabled(index == selected.count - 1)
                            }
                    }
                } header: {
                    Text("Your Services")
                } footer: {
                    Text("Each gets a Popular on … row on Home, in this order. Press and hold one to move it.")
                }
            }
            Section {
                if model.isLoading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if let errorMessage = model.errorMessage {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Couldn't load streaming services.")
                            .foregroundStyle(DT.Color.textPrimary)
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(DT.Color.textSecondary)
                        Button("Try Again") { Task { await model.load(seerrRepo: seerrRepo) } }
                            .foregroundStyle(DT.Color.accent)
                    }
                } else if model.available.isEmpty {
                    Text("Seerr has no streaming services listed for this country.")
                        .foregroundStyle(DT.Color.textSecondary)
                } else {
                    ForEach(model.shown(matching: query)) { provider in row(provider) }
                }
            } header: {
                if !model.region.isEmpty {
                    Text("Available in \(Locale.current.localizedString(forRegionCode: model.region) ?? model.region)")
                }
            } footer: {
                // JustWatch supplies this data through TMDB, which asks for it to be credited.
                Text("Availability from JustWatch")
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge("Popular Elsewhere")
        .searchable(text: $query, prompt: "Search services")
        .task { await model.load(seerrRepo: seerrRepo) }
        .onChange(of: regionOverride) { Task { await model.load(seerrRepo: seerrRepo) } }
    }

    private func moveService(at index: Int, by offset: Int) {
        var list = selected
        let target = index + offset
        guard list.indices.contains(target) else { return }
        list.swapAt(index, target)
        selectedData = StreamingServicePrefs.encode(list)
    }

    private func row(_ provider: SeerrWatchProvider) -> some View {
        let isSelected = selected.contains(provider)
        return Button { toggle(provider) } label: {
            StreamingServiceRowLabel(provider: provider, isSelected: isSelected)
        }
        .tvListRow()
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func toggle(_ provider: SeerrWatchProvider) {
        let list = model.toggling(provider, in: selected)
        selectedData = StreamingServicePrefs.encode(list)
        HapticManager.impact(.light)
        if !list.isEmpty { model.showRowsOnHome() }
    }
}
