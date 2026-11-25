// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import SeerrAPI

/// On a title's page: its open Seerr issues and Report a Problem. Shows nothing without Seerr,
/// for a title Seerr hasn't seen, or when there's nothing open and the person can't report.
struct TitleIssuesSection: View {
    let tmdbId: Int?
    let mediaType: RequestMediaType?

    @Environment(SeerrRepository.self) private var seerrRepo

    @State private var title: SeerrTitleIssues?
    @State private var permissions = SeerrIssuePermissions.none
    @State private var reporting = false
    @State private var opened: SeerrIssue?

    private var openIssues: [SeerrIssue] { title?.issues.filter(\.isOpen) ?? [] }
    private var canReport: Bool { permissions.canCreate && title?.mediaID != nil }

    var body: some View {
        Group {
            if canReport || !openIssues.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Issues")
                        .font(.system(.headline, weight: .semibold))
                        .foregroundStyle(DT.Color.textPrimary)
                    ForEach(openIssues) { issue in
                        Button { opened = issue } label: { SeerrIssueRow(issue: issue, showsTitle: false) }
                            .buttonStyle(.plain)
                    }
                    if canReport {
                        Button { reporting = true } label: {
                            Label("Report a Problem", systemImage: "exclamationmark.bubble")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .tvFocusSection()
            }
        }
        .task(id: tmdbId) { await load() }
        .appSheet(isPresented: $reporting, title: "Report a Problem", systemImage: "exclamationmark.bubble") {
            if let mediaID = title?.mediaID, let mediaType {
                NavigationStack {
                    SeerrReportIssueView(mediaID: mediaID, mediaType: mediaType, seasons: title?.seasons ?? []) {
                        Task { await load() }
                    }
                }
            }
        }
        .appSheet(item: $opened) { issue in
            NavigationStack {
                SeerrIssueDetailView(issueID: issue.id, onChange: { Task { await load() } })
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { opened = nil }
                        }
                    }
            }
        }
    }

    private func load() async {
        guard seerrRepo.isConfigured, let tmdbId, let mediaType else { return }
        permissions = await seerrRepo.issuePermissions()
        title = await seerrRepo.titleIssues(mediaType: mediaType, tmdbId: tmdbId)
    }
}
