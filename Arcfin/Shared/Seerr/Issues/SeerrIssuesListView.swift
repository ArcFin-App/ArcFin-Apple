// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import SeerrAPI

/// Seerr's issues, newest change first: everyone's for people who may view them all, otherwise
/// the person's own, as Seerr decides. Open, resolved or all.
struct SeerrIssuesListView: View {
    @Environment(SeerrRepository.self) private var seerrRepo

    @State private var filter: SeerrIssueFilter = .open
    @State private var issues: [SeerrIssue] = []
    @State private var permissions = SeerrIssuePermissions.none
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var opened: SeerrIssue?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Show", selection: $filter) {
                    Text("Open").tag(SeerrIssueFilter.open)
                    Text("Resolved").tag(SeerrIssueFilter.resolved)
                    Text("All").tag(SeerrIssueFilter.all)
                }
                .pickerStyle(.segmented)
                .padding(.bottom, 4)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(.caption))
                        .foregroundStyle(DT.Color.palette("F43F5E"))
                }
                if isLoading && issues.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 160)
                } else if issues.isEmpty {
                    ContentUnavailableView(emptyTitle, systemImage: "checkmark.bubble",
                                           description: Text(permissions.canViewAll
                                                             ? "Problems people report with a title show here."
                                                             : "Problems you report with a title show here."))
                        .frame(minHeight: 220)
                } else {
                    ForEach(issues) { issue in
                        Button { opened = issue } label: { SeerrIssueRow(issue: issue) }
                            .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, DT.Spacing.pagePad)
            .padding(.top, 12)
            Spacer().frame(height: DT.Size.tabBarHeight + 16)
        }
        .screenBackground()
        .navigationTitle("Issues")
        .arcfinNavTitleLarge("Issues")
        .navigationDestination(item: $opened) { issue in
            SeerrIssueDetailView(issueID: issue.id, onChange: { Task { await load() } })
        }
        .task(id: filter) { await load() }
        .refreshable { await load() }
    }

    private var emptyTitle: String {
        switch filter {
        case .open: String(localized: "No Open Issues")
        case .resolved: String(localized: "No Resolved Issues")
        case .all: String(localized: "No Issues")
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        permissions = await seerrRepo.issuePermissions()
        do {
            issues = try await seerrRepo.issues(filter: filter)
            errorMessage = nil
        } catch where !SeerrRepository.isCancellation(error) {
            errorMessage = String(localized: "Couldn't load issues from Seerr.")
        } catch {}
    }
}
