// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import AuthCore
import JellyfinAPI

@MainActor @Observable
final class AdminTasksModel {
    private(set) var tasks: [JellyfinScheduledTask] = []
    private(set) var isLoading = true
    private(set) var errorMessage: String?
    var actionError: String?

    @ObservationIgnored private var pollTask: Task<Void, Never>?
    private let admin = JellyfinAdminClient()

    /// By category, in the server's own category order.
    var categories: [(name: String, tasks: [JellyfinScheduledTask])] {
        var order: [String] = []
        var byCategory: [String: [JellyfinScheduledTask]] = [:]
        for task in tasks {
            if byCategory[task.category] == nil { order.append(task.category) }
            byCategory[task.category, default: []].append(task)
        }
        return order.map { ($0, byCategory[$0] ?? []) }
    }

    func load(authManager: AuthManager) async {
        guard let access = AdminAccess.session(authManager) else {
            errorMessage = AdminAccess.unavailableMessage
            isLoading = false
            return
        }
        do {
            tasks = try await admin.scheduledTasks(credential: access.credential, authHeader: access.header)
            errorMessage = nil
        } catch {
            errorMessage = String(localized: "Couldn't load the server's tasks.")
        }
        isLoading = false
    }

    func run(_ task: JellyfinScheduledTask, authManager: AuthManager) {
        guard let access = AdminAccess.session(authManager) else { return }
        Task {
            do {
                try await admin.startTask(id: task.id, credential: access.credential, authHeader: access.header)
                HapticManager.impact(.light)
                await load(authManager: authManager)
            } catch {
                actionError = String(localized: "“\(task.name)” didn't start.")
            }
        }
    }

    func stop(_ task: JellyfinScheduledTask, authManager: AuthManager) {
        guard let access = AdminAccess.session(authManager) else { return }
        Task {
            do {
                try await admin.stopTask(id: task.id, credential: access.credential, authHeader: access.header)
                await load(authManager: authManager)
            } catch {
                actionError = String(localized: "“\(task.name)” didn't stop.")
            }
        }
    }

    /// Every two seconds while the screen is open, so running tasks show their progress.
    func startPolling(authManager: AuthManager) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self, !Task.isCancelled else { return }
                if self.tasks.contains(where: { $0.state != .idle }) { await self.load(authManager: authManager) }
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }
}

/// Scheduled tasks: what each does, when it last ran and how it went, with Run Now.
struct AdminTasksView: View {
    @Environment(AuthManager.self) private var authManager
    @State private var model = AdminTasksModel()

    var body: some View {
        List {
            if let error = model.errorMessage {
                Section { Text(error).foregroundStyle(DT.Color.textSecondary) }
            }
            ForEach(model.categories, id: \.name) { category in
                Section(category.name) {
                    ForEach(category.tasks) { task in
                        AdminTaskRow(task: task,
                                     run: { model.run(task, authManager: authManager) },
                                     stop: { model.stop(task, authManager: authManager) })
                    }
                }
            }
        }
        .overlay { if model.isLoading { ProgressView() } }
        .arcfinListStyle()
        .screenBackground()
        .arcfinNavTitleLarge("Scheduled Tasks")
        .task { await model.load(authManager: authManager) }
        .refreshable { await model.load(authManager: authManager) }
        .onAppear { model.startPolling(authManager: authManager) }
        .onDisappear { model.stopPolling() }
        .alert("Couldn't Do That", isPresented: Binding(get: { model.actionError != nil }, set: { if !$0 { model.actionError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.actionError ?? "")
        }
    }
}

private struct AdminTaskRow: View {
    let task: JellyfinScheduledTask
    let run: () -> Void
    let stop: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(task.name)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(DT.Color.textPrimary)
                if let description = task.description, !description.isEmpty {
                    Text(description)
                        .font(.system(.caption))
                        .foregroundStyle(DT.Color.textSecondary)
                        .lineLimit(2)
                }
                if task.state == .running {
                    ProgressView(value: (task.progress ?? 0) / 100)
                        .tint(DT.Color.accent)
                    Text(((task.progress ?? 0) / 100).formatted(.percent.precision(.fractionLength(0))))
                        .font(.system(.caption2, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(DT.Color.textSecondary)
                } else if let end = task.lastRunEnd {
                    HStack(spacing: 4) {
                        Image(systemName: task.lastResult == "Failed" ? "xmark.octagon.fill" : "checkmark.circle.fill")
                            .foregroundStyle(task.lastResult == "Failed" ? DT.Color.palette("F43F5E") : DT.Color.palette("10b981"))
                        Text(task.lastResult == "Failed" ? "Failed \(end, format: .relative(presentation: .named))"
                             : "Ran \(end, format: .relative(presentation: .named))")
                    }
                    .font(.system(.caption2))
                    .foregroundStyle(DT.Color.textSecondary)
                } else {
                    Text("Hasn't run yet")
                        .font(.system(.caption2))
                        .foregroundStyle(DT.Color.textSecondary)
                }
            }
            Spacer(minLength: 8)
            if task.state == .idle {
                Button("Run", action: run)
                    .buttonStyle(.bordered)
                    .tint(DT.Color.accent)
                    .controlSize(.small)
            } else {
                Button("Stop", role: .destructive, action: stop)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(task.state == .cancelling)
            }
        }
        .padding(.vertical, 2)
    }
}
