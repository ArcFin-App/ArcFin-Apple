// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import SeerrAPI

extension SeerrIssueType {
    var label: String {
        switch self {
        case .video: String(localized: "Video")
        case .audio: String(localized: "Audio")
        case .subtitles: String(localized: "Subtitles")
        case .other: String(localized: "Other")
        }
    }

    var systemImage: String {
        switch self {
        case .video: "film"
        case .audio: "speaker.wave.2"
        case .subtitles: "captions.bubble"
        case .other: "exclamationmark.bubble"
        }
    }
}

extension SeerrIssue {
    /// "Season 2 · Episode 5", "Season 2", or nil for the whole title.
    var whereText: String? {
        switch (problemSeason, problemEpisode) {
        case let (season?, episode?): String(localized: "Season \(season) · Episode \(episode)")
        case let (season?, nil): String(localized: "Season \(season)")
        default: nil
        }
    }

    var statusLabel: String { isOpen ? String(localized: "Open") : String(localized: "Resolved") }

    var statusColor: Color { DT.Color.palette(isOpen ? "f59e0b" : "10b981") }
}

/// An issue in a list: the title's poster and name, what kind of problem and where, its status
/// and who reported it. The title is looked up from Seerr, as issue lists don't carry it.
struct SeerrIssueRow: View {
    let issue: SeerrIssue
    var showsTitle = true

    @Environment(SeerrRepository.self) private var seerrRepo
    @State private var title: SeerrItem?

    var body: some View {
        HStack(spacing: 10) {
            if showsTitle {
                poster
            } else {
                Image(systemName: issue.type.systemImage)
                    .foregroundStyle(issue.statusColor)
                    .frame(width: 32)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(showsTitle ? title?.title ?? String(localized: "Issue \(issue.id)") : issue.type.label)
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(DT.Color.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text([showsTitle ? issue.type.label : nil, issue.whereText].compactMap { $0 }.joined(separator: " · "))
                        .font(DT.Font.caption2)
                        .foregroundStyle(DT.Color.textSecondary)
                    StatusPill(label: issue.statusLabel, color: issue.statusColor)
                }
                if let name = issue.createdBy?.name, !name.isEmpty {
                    Label("Reported by \(name)", systemImage: "person")
                        .font(DT.Font.caption2)
                        .foregroundStyle(DT.Color.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(DT.Font.caption2)
                .foregroundStyle(DT.Color.textSecondary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 12).padding(.vertical, 11)
        .background(DT.Color.textPrimary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(DT.Color.textPrimary.opacity(0.06), lineWidth: 1))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .task(id: issue.id) {
            guard showsTitle, title == nil else { return }
            title = await seerrRepo.title(of: issue)
        }
    }

    private var poster: some View {
        Group {
            if let url = title?.posterURL {
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    default: fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: 32, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var fallback: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(DT.Color.textPrimary.opacity(0.06))
            .overlay(Image(systemName: issue.type.systemImage).foregroundStyle(DT.Color.textSecondary))
    }
}
