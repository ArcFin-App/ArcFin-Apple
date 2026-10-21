// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import SeerrAPI

/// The user's own TMDB key. With it, title pages, streaming rows and Home's catalogue shelves
/// work without Seerr, and keep working when Seerr's requests fail.
struct TMDBSettingsView: View {
    @Environment(SeerrRepository.self) private var seerrRepo

    @State private var key = TMDBCredential.load() ?? ""
    @State private var status: Status = .idle

    private enum Status: Equatable {
        case idle, checking, ok
        case failed(String)
    }

    var body: some View {
        List {
            Section {
                SecureField("API key or read access token", text: $key)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif
                    .font(.system(.body, design: .monospaced))
                Button("Save and Test") { Task { await saveAndTest() } }
                    .disabled(status == .checking)
                if !key.isEmpty {
                    Button("Remove Key", role: .destructive) {
                        key = ""
                        try? TMDBCredential.save("")
                        seerrRepo.reloadTMDB()
                        status = .idle
                    }
                }
            } footer: {
                Text("Optional. With your own free key from themoviedb.org (Settings → API), Arcfin can show where titles are streaming, review details and what's popular without Seerr, and fill in when Seerr can't reach TMDB. Requests still need Seerr. The key is stored in the Keychain.")
            }

            switch status {
            case .idle: EmptyView()
            case .checking:
                Section { HStack { ProgressView(); Text("Checking…").foregroundStyle(DT.Color.textSecondary) } }
            case .ok:
                Section { Label("Connected to TMDB", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            case .failed(let message):
                Section {
                    Label("TMDB didn't accept this key", systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                    Text(message).font(.footnote).foregroundStyle(DT.Color.textSecondary)
                }
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge("TMDB")
    }

    private func saveAndTest() async {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        status = .checking
        do {
            _ = try await TMDBClient(key: trimmed).trending()
            try TMDBCredential.save(trimmed)
            seerrRepo.reloadTMDB()
            status = .ok
            Task { await seerrRepo.loadDiscover() }
        } catch {
            status = .failed(error.localizedDescription)
        }
    }
}
