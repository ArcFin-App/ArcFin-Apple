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

/// The services and countries Seerr lists, for Streaming Services.
@MainActor @Observable
final class StreamingServicesModel {
    private(set) var available: [SeerrWatchProvider] = []
    private(set) var isLoading = true
    private(set) var errorMessage: String?
    private(set) var region = ""
    private(set) var automaticRegion = ""
    private(set) var regions: [(code: String, name: String)] = []

    func shown(matching query: String) -> [SeerrWatchProvider] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return available }
        return available.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    func load(seerrRepo: SeerrRepository) async {
        isLoading = true
        errorMessage = nil
        automaticRegion = await seerrRepo.automaticRegion()
        region = await seerrRepo.region()
        if regions.isEmpty {
            regions = await seerrRepo.streamingRegions()
            // Seerr gets this list from TMDB too; the system's countries stand in if it can't.
            if regions.isEmpty {
                regions = Locale.Region.isoRegions
                    .filter { $0.identifier.count == 2 }
                    .map { ($0.identifier, Locale.current.localizedString(forRegionCode: $0.identifier) ?? $0.identifier) }
                    .sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
            }
        }
        do {
            available = try await seerrRepo.streamingServices()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func regionName(_ code: String) -> String {
        code.isEmpty ? "…" : (Locale.current.localizedString(forRegionCode: code) ?? code)
    }

    /// `selected` with `provider` added or taken away.
    func toggling(_ provider: SeerrWatchProvider, in selected: [SeerrWatchProvider]) -> [SeerrWatchProvider] {
        var list = selected
        if let index = list.firstIndex(of: provider) { list.remove(at: index) } else { list.append(provider) }
        return list
    }

    /// Makes sure the rows actually show, for someone who has customised their shelves.
    func showRowsOnHome() {
        let raw = UserDefaults.standard.string(forKey: HomeShelfPrefs.activeKey) ?? ""
        var active = HomeShelfPrefs.active(from: raw)
        if !raw.isEmpty, !active.contains(.streamingServices) {
            active.insert(.streamingServices)
            UserDefaults.standard.set(HomeShelfPrefs.encode(active), forKey: HomeShelfPrefs.activeKey)
        }
    }
}

/// A streaming service's logo and name, with whether it's picked.
struct StreamingServiceRowLabel: View {
    let provider: SeerrWatchProvider
    let isSelected: Bool

    var body: some View {
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
}
