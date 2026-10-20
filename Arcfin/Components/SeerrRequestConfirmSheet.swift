// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import SeerrAPI

struct SeerrRequestConfirmSheet: View {
    @Environment(SeerrRepository.self) private var seerrRepo

    let item: SeerrItem
    @Binding var requestingItem: SeerrItem?

    @State private var detail: SeerrMediaDetail?
    @State private var isLoadingDetail = true
    @State private var quota: SeerrSeasonQuota?
    @State private var partialRequestsEnabled = true
    @State private var selectedSeasons: Set<Int> = []
    @State private var isSubmitting = false
    @State private var submitError: String?

    private var isSeries: Bool { item.mediaType == .tv }
    private var rows: [SeerrSeasonRow] { detail?.seasonRows ?? [] }
    private var unrequested: [Int] { SeerrSeasonSelection.unrequested(rows) }

    // Mirrors Seerr's own request modal: a whole-series-only server needs quota for every
    // season left (overLimit); a partial-request server only needs it for what's switched on
    // (overQuota), which can stop fitting once the quota changes under the user mid-sheet.
    private var limited: Bool { (quota?.limit ?? 0) > 0 }
    private var overLimit: Bool {
        limited && !partialRequestsEnabled && unrequested.count > (quota?.remaining ?? 0)
    }
    private var overQuota: Bool {
        partialRequestsEnabled && !SeerrSeasonSelection.withinQuota(selected: selectedSeasons, quota: quota)
    }
    private var remaining: Int {
        (overLimit || overQuota) ? 0 : (quota?.remaining ?? 0) - selectedSeasons.count
    }
    private var selecting: Bool { SeerrSeasonSelection.selectsAll(selectedSeasons, unrequested: unrequested) }
    private var canToggleAll: Bool {
        !selecting || SeerrSeasonSelection.roomForAll(unrequested: unrequested, quota: quota)
    }
    private var roomForOneMore: Bool { SeerrSeasonSelection.roomForOneMore(selected: selectedSeasons, quota: quota) }
    private var approvedAutomatically: Bool {
        isSeries && !unrequested.isEmpty && !overLimit && seerrRepo.autoApprovesTVRequests()
    }
    // A whole-series-only server always asks for every season left, regardless of the
    // (non-interactive, in that case) selection state.
    private var seasonsToRequest: [Int] {
        (partialRequestsEnabled ? Array(selectedSeasons) : unrequested).sorted()
    }
    private var requestDisabled: Bool {
        isSubmitting || (isSeries && (
            overLimit || overQuota || unrequested.isEmpty ||
            (partialRequestsEnabled && selectedSeasons.isEmpty)
        ))
    }
    private var requestLabel: String {
        guard isSeries else { return isSubmitting ? "Sending…" : "Confirm Request" }
        if unrequested.isEmpty { return "Already Requested" }
        if !partialRequestsEnabled { return isSubmitting ? "Sending…" : "Request Series" }
        if selectedSeasons.isEmpty { return "Select Seasons" }
        return isSubmitting ? "Sending…" : "Request \(selectedSeasons.count) Season\(selectedSeasons.count == 1 ? "" : "s")"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                header

                if isLoadingDetail {
                    ProgressView()
                        .scaleEffect(0.8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, DT.Spacing.pagePad)
                        .padding(.bottom, DT.Spacing.sm)
                }

                if let genres = detail?.genres, !genres.isEmpty {
                    genreRow(genres)
                }

                if isSeries {
                    seasonSection
                }

                let overviewText = detail?.overview ?? item.overview
                if let overviewText, !overviewText.isEmpty {
                    Text(overviewText)
                        .font(DT.Font.caption)
                        .foregroundStyle(DT.Color.textSecondary)
                        .lineSpacing(3)
                        .lineLimit(5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, DT.Spacing.pagePad)
                        .padding(.bottom, DT.Spacing.md)
                }

                if let cast = detail?.cast, !cast.isEmpty {
                    castRow(cast)
                } else {
                    Spacer().frame(height: DT.Spacing.sm)
                }

                Text("Send a request to your Seerr server. You'll be notified when it becomes available.")
                    .font(DT.Font.caption)
                    .foregroundStyle(DT.Color.textSecondary)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DT.Spacing.pagePad)
                    .padding(.bottom, DT.Spacing.lg)

                if let submitError {
                    Text(submitError)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: "EF4444"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, DT.Spacing.pagePad)
                        .padding(.bottom, DT.Spacing.sm)
                }

                submitButton
                cancelButton
            }
        }
        .task {
            async let fetchedDetail = seerrRepo.mediaDetail(mediaType: item.mediaType, tmdbId: item.id)
            async let fetchedSettings = seerrRepo.ensurePublicSettings()
            let (resolvedDetail, resolvedSettings) = await (fetchedDetail, fetchedSettings)
            detail = resolvedDetail
            partialRequestsEnabled = resolvedSettings?.partialRequestsEnabled ?? true
            // The sheet opens with nothing switched on, same as Seerr's own modal — not every
            // unrequested season preselected, so a quota-limited user doesn't accidentally
            // submit more than they meant to.
            if isSeries {
                quota = await seerrRepo.seasonQuota()
            }
            isLoadingDetail = false
        }
    }

    // MARK: - Header / genres / cast (unchanged visual language)

    private var header: some View {
        HStack(spacing: 14) {
            if let url = item.posterURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: RoundedRectangle(cornerRadius: 8).fill(DT.Color.backgroundSecondary)
                    }
                }
                .frame(width: 56, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(DT.Color.textPrimary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(item.mediaType == .tv ? "Series" : "Movie")
                        .font(.system(size: 11))
                        .foregroundStyle(DT.Color.textSecondary)
                    if let year = item.year {
                        Text("· \(year)")
                            .font(.system(size: 11))
                            .foregroundStyle(DT.Color.textSecondary)
                    }
                    if let runtime = detail?.runtimeMinutes {
                        Text("· \(runtime) min")
                            .font(.system(size: 11))
                            .foregroundStyle(DT.Color.textSecondary)
                    }
                }
                if let rating = detail?.voteAverage, rating > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color(hex: "f59e0b"))
                        Text(String(format: "%.1f", rating))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(DT.Color.textPrimary)
                    }
                }
                if let tagline = detail?.tagline {
                    Text(tagline)
                        .font(.system(size: 11, weight: .medium))
                        .italic()
                        .foregroundStyle(DT.Color.textSecondary)
                        .lineLimit(2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.top, DT.Spacing.lg)
        .padding(.bottom, DT.Spacing.md)
    }

    private func genreRow(_ genres: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(genres, id: \.self) { genre in
                    Text(genre)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DT.Color.textSecondary)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, DT.Spacing.pagePad)
        }
        .padding(.bottom, DT.Spacing.sm)
    }

    private func castRow(_ cast: [SeerrCastMember]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(cast) { member in
                    VStack(spacing: 4) {
                        AsyncImage(url: member.profileURL) { phase in
                            switch phase {
                            case .success(let img): img.resizable().scaledToFill()
                            default: Circle().fill(DT.Color.backgroundSecondary)
                            }
                        }
                        .frame(width: 48, height: 48)
                        .clipShape(Circle())
                        Text(member.name)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(DT.Color.textPrimary)
                            .lineLimit(1)
                    }
                    .frame(width: 56)
                }
            }
            .padding(.horizontal, DT.Spacing.pagePad)
        }
        .padding(.bottom, DT.Spacing.lg)
    }

    // MARK: - Seasons

    private var seasonSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Seasons")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DT.Color.textPrimary)
                Spacer()
                if partialRequestsEnabled, !unrequested.isEmpty {
                    Button(selecting ? "Select All" : "Clear Selection") {
                        selectedSeasons = SeerrSeasonSelection.toggleAll(selectedSeasons, unrequested: unrequested, quota: quota)
                    }
                    .disabled(!canToggleAll)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(canToggleAll ? DT.Color.accent : DT.Color.textSecondary)
                }
            }
            .padding(.horizontal, DT.Spacing.pagePad)

            if limited {
                quotaBanner
            }

            if approvedAutomatically {
                autoApproveBanner
            }

            if !partialRequestsEnabled {
                Text("This server only requests whole series at a time.")
                    .font(.system(size: 11))
                    .foregroundStyle(DT.Color.textSecondary)
                    .padding(.horizontal, DT.Spacing.pagePad)
            }

            if rows.isEmpty {
                // Detail fetch failed or returned no seasons — don't strand the button
                // disabled with no picker visible to explain why (same fallback as before
                // this view had per-season status at all).
                EmptyView()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 {
                            Divider().background(Color.white.opacity(0.06))
                        }
                        seasonRow(row)
                    }
                }
                .background(Color.white.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: DT.Radius.md))
                .padding(.horizontal, DT.Spacing.pagePad)
            }
        }
        .padding(.bottom, DT.Spacing.md)
    }

    private func seasonRow(_ row: SeerrSeasonRow) -> some View {
        let chosen = !row.locked && (partialRequestsEnabled ? selectedSeasons.contains(row.seasonNumber) : true)
        let blocked = !row.locked && !chosen && !roomForOneMore
        let interactive = partialRequestsEnabled && !row.locked && !blocked

        return Button {
            selectedSeasons = SeerrSeasonSelection.toggle(selectedSeasons, season: row.seasonNumber, unrequested: unrequested, quota: quota)
        } label: {
            HStack(spacing: 12) {
                seasonStatusCircle(row: row, chosen: chosen)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.label)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(DT.Color.textPrimary)
                    Text("\(row.episodeCount) episode\(row.episodeCount == 1 ? "" : "s")")
                        .font(.system(size: 11))
                        .foregroundStyle(DT.Color.textSecondary)
                }
                Spacer()
                if row.locked, let badge = row.badge {
                    Text(seasonBadgeLabel(badge))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(hex: seasonBadgeColorHex(badge)))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .opacity(blocked ? 0.4 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!interactive)
    }

    private func seasonStatusCircle(row: SeerrSeasonRow, chosen: Bool) -> some View {
        let locked = row.locked
        let badgeColor = row.badge.map { Color(hex: seasonBadgeColorHex($0)) }
        ZStack {
            Circle()
                .fill(locked ? (badgeColor?.opacity(0.18) ?? Color.white.opacity(0.08))
                              : (chosen ? DT.Color.accent : Color.clear))
                .overlay(Circle().stroke(locked ? Color.clear : Color.white.opacity(0.3), lineWidth: locked ? 0 : 1.5))
            if locked {
                Image(systemName: seasonBadgeIcon(row.badge))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(badgeColor ?? DT.Color.textSecondary)
            } else if chosen {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 24, height: 24)
    }

    private func seasonBadgeLabel(_ badge: SeerrSeasonBadge) -> String {
        switch badge {
        case .notRequested:        "Not Requested"
        case .pending:              "Pending"
        case .requested:            "Requested"
        case .partiallyAvailable:   "Partial"
        case .available:            "Available"
        }
    }

    private func seasonBadgeColorHex(_ badge: SeerrSeasonBadge) -> String {
        switch badge {
        case .notRequested:        "6B7280"
        case .pending:              "f59e0b"
        case .requested:            "06B6D4"
        case .partiallyAvailable:   "10b981"
        case .available:            "10b981"
        }
    }

    private func seasonBadgeIcon(_ badge: SeerrSeasonBadge?) -> String {
        switch badge {
        case .pending:              "clock.fill"
        case .requested:            "arrow.triangle.2.circlepath"
        case .partiallyAvailable:   "checkmark"
        case .available:            "checkmark"
        case .notRequested, nil:    "circle"
        }
    }

    private var quotaBanner: some View {
        let text: String = {
            if overLimit { return "Not enough season requests remaining for the whole series." }
            if overQuota { return "That's more seasons than you have requests remaining for." }
            if remaining <= 0 { return "No season requests remaining." }
            return "\(remaining) season request\(remaining == 1 ? "" : "s") remaining"
                + (quota?.days.map { $0 > 0 ? " (resets every \($0) day\($0 == 1 ? "" : "s"))" : "" } ?? "")
        }()
        let isWarning = overLimit || overQuota || remaining <= 0
        return Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(isWarning ? Color(hex: "EF4444") : DT.Color.textSecondary)
            .padding(.horizontal, DT.Spacing.pagePad)
    }

    private var autoApproveBanner: some View {
        Text("This request will be approved automatically.")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(DT.Color.accent)
            .padding(.horizontal, DT.Spacing.pagePad)
    }

    // MARK: - Actions

    private var submitButton: some View {
        Button {
            HapticManager.impact(.medium)
            submitError = nil
            isSubmitting = true
            let captured = item
            let seasons = isSeries ? seasonsToRequest : []
            Task {
                do {
                    try await seerrRepo.createRequest(mediaType: captured.mediaType, mediaId: captured.id, seasons: seasons)
                    requestingItem = nil
                } catch {
                    isSubmitting = false
                    submitError = "Couldn't send request: \(error.localizedDescription)"
                }
            }
        } label: {
            HStack(spacing: 8) {
                if isSubmitting { ProgressView().tint(.white) }
                Text(requestLabel)
            }
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(LinearGradient(
                    colors: [DT.Color.accentDeep, DT.Color.accent],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                .clipShape(RoundedRectangle(cornerRadius: DT.Radius.lg))
                .shadow(color: DT.Color.accent.opacity(0.35), radius: 16)
                .opacity(requestDisabled ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .disabled(requestDisabled)
        .padding(.horizontal, DT.Spacing.pagePad)
    }

    private var cancelButton: some View {
        Button { requestingItem = nil } label: {
            Text("Cancel")
                .font(.system(size: 13))
                .foregroundStyle(DT.Color.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.bottom, DT.Spacing.lg)
    }
}
