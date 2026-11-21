// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import JellyfinAPI

@MainActor @Observable
final class AdminActivityModel {
    private(set) var entries: [JellyfinActivityEntry] = []
    private(set) var isLoading = true
    private(set) var reachedEnd = false
    private(set) var errorMessage: String?

    private let admin = JellyfinAdminClient()
    private let pageSize = 50

    func load(authManager: AuthManager) async {
        guard let access = AdminAccess.session(authManager) else { return }
        do {
            entries = try await admin.activity(limit: pageSize, credential: access.credential, authHeader: access.header)
            reachedEnd = entries.count < pageSize
            errorMessage = nil
        } catch {
            errorMessage = String(localized: "Couldn't load the server's activity.")
        }
        isLoading = false
    }

    func loadMore(authManager: AuthManager) async {
        guard !reachedEnd, let access = AdminAccess.session(authManager),
              let more = try? await admin.activity(startIndex: entries.count, limit: pageSize, credential: access.credential, authHeader: access.header)
        else { return }
        let known = Set(entries.map(\.id))
        entries += more.filter { !known.contains($0.id) }
        reachedEnd = more.count < pageSize
    }
}

/// The server's activity log, newest first: sign-ins, playback, tasks, plugin changes.
struct AdminActivityView: View {
    @Environment(AuthManager.self) private var authManager
    @State private var model = AdminActivityModel()

    var body: some View {
        List {
            if let error = model.errorMessage {
                Text(error).foregroundStyle(DT.Color.textSecondary)
            }
            ForEach(model.entries) { entry in
                AdminActivityRow(entry: entry)
                    .onAppear {
                        if entry.id == model.entries.last?.id { Task { await model.loadMore(authManager: authManager) } }
                    }
            }
        }
        .overlay { if model.isLoading { ProgressView() } }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge("Activity")
        .task { await model.load(authManager: authManager) }
        .refreshable { await model.load(authManager: authManager) }
    }
}

private struct AdminActivityRow: View {
    let entry: JellyfinActivityEntry

    private var icon: (name: String, color: Color) {
        switch entry.severity {
        case "Error": ("xmark.octagon.fill", DT.Color.palette("F43F5E"))
        case "Warning": ("exclamationmark.triangle.fill", DT.Color.palette("f59e0b"))
        default:
            switch entry.type {
            case let type where type.contains("Session") || type.contains("Authentication"): ("person.crop.circle", DT.Color.palette("60A5FA"))
            case let type where type.contains("Playback") || type.contains("VideoPlayback"): ("play.circle", DT.Color.accent)
            case let type where type.contains("Plugin") || type.contains("Package"): ("puzzlepiece.extension", DT.Color.palette("10b981"))
            case let type where type.contains("Task"): ("clock", DT.Color.textSecondary)
            default: ("info.circle", DT.Color.textSecondary)
            }
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon.name)
                .foregroundStyle(icon.color)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name)
                    .font(.system(.subheadline))
                    .foregroundStyle(DT.Color.textPrimary)
                if let overview = entry.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.system(.caption))
                        .foregroundStyle(DT.Color.textSecondary)
                        .lineLimit(3)
                }
                if let date = entry.date {
                    Text(date, format: .relative(presentation: .named))
                        .font(.system(.caption2))
                        .foregroundStyle(DT.Color.textSecondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
