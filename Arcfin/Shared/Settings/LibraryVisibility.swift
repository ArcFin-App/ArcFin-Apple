// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI
import AuthCore

/// Libraries hidden from Browse on this device.
enum LibraryVisibility {
    static let hiddenKey = "hiddenLibraryIDs"

    static var hiddenIDs: Set<String> {
        Set((UserDefaults.standard.string(forKey: hiddenKey) ?? "").split(separator: ",").map(String.init))
    }
}

/// The libraries Recently Added leaves out, kept in the Jellyfin account.
@MainActor @Observable
final class LibraryVisibilityModel {
    private(set) var latestExcluded: Set<String> = []
    private(set) var latestLoaded = false
    private(set) var errorMessage: String?

    private let client = JellyfinMediaClient()

    func load(authManager: AuthManager) async {
        guard let credential = authManager.state.credential else { return }
        let header = authManager.authClient.authHeader(token: credential.accessToken)
        if let ids = try? await client.getLatestExcludedLibraries(credential: credential, authHeader: header) {
            latestExcluded = Set(ids)
            latestLoaded = true
        } else {
            errorMessage = String(localized: "Couldn't load this from your server.")
        }
    }

    func setLatest(_ id: String, shown: Bool, authManager: AuthManager) {
        guard let credential = authManager.state.credential else { return }
        let header = authManager.authClient.authHeader(token: credential.accessToken)
        let previous = latestExcluded
        if shown { latestExcluded.remove(id) } else { latestExcluded.insert(id) }
        let ids = Array(latestExcluded)
        Task {
            do {
                try await client.setLatestExcludedLibraries(ids, credential: credential, authHeader: header)
                errorMessage = nil
            } catch {
                latestExcluded = previous
                errorMessage = String(localized: "Couldn't save this to your server.")
            }
        }
    }
}

/// Which libraries show in Browse (kept on this device) and in Recently Added (kept in the
/// Jellyfin account, so other apps follow it too).
struct LibraryVisibilityView: View {
    @Environment(MediaRepository.self) private var mediaRepo
    @Environment(AuthManager.self) private var authManager
    @AppStorage(LibraryVisibility.hiddenKey) private var hiddenString = ""
    @State private var model = LibraryVisibilityModel()

    private var libraries: [JellyfinLibrary] {
        mediaRepo.libraries.filter { $0.collectionType != .livetv }
    }

    private var hidden: Set<String> {
        Set(hiddenString.split(separator: ",").map(String.init))
    }

    var body: some View {
        List {
            Section {
                ForEach(libraries) { library in
                    Toggle(isOn: Binding(
                        get: { !hidden.contains(library.id) },
                        set: { shown in
                            var ids = hidden
                            if shown { ids.remove(library.id) } else { ids.insert(library.id) }
                            hiddenString = ids.sorted().joined(separator: ",")
                        }
                    )) {
                        TVRowLabelText(verbatim: library.name)
                    }
                    .tvListRow()
                    .syncLocked(LibraryVisibility.hiddenKey, authManager)
                }
            } header: {
                Text("Show in Browse")
            }

            Section {
                ForEach(libraries) { library in
                    Toggle(isOn: Binding(
                        get: { !model.latestExcluded.contains(library.id) },
                        set: { shown in model.setLatest(library.id, shown: shown, authManager: authManager) }
                    )) {
                        TVRowLabelText(verbatim: library.name)
                    }
                    .tvListRow()
                    .disabled(!model.latestLoaded)
                }
            } header: {
                Text("Show in Recently Added")
            } footer: {
                Text(model.errorMessage ?? String(localized: "Saved to your Jellyfin account, so it applies in its other apps too. Home updates the next time it refreshes."))
                    .font(.caption)
                    .foregroundStyle(model.errorMessage == nil ? DT.Color.textSecondary : DT.Color.palette("F43F5E"))
            }
        }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge("Libraries")
        .task { await model.load(authManager: authManager) }
    }
}
