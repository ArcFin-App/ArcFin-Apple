// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import SeerrAPI

/// The streaming services someone subscribes to, in the order picked. Each gets a "Popular
/// on …" row on Home, from Seerr.
enum StreamingServicePrefs {
    static let key = "streamingServices"

    static func decode(_ data: Data) -> [SeerrWatchProvider] {
        (try? JSONDecoder().decode([SeerrWatchProvider].self, from: data)) ?? []
    }

    static func encode(_ providers: [SeerrWatchProvider]) -> Data {
        (try? JSONEncoder().encode(providers)) ?? Data()
    }
}

struct StreamingServicesView: View {
    @Environment(SeerrRepository.self) private var seerrRepo
    @AppStorage(StreamingServicePrefs.key) private var selectedData = Data()

    @State private var available: [SeerrWatchProvider] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var region = ""
    @State private var query = ""

    private var selected: [SeerrWatchProvider] { StreamingServicePrefs.decode(selectedData) }

    private var shown: [SeerrWatchProvider] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return available }
        return available.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        List {
            if !selected.isEmpty && query.isEmpty {
                Section {
                    ForEach(selected) { provider in row(provider) }
                        .onMove { from, to in
                            var list = selected
                            list.move(fromOffsets: from, toOffset: to)
                            selectedData = StreamingServicePrefs.encode(list)
                        }
                } header: {
                    Text("Your Services")
                } footer: {
                    Text("Each gets a Popular on … row on Home, in this order.")
                }
            }
            Section {
                if isLoading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if let errorMessage {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Couldn't load services from Seerr.")
                            .foregroundStyle(DT.Color.textPrimary)
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(DT.Color.textSecondary)
                        Button("Try Again") { Task { await load() } }
                            .foregroundStyle(DT.Color.accent)
                    }
                } else if available.isEmpty {
                    Text("Seerr has no streaming services listed for this country.")
                        .foregroundStyle(DT.Color.textSecondary)
                } else {
                    ForEach(shown) { provider in row(provider) }
                }
            } header: {
                if !region.isEmpty {
                    Text("Available in \(Locale.current.localizedString(forRegionCode: region) ?? region)")
                }
            } footer: {
                Text("The country comes from your region setting in Seerr, the same one its own pages use.")
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge("Streaming Services")
        .searchable(text: $query, prompt: "Search services")
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        region = await seerrRepo.region()
        do {
            available = try await seerrRepo.streamingServices()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func row(_ provider: SeerrWatchProvider) -> some View {
        let isSelected = selected.contains(provider)
        return Button { toggle(provider) } label: {
            HStack(spacing: 12) {
                CachedAsyncImage(url: provider.logoURL) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    default: DT.Color.backgroundTertiary
                    }
                }
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(provider.name)
                    .foregroundStyle(DT.Color.textPrimary)
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? DT.Color.accent : DT.Color.textSecondary.opacity(0.5))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func toggle(_ provider: SeerrWatchProvider) {
        var list = selected
        if let index = list.firstIndex(of: provider) { list.remove(at: index) } else { list.append(provider) }
        selectedData = StreamingServicePrefs.encode(list)
        HapticManager.impact(.light)
        // Make sure the rows actually show, for someone who has customised their shelves.
        if !list.isEmpty {
            let raw = UserDefaults.standard.string(forKey: HomeShelfPrefs.activeKey) ?? ""
            var active = HomeShelfPrefs.active(from: raw)
            if !raw.isEmpty, !active.contains(.streamingServices) {
                active.insert(.streamingServices)
                UserDefaults.standard.set(HomeShelfPrefs.encode(active), forKey: HomeShelfPrefs.activeKey)
            }
        }
    }
}
