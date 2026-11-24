// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

/// The server admin's announcements and maintenance windows, as last fetched for a server.
/// Kept on this device, so a maintenance window still shows while the server is down.
struct CachedNotices: Codable, Equatable {
    var announcements: [Announcement]
    var maintenance: [MaintenanceWindow]

    private static func key(_ server: URL) -> String { "arcfin.serverNotices.\(AdminLock.serverKey(server))" }

    static func load(server: URL) -> CachedNotices? {
        UserDefaults.standard.data(forKey: key(server)).flatMap { try? JSONDecoder().decode(CachedNotices.self, from: $0) }
    }

    func save(server: URL) {
        UserDefaults.standard.set(try? JSONEncoder().encode(self), forKey: Self.key(server))
    }

    static func forget(server: URL) {
        UserDefaults.standard.removeObject(forKey: key(server))
    }

    func activeAnnouncements(at now: Date, dismissed: Set<String>) -> [Announcement] {
        announcements.filter { ($0.starts ?? .distantPast) <= now && now < ($0.ends ?? .distantFuture) && !dismissed.contains($0.id) }
    }

    /// A window starting within the next 24 hours.
    func upcomingMaintenance(at now: Date) -> MaintenanceWindow? {
        maintenance.filter { $0.starts > now && $0.starts.timeIntervalSince(now) <= 24 * 3600 }.min { $0.starts < $1.starts }
    }

    func currentMaintenance(at now: Date) -> MaintenanceWindow? {
        maintenance.first { $0.starts <= now && now < $0.ends }
    }
}

extension MaintenanceWindow {
    /// "Server maintenance Sat 02:00–04:00. <message>"
    var summary: String {
        let day = starts.formatted(.dateTime.weekday(.abbreviated))
        let from = starts.formatted(date: .omitted, time: .shortened)
        let to = ends.formatted(date: .omitted, time: .shortened)
        let text = String(localized: "Server maintenance \(day) \(from)–\(to).")
        return message.isEmpty ? text : text + " " + message
    }
}

/// Announcements and upcoming maintenance at the top of Home, each dismissible.
struct ServerNoticeBanners: View {
    private static let dismissedKey = "arcfin.dismissedAnnouncements"

    @AppStorage(dismissedKey) private var dismissedRaw = ""

    private var dismissed: Set<String> { Set(dismissedRaw.split(separator: ",").map(String.init)) }

    /// Moved on once a minute by `.task`, so a window or an announcement comes and goes on time.
    /// Not a TimelineView: Home redraws constantly while its hero tracks the scroll position, and
    /// a schedule made from "now" in each redraw restarted itself every time, which never settled.
    @State private var now = Date.now

    var body: some View {
        // Nothing at all in Home's list when there's nothing to show.
        if let notices = ServerCompanion.shared.currentNotices(), !notices.announcements.isEmpty || !notices.maintenance.isEmpty {
            banners(notices)
                .task {
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(60))
                        now = .now
                    }
                }
        }
    }

    @ViewBuilder
    private func banners(_ notices: CachedNotices) -> some View {
        let announcements = notices.activeAnnouncements(at: now, dismissed: dismissed)
        let maintenance = notices.upcomingMaintenance(at: now).flatMap { dismissed.contains($0.id) ? nil : $0 }
        if !announcements.isEmpty || maintenance != nil {
            VStack(spacing: DT.Spacing.sm) {
                if let maintenance {
                    NoticeBanner(title: String(localized: "Maintenance Coming Up"), message: maintenance.summary,
                                 isWarning: true, systemImage: "wrench.and.screwdriver") { dismiss(maintenance.id) }
                }
                ForEach(announcements) { announcement in
                    NoticeBanner(title: announcement.title, message: announcement.message,
                                 isWarning: announcement.style == "warning",
                                 systemImage: announcement.style == "warning" ? "exclamationmark.triangle" : "megaphone") {
                        dismiss(announcement.id)
                    }
                }
            }
            .padding(.horizontal, DT.Spacing.pagePad)
            .padding(.bottom, DT.Spacing.md)
        }
    }

    private func dismiss(_ id: String) {
        // Only the latest few are kept: old announcements don't come back.
        dismissedRaw = (Array(dismissed) + [id]).suffix(100).joined(separator: ",")
    }
}

private struct NoticeBanner: View {
    let title: String
    let message: String
    let isWarning: Bool
    let systemImage: String
    var dismiss: () -> Void

    private var tint: Color { isWarning ? DT.Color.palette("f59e0b") : DT.Color.palette("60A5FA") }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .contentFont(.title3)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                if !title.isEmpty {
                    Text(title)
                        .contentFont(.footnote, design: .default, weight: .semibold)
                        .foregroundStyle(DT.Color.textPrimary)
                }
                if !message.isEmpty {
                    Text(message)
                        .contentFont(.caption)
                        .foregroundStyle(DT.Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .contentFont(.caption, design: .default, weight: .semibold)
                    .foregroundStyle(DT.Color.textSecondary)
                    .padding(4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(12)
        .background(tint.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: DT.Radius.lg).stroke(tint.opacity(0.25), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// In place of the can't-reach screen while the server is down for planned maintenance.
struct MaintenanceNotice: View {
    let window: MaintenanceWindow

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "wrench.and.screwdriver")
                .scaledFont(size: 44, weight: .medium)
                .foregroundStyle(DT.Color.palette("f59e0b"))
                .accessibilityHidden(true)
            Text("Down for Maintenance · Back at \(window.ends.formatted(date: .omitted, time: .shortened))")
                .font(.system(.title2, design: .default, weight: .bold))
                .foregroundStyle(DT.Color.textPrimary)
                .multilineTextAlignment(.center)
            Text(window.message.isEmpty ? String(localized: "Your server's admin planned this. Arcfin tries again when it's over.") : window.message)
                .font(.system(.footnote))
                .foregroundStyle(DT.Color.textSecondary)
                .multilineTextAlignment(.center)
        }
    }
}
