// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// Shared list content between the iOS/iPadOS sheet and the macOS in-place overlay panel
/// — .sheet(isPresented:) has now failed to render reliably on macOS twice in this
/// app (the other case was PlayerView's track/chapter menus), so rather than keep chasing
/// why, macOS gets its own chrome around this same content instead of relying on .sheet.
struct LibraryFilterList: View {
    let availableGenres: [String]
    let availableYears: [Int]
    let availableRatings: [String]
    let availableTags: [String]
    @Binding var selectedGenres: Set<String>
    @Binding var selectedYears: Set<Int>
    @Binding var watchedFilter: LibraryWatchedFilter
    @Binding var favoritesOnly: Bool
    @Binding var sortOption: LibrarySortOption
    @Binding var extraFilters: LibraryExtraFilters
    var sortOptions: [LibrarySortOption] = LibrarySortOption.standard

    var body: some View {
        List {
            // A Picker with .pickerStyle(.inline) here rendered as an empty section on
            // macOS — a known-unreliable style inside a List on that platform. Plain
            // tappable rows, same pattern as the Genre/Year sections below, work
            // identically everywhere since nothing depends on a platform picker style.
            Section {
                FilterGroup(title: "Sort By", value: sortOption.label) {
                    ForEach(sortOptions) { option in
                        filterRow(option.label, isSelected: sortOption == option) {
                            sortOption = option
                        }
                    }
                }
            }

            Section("Status") {
                Picker("Status", selection: $watchedFilter) {
                    ForEach(LibraryWatchedFilter.allCases) { filter in
                        Text(filter.label).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: watchedFilter) { HapticManager.selection() }
                Toggle("Favourites Only", isOn: $favoritesOnly)
            }

            if !availableGenres.isEmpty {
                Section {
                    FilterGroup(title: "Genre", value: Self.summary(selectedGenres)) {
                        if selectedGenres.count > 1 {
                            Picker("Match", selection: $extraFilters.matchAllGenres) {
                                Text("Any").tag(false)
                                Text("All").tag(true)
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: extraFilters.matchAllGenres) { HapticManager.selection() }
                        }
                        ForEach(availableGenres, id: \.self) { genre in
                            filterRow(genre, isSelected: selectedGenres.contains(genre)) {
                                toggle(genre, in: &selectedGenres)
                            }
                        }
                    }
                }
            }

            if !availableYears.isEmpty {
                Section {
                    FilterGroup(title: "Year", value: Self.summary(Set(selectedYears.map(String.init)))) {
                        ForEach(availableYears, id: \.self) { year in
                            filterRow(String(year), isSelected: selectedYears.contains(year)) {
                                toggle(year, in: &selectedYears)
                            }
                        }
                    }
                }
            }

            Section("Minimum Score") {
                minimumScoreControls
            }

            if !availableRatings.isEmpty {
                let ordered = LibraryExtraFilters.ordered(availableRatings)
                let step = LibraryExtraFilters.ratingStep(extraFilters.officialRatings, in: ordered)
                let label = step >= ordered.count ? String(localized: "Any") : String(localized: "Up to \(ordered[step])")
                Section("Content Rating") {
                    contentRatingControls(ordered: ordered, step: step, label: label)
                }
            }

            Section("Quality") {
                Picker("Resolution", selection: $extraFilters.quality) {
                    ForEach(LibraryQualityFilter.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: extraFilters.quality) { HapticManager.selection() }
                Toggle("Has Subtitles", isOn: $extraFilters.hasSubtitles)
            }

            if !availableTags.isEmpty {
                Section {
                    FilterGroup(title: "Tags", value: Self.summary(extraFilters.tags)) {
                        ForEach(availableTags, id: \.self) { tag in
                            filterRow(tag, isSelected: extraFilters.tags.contains(tag)) {
                                toggle(tag, in: &extraFilters.tags)
                            }
                        }
                    }
                }
            }

            if !selectedGenres.isEmpty || !selectedYears.isEmpty || watchedFilter != .all || favoritesOnly
                || extraFilters.isActive {
                Section {
                    Button(role: .destructive) {
                        selectedGenres.removeAll()
                        selectedYears.removeAll()
                        extraFilters = LibraryExtraFilters()
                        watchedFilter = .all
                        favoritesOnly = false
                    } label: {
                        Text("Clear All Filters").frame(maxWidth: .infinity, alignment: .center)
                    }
                    .formRowButton()
                }
            }
        }
    }

    private static func summary(_ selected: Set<String>) -> String {
        switch selected.count {
        case 0: String(localized: "Any")
        case 1: selected.first ?? String(localized: "Any")
        default: String(localized: "\(selected.count) selected")
        }
    }

    private func filterRow(_ label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            HapticManager.selection()
            action()
        } label: {
            HStack {
                Text(label).foregroundStyle(DT.Color.textPrimary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark").foregroundStyle(DT.Color.accent)
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func toggle<T: Hashable>(_ value: T, in set: inout Set<T>) {
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
    }
}

struct LibraryFilterSheet: View {
    let availableGenres: [String]
    let availableYears: [Int]
    let availableRatings: [String]
    let availableTags: [String]
    @Binding var selectedGenres: Set<String>
    @Binding var selectedYears: Set<Int>
    @Binding var watchedFilter: LibraryWatchedFilter
    @Binding var favoritesOnly: Bool
    @Binding var sortOption: LibrarySortOption
    @Binding var extraFilters: LibraryExtraFilters
    var sortOptions: [LibrarySortOption] = LibrarySortOption.standard

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            LibraryFilterList(
                availableGenres: availableGenres, availableYears: availableYears, availableRatings: availableRatings, availableTags: availableTags,
                selectedGenres: $selectedGenres, selectedYears: $selectedYears,
                watchedFilter: $watchedFilter, favoritesOnly: $favoritesOnly, sortOption: $sortOption,
                extraFilters: $extraFilters, sortOptions: sortOptions
            )
            .sheetTitle("Filter & Sort")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
