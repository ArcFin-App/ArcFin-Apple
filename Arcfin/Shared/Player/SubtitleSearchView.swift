// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import JellyfinAPI

/// Searches the server's subtitle providers for a title and has the server download the one
/// picked, which then shows up as a new subtitle track everywhere that title plays.
struct SubtitleSearchView: View {
    let itemId: String
    var onDownloaded: () -> Void = {}

    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    @State private var language: String
    @State private var results: [RemoteSubtitle] = []
    @State private var isSearching = false
    @State private var hasSearched = false
    @State private var downloadingId: String?
    @State private var errorMessage: String?

    private let client = JellyfinMediaClient()

    /// Jellyfin names languages by their ISO 639-2/B codes ("fre", "ger"), which is also what
    /// its subtitle providers expect.
    static let languages: [(code: String, name: String)] = [
        ("eng", "English"), ("spa", "Spanish"), ("fre", "French"), ("ger", "German"),
        ("ita", "Italian"), ("por", "Portuguese"), ("dut", "Dutch"), ("swe", "Swedish"),
        ("pol", "Polish"), ("rus", "Russian"), ("tur", "Turkish"), ("ara", "Arabic"),
        ("hin", "Hindi"), ("jpn", "Japanese"), ("kor", "Korean"), ("chi", "Chinese"),
    ]

    init(itemId: String, onDownloaded: @escaping () -> Void = {}) {
        self.itemId = itemId
        self.onDownloaded = onDownloaded
        let preferred = UserDefaults.standard.string(forKey: "preferredSubtitleLanguage") ?? ""
        _language = State(initialValue: Self.languages.contains { $0.code == preferred } ? preferred : "eng")
    }

    private var credential: ServerCredential? { authManager.state.credential }
    private var authHeader: String? { credential.map { authManager.authClient.authHeader(token: $0.accessToken) } }

    var body: some View {
        List {
            Section {
                Picker("Language", selection: $language) {
                    ForEach(Self.languages, id: \.code) { Text($0.name).tag($0.code) }
                }
            } footer: {
                Text("Uses the subtitle providers installed on your server, such as OpenSubtitles.")
            }

            if isSearching {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .listRowBackground(Color.clear)
            } else if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(DT.Color.textSecondary)
            } else if hasSearched && results.isEmpty {
                ContentUnavailableView("No Subtitles Found", systemImage: "captions.bubble",
                                       description: Text("Try another language."))
                    .listRowBackground(Color.clear)
            } else if !results.isEmpty {
                Section("\(results.count) found") {
                    ForEach(results) { subtitle in
                        Button { download(subtitle) } label: { row(subtitle) }
                            .disabled(downloadingId != nil)
                    }
                }
            }
        }
        .insetGroupedList()
        .screenBackground()
        .navigationTitle("Search Subtitles")
        .inlineNavigationTitle()
        .task(id: language) { await search() }
    }

    private func row(_ subtitle: RemoteSubtitle) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(subtitle.name)
                    .font(.system(.subheadline, weight: .medium))
                    .foregroundStyle(DT.Color.textPrimary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if subtitle.isHashMatch { tag("Exact match", color: DT.Color.accent) }
                    if subtitle.isHearingImpaired { tag("SDH") }
                    if subtitle.isForced { tag("Forced") }
                    if subtitle.isMachineTranslated { tag("Machine translated") }
                }
                Text(details(for: subtitle))
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if downloadingId == subtitle.id {
                ProgressView()
            } else {
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(DT.Color.accent)
                    .accessibilityLabel("Download")
            }
        }
        .contentShape(Rectangle())
    }

    private func tag(_ text: String, color: Color = DT.Color.textSecondary) -> some View {
        Text(text)
            .font(.system(.caption2, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
    }

    private func details(for subtitle: RemoteSubtitle) -> String {
        var parts: [String] = []
        if let provider = subtitle.providerName { parts.append(provider) }
        if let format = subtitle.format { parts.append(format.uppercased()) }
        if let count = subtitle.downloadCount, count > 0 { parts.append("\(count.formatted(.number.notation(.compactName))) downloads") }
        if let author = subtitle.author, !author.isEmpty { parts.append(author) }
        return parts.joined(separator: " · ")
    }

    private func search() async {
        guard let credential, let authHeader else { return }
        isSearching = true
        errorMessage = nil
        do {
            let found = try await client.searchRemoteSubtitles(credential: credential, authHeader: authHeader, itemId: itemId, language: language)
            guard !Task.isCancelled else { return }
            results = found.sorted { lhs, rhs in
                if lhs.isHashMatch != rhs.isHashMatch { return lhs.isHashMatch }
                return (lhs.downloadCount ?? 0) > (rhs.downloadCount ?? 0)
            }
        } catch is CancellationError {
            return
        } catch {
            results = []
            errorMessage = error.localizedDescription
        }
        hasSearched = true
        isSearching = false
    }

    private func download(_ subtitle: RemoteSubtitle) {
        guard let credential, let authHeader else { return }
        downloadingId = subtitle.id
        Task {
            do {
                try await client.downloadRemoteSubtitle(credential: credential, authHeader: authHeader, itemId: itemId, subtitleId: subtitle.id)
                HapticManager.impact(.light)
                onDownloaded()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            downloadingId = nil
        }
    }
}
