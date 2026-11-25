// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import SeerrAPI

/// Reporting a problem with a title to Seerr: what kind, for a show which season and episode,
/// and what's wrong. Seerr wants the description, so Send waits for one.
struct SeerrReportIssueView: View {
    let mediaID: Int
    let mediaType: RequestMediaType
    let seasons: [SeerrTitleIssues.Season]
    var onSent: () -> Void = {}

    @Environment(SeerrRepository.self) private var seerrRepo
    @Environment(\.dismiss) private var dismiss

    @State private var type: SeerrIssueType = .video
    @State private var season = 0
    @State private var episode = 0
    @State private var message = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    private var episodeCount: Int { seasons.first { $0.number == season }?.episodeCount ?? 0 }

    var body: some View {
        Form {
            Section {
                Picker("Problem With", selection: $type) {
                    ForEach(SeerrIssueType.allCases) { type in
                        Label(type.label, systemImage: type.systemImage).tag(type)
                    }
                }
                .pickerStyle(.menu)
                if mediaType == .tv, !seasons.isEmpty {
                    Picker("Season", selection: $season) {
                        Text("All Seasons").tag(0)
                        ForEach(seasons) { Text("Season \($0.number)").tag($0.number) }
                    }
                    .pickerStyle(.menu)
                    if season > 0, episodeCount > 0 {
                        Picker("Episode", selection: $episode) {
                            Text("All Episodes").tag(0)
                            ForEach(1...episodeCount, id: \.self) { Text("Episode \($0)").tag($0) }
                        }
                        .pickerStyle(.menu)
                    }
                }
            }
            Section {
                TextField("What's wrong?", text: $message, axis: .vertical)
                    .lineLimit(3...8)
            } footer: {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(DT.Color.palette("F43F5E"))
                } else {
                    Text("Your server's admin sees this in Seerr and can reply here.")
                }
            }
            Section {
                Button {
                    Task { await send() }
                } label: {
                    if isSending { ProgressView() } else { Label("Send Report", systemImage: "paperplane") }
                }
                .disabled(isSending || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .formStyle(.grouped)
        .onChange(of: season) { _, _ in episode = 0 }
        .sheetTitle("Report a Problem")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }

    private func send() async {
        isSending = true
        defer { isSending = false }
        do {
            try await seerrRepo.reportIssue(type: type, message: message.trimmingCharacters(in: .whitespacesAndNewlines), mediaID: mediaID,
                                            season: season > 0 ? season : nil, episode: episode > 0 ? episode : nil)
            onSent()
            dismiss()
        } catch {
            errorMessage = String(localized: "Seerr didn't take the report. You may not have permission to report problems, or Seerr couldn't be reached.")
        }
    }
}
