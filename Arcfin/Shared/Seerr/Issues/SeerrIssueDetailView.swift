// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import SeerrAPI

/// One Seerr issue: the title, what kind of problem and where, its comments oldest first, a
/// reply box, and for the reporter or an issue manager, resolve or reopen and delete.
struct SeerrIssueDetailView: View {
    let issueID: Int
    /// After a reply, a status change or a delete, so the list behind can reload.
    var onChange: () -> Void = {}

    @Environment(SeerrRepository.self) private var seerrRepo
    @Environment(\.dismiss) private var dismiss

    @State private var issue: SeerrIssue?
    @State private var title: SeerrItem?
    @State private var permissions = SeerrIssuePermissions.none
    @State private var reply = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var confirmingDelete = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: DT.Spacing.md) {
                if let issue {
                    header(issue)
                    if permissions.canChange(issue) { actions(issue) }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(.caption))
                            .foregroundStyle(DT.Color.palette("F43F5E"))
                    }
                    comments(issue)
                    replyBox
                } else if let errorMessage {
                    ContentUnavailableView("Couldn't Load This Issue", systemImage: "exclamationmark.bubble",
                                           description: Text(errorMessage))
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                }
            }
            .padding(.horizontal, DT.Spacing.pagePad)
            .padding(.top, 12)
            Spacer().frame(height: DT.Size.tabBarHeight + 16)
        }
        .screenBackground()
        .navigationTitle(Text("Issue \(issueID)"))
        .alert("Delete This Issue?", isPresented: $confirmingDelete) {
            Button("Delete Issue", role: .destructive) { Task { await delete() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its comments are deleted too.")
        }
        .task(id: issueID) { await load() }
    }

    private func header(_ issue: SeerrIssue) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if let url = title?.posterURL {
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    default: DT.Color.textPrimary.opacity(0.06)
                    }
                }
                .frame(width: 72, height: 108)
                .clipShape(RoundedRectangle(cornerRadius: DT.Radius.card))
            }
            VStack(alignment: .leading, spacing: 6) {
                if let name = title?.title {
                    Text(name)
                        .font(.system(.title3, weight: .bold))
                        .foregroundStyle(DT.Color.textPrimary)
                }
                Label(issue.type.label, systemImage: issue.type.systemImage)
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(DT.Color.textPrimary)
                if let place = issue.whereText {
                    Text(place)
                        .font(.system(.footnote))
                        .foregroundStyle(DT.Color.textSecondary)
                }
                StatusPill(label: issue.statusLabel, color: issue.statusColor)
                if let name = issue.createdBy?.name, !name.isEmpty {
                    Text(issue.createdAt.map { String(localized: "Reported by \(name), \($0.formatted(date: .abbreviated, time: .shortened))") }
                         ?? String(localized: "Reported by \(name)"))
                        .font(DT.Font.caption2)
                        .foregroundStyle(DT.Color.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func actions(_ issue: SeerrIssue) -> some View {
        HStack(spacing: 12) {
            Button {
                Task { await setResolved(issue.isOpen) }
            } label: {
                Label(issue.isOpen ? "Resolve" : "Reopen", systemImage: issue.isOpen ? "checkmark.circle" : "arrow.uturn.backward.circle")
            }
            .buttonStyle(.borderedProminent)
            Button(role: .destructive) { confirmingDelete = true } label: {
                Label("Delete", systemImage: "trash")
            }
            .buttonStyle(.bordered)
        }
        .disabled(isWorking)
    }

    private func comments(_ issue: SeerrIssue) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Comments")
                .font(.system(.caption, weight: .semibold))
                .foregroundStyle(DT.Color.textSecondary)
            if issue.comments.isEmpty {
                Text("No comments yet.")
                    .font(.system(.footnote))
                    .foregroundStyle(DT.Color.textSecondary)
            }
            ForEach(issue.comments) { comment in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(comment.user?.name ?? "")
                            .font(.system(.caption, weight: .semibold))
                            .foregroundStyle(DT.Color.textPrimary)
                        Spacer(minLength: 0)
                        if let date = comment.createdAt {
                            Text(date, style: .relative)
                                .font(DT.Font.caption2)
                                .foregroundStyle(DT.Color.textSecondary)
                        }
                    }
                    Text(comment.message)
                        .font(.system(.footnote))
                        .foregroundStyle(DT.Color.textPrimary.opacity(0.9))
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DT.Color.textPrimary.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var replyBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Add a comment", text: $reply, axis: .vertical)
                .lineLimit(1...5)
                .padding(10)
                .background(DT.Color.textPrimary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            Button {
                Task { await send() }
            } label: {
                Label("Send", systemImage: "paperplane")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isWorking || reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func load() async {
        permissions = await seerrRepo.issuePermissions()
        do {
            let loaded = try await seerrRepo.issue(id: issueID)
            issue = loaded
            errorMessage = nil
            if title == nil { title = await seerrRepo.title(of: loaded) }
        } catch where !SeerrRepository.isCancellation(error) {
            errorMessage = String(localized: "Seerr couldn't be reached, or the issue was deleted.")
        } catch {}
    }

    private func send() async {
        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        await work {
            issue = try await seerrRepo.comment(on: issueID, message: text)
            reply = ""
        }
    }

    private func setResolved(_ resolved: Bool) async {
        await work { issue = try await seerrRepo.setIssueResolved(issueID, resolved: resolved) }
    }

    private func delete() async {
        await work {
            try await seerrRepo.deleteIssue(issueID)
            dismiss()
        }
    }

    private func work(_ change: () async throws -> Void) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await change()
            errorMessage = nil
            onChange()
        } catch {
            errorMessage = String(localized: "Seerr didn't accept that. You may not have permission, or Seerr couldn't be reached.")
        }
    }
}
