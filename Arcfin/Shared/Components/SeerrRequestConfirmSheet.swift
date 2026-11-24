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
    @State private var alreadyRequested = false
    @State private var seasonsFailed = false

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
        isSubmitting || alreadyRequested || (isSeries && (
            overLimit || overQuota || unrequested.isEmpty ||
            (partialRequestsEnabled && selectedSeasons.isEmpty)
        ))
    }
    private var requestLabel: String {
        if alreadyRequested { return String(localized: "Already Requested") }
        guard isSeries else { return isSubmitting ? String(localized: "Sending…") : String(localized: "Confirm Request") }
        // No detail means the seasons aren't known yet, not that they're all requested.
        if detail == nil { return String(localized: "Select Seasons") }
        if unrequested.isEmpty { return String(localized: "Already Requested") }
        if !partialRequestsEnabled { return isSubmitting ? String(localized: "Sending…") : String(localized: "Request Series") }
        if selectedSeasons.isEmpty { return String(localized: "Select Seasons") }
        return isSubmitting ? String(localized: "Sending…") : String(localized: "Request \(selectedSeasons.count) Seasons")
    }

    var body: some View {
        Group {
            if PlatformMetrics.sheetsSideBySide { sideBySide } else { singleColumn }
        }
        .task {
            // A movie has no per-season rows to say so; the loaded requests and the item's own
            // status do. A series is covered by its season rows below.
            if !isSeries, seerrRepo.isRequested(item) { alreadyRequested = true }
            await loadDetail()
        }
    }

    private func loadDetail() async {
        isLoadingDetail = true
        seasonsFailed = false
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
            seasonsFailed = resolvedDetail == nil
        }
        isLoadingDetail = false
    }

    /// iPhone, iPad and Mac: one column, in a NavigationStack so Cancel can live in the
    /// toolbar's leading edge (sheets.md's platform convention).
    private var singleColumn: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    header
                    loadingIndicator
                    if let genres = detail?.genres, !genres.isEmpty { genreRow(genres) }
                    if isSeries { seasonSection }
                    overview
                    if let cast = detail?.cast, !cast.isEmpty {
                        castRow(cast)
                    } else {
                        Spacer().frame(height: DT.Spacing.sm)
                    }
                    requestFooter
                }
            }
            .navigationTitle("")
            .inlineNavigationTitle()
            .seerrRequestCancelToolbar { requestingItem = nil }
        }
    }

    /// Apple TV: the title on the left, what to request on the right, each scrolling on its
    /// own, with room around the rows so a focused one isn't cut at the edge.
    private var sideBySide: some View {
        HStack(alignment: .top, spacing: 48) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    loadingIndicator
                    if let genres = detail?.genres, !genres.isEmpty { genreRow(genres) }
                    overview
                    if let cast = detail?.cast, !cast.isEmpty { castRow(cast) }
                }
                .padding(.vertical, 24)
            }
            .scrollClipDisabled()
            .frame(maxWidth: .infinity)
            .loginFocusSection()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    if isSeries { seasonSection }
                    requestFooter
                }
                .padding(.vertical, 24)
            }
            .scrollClipDisabled()
            .frame(maxWidth: .infinity)
            .loginFocusSection()
        }
    }

    @ViewBuilder
    private var loadingIndicator: some View {
        if isLoadingDetail {
            ProgressView()
                .scaleEffect(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DT.Spacing.pagePad)
                .padding(.bottom, DT.Spacing.sm)
        }
    }

    @ViewBuilder
    private var overview: some View {
        let overviewText = detail?.overview ?? item.overview
        if let overviewText, !overviewText.isEmpty {
            Text(overviewText)
                .font(DT.Font.caption)
                .foregroundStyle(DT.Color.textSecondary)
                .lineSpacing(3)
                .lineLimit(PlatformMetrics.sheetsSideBySide ? 10 : 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DT.Spacing.pagePad)
                .padding(.bottom, DT.Spacing.md)
        }
    }

    /// The note, any error, and Request and Cancel.
    @ViewBuilder
    private var requestFooter: some View {
        Text("Send a request to your Seerr server. You'll be notified when it becomes available.")
            .font(DT.Font.caption)
            .foregroundStyle(DT.Color.textSecondary)
            .lineSpacing(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DT.Spacing.pagePad)
            .padding(.bottom, DT.Spacing.lg)

        if alreadyRequested {
            Text("This title has already been requested. You'll be notified when it becomes available.")
                .font(.system(.caption))
                .foregroundStyle(DT.Color.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DT.Spacing.pagePad)
                .padding(.bottom, DT.Spacing.sm)
        } else if let submitError {
            Text(submitError)
                .font(.system(.caption))
                .foregroundStyle(DT.Color.palette("F43F5E"))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DT.Spacing.pagePad)
                .padding(.bottom, DT.Spacing.sm)
        }

        submitButton
        SeerrRequestCancelButton { requestingItem = nil }
    }

    // MARK: - Header / genres / cast (unchanged visual language)

    private var header: some View {
        HStack(spacing: 14) {
            if let url = item.posterURL {
                CachedAsyncImage(url: url) { phase in
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
                    .font(.system(.body, design: .default, weight: .heavy))
                    .foregroundStyle(DT.Color.textPrimary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(item.mediaType == .tv ? "Series" : "Movie")
                        .font(.system(.caption2))
                        .foregroundStyle(DT.Color.textSecondary)
                    if let year = item.year {
                        Text("· \(year)")
                            .font(.system(.caption2))
                            .foregroundStyle(DT.Color.textSecondary)
                    }
                    if let runtime = detail?.runtimeMinutes {
                        Text("· \(runtime) min")
                            .font(.system(.caption2))
                            .foregroundStyle(DT.Color.textSecondary)
                    }
                }
                if let rating = detail?.voteAverage, rating > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill")
                            .font(.system(.caption2))
                            .foregroundStyle(DT.Color.palette("f59e0b"))
                        Text(rating.formatted(.number.precision(.fractionLength(1))))
                            .font(.system(.caption, design: .default, weight: .semibold))
                            .foregroundStyle(DT.Color.textPrimary)
                    }
                }
                if let tagline = detail?.tagline {
                    Text(tagline)
                        .font(.system(.caption2, design: .default, weight: .medium))
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
                        .font(.system(.caption2, design: .default, weight: .medium))
                        .foregroundStyle(DT.Color.textSecondary)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(DT.Color.textPrimary.opacity(0.06))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, DT.Spacing.pagePad)
        }
        .shelfScrollButtons()
        .padding(.bottom, DT.Spacing.sm)
    }

    private func castRow(_ cast: [SeerrCastMember]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(cast) { member in
                    VStack(spacing: 4) {
                        CachedAsyncImage(url: member.profileURL) { phase in
                            switch phase {
                            case .success(let img): img.resizable().scaledToFill()
                            default: Circle().fill(DT.Color.backgroundSecondary)
                            }
                        }
                        .frame(width: 48, height: 48)
                        .clipShape(Circle())
                        Text(member.name)
                            .font(.system(.caption2, design: .default, weight: .medium))
                            .foregroundStyle(DT.Color.textPrimary)
                            .lineLimit(1)
                    }
                    .frame(width: 56)
                }
            }
            .padding(.horizontal, DT.Spacing.pagePad)
        }
        .shelfScrollButtons()
        .padding(.bottom, DT.Spacing.lg)
    }

    // MARK: - Seasons

    private var seasonSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Seasons")
                    .font(.system(.footnote, design: .default, weight: .semibold))
                    .foregroundStyle(DT.Color.textPrimary)
                Spacer()
                if partialRequestsEnabled, !unrequested.isEmpty {
                    Button(selecting ? "Select All" : "Clear Selection") {
                        selectedSeasons = SeerrSeasonSelection.toggleAll(selectedSeasons, unrequested: unrequested, quota: quota)
                    }
                    .disabled(!canToggleAll)
                    .font(.system(.caption, design: .default, weight: .medium))
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
                    .font(.system(.caption2))
                    .foregroundStyle(DT.Color.textSecondary)
                    .padding(.horizontal, DT.Spacing.pagePad)
            }

            if seasonsFailed {
                HStack {
                    Text("Couldn't load the seasons.")
                        .font(.system(.caption2, design: .default, weight: .medium))
                        .foregroundStyle(DT.Color.palette("F43F5E"))
                    Spacer()
                    Button("Try Again") { Task { await loadDetail() } }
                        .font(.system(.caption, design: .default, weight: .medium))
                        .foregroundStyle(DT.Color.accent)
                }
                .padding(.horizontal, DT.Spacing.pagePad)
            } else if rows.isEmpty {
                EmptyView()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 {
                            Divider().background(DT.Color.textPrimary.opacity(0.06))
                        }
                        seasonRow(row)
                    }
                }
                // A background in the shape, not a clip: a focused row grows past the edge on
                // Apple TV, and clipping cut it off on both sides.
                .background(DT.Color.textPrimary.opacity(0.03), in: RoundedRectangle(cornerRadius: DT.Radius.md))
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
            HapticManager.selection()
            selectedSeasons = SeerrSeasonSelection.toggle(selectedSeasons, season: row.seasonNumber, unrequested: unrequested, quota: quota)
        } label: {
            HStack(spacing: 12) {
                seasonStatusCircle(row: row, chosen: chosen)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.label)
                        .font(.system(.footnote, design: .default, weight: .medium))
                        .foregroundStyle(DT.Color.textPrimary)
                    Text("\(row.episodeCount) episodes")
                        .font(.system(.caption2))
                        .foregroundStyle(DT.Color.textSecondary)
                }
                Spacer()
                if row.locked, let badge = row.badge {
                    Text(seasonBadgeLabel(badge))
                        .font(.system(.caption2, design: .default, weight: .semibold))
                        .foregroundStyle(DT.Color.palette(seasonBadgeColorHex(badge)))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .opacity(blocked ? 0.4 : 1)
            .contentShape(Rectangle())
        }
        .arcfinPlainButton(cornerRadius: DT.Radius.md)
        .disabled(!interactive)
        .accessibilityAddTraits(chosen && partialRequestsEnabled ? .isSelected : [])
    }

    private func seasonStatusCircle(row: SeerrSeasonRow, chosen: Bool) -> some View {
        let locked = row.locked
        let badgeColor = row.badge.map { DT.Color.palette(seasonBadgeColorHex($0)) }
        return ZStack {
            Circle()
                .fill(locked ? (badgeColor?.opacity(0.18) ?? DT.Color.textPrimary.opacity(0.08))
                              : (chosen ? DT.Color.accent : Color.clear))
                .overlay(Circle().stroke(locked ? Color.clear : DT.Color.textPrimary.opacity(0.3), lineWidth: locked ? 0 : 1.5))
            if locked {
                Image(systemName: seasonBadgeIcon(row.badge))
                    .font(.system(.caption2, weight: .bold))
                    .foregroundStyle(badgeColor ?? DT.Color.textSecondary)
            } else {
                // Kept as one persistent view (visibility via opacity, not insertion) so
                // SwiftUI sees the same node across a toggle and actually retriggers the
                // bounce — a conditionally-inserted Image has no prior frame to animate from.
                Image(systemName: "checkmark")
                    .font(.system(.caption2, weight: .bold))
                    .foregroundStyle(DT.Color.onAccent)
                    .opacity(chosen ? 1 : 0)
                    .symbolEffect(.bounce, value: chosen)
            }
        }
        .frame(width: 24, height: 24)
    }

    private func seasonBadgeLabel(_ badge: SeerrSeasonBadge) -> String {
        switch badge {
        case .notRequested:        String(localized: "Not Requested")
        case .pending:              String(localized: "Pending")
        case .requested:            String(localized: "Requested")
        case .partiallyAvailable:   String(localized: "Partial")
        case .available:            String(localized: "Available")
        }
    }

    private func seasonBadgeColorHex(_ badge: SeerrSeasonBadge) -> String {
        switch badge {
        case .notRequested:        "6B7280"
        case .pending:              "f59e0b"
        case .requested:            "FF6A4D"
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
            if overLimit { return String(localized: "Not enough season requests remaining for the whole series.") }
            if overQuota { return String(localized: "That's more seasons than you have requests remaining for.") }
            if remaining <= 0 { return String(localized: "No season requests remaining.") }
            if let days = quota?.days, days > 0 {
                return String(localized: "\(remaining) season requests remaining (resets every \(days) days)")
            }
            return String(localized: "\(remaining) season requests remaining")
        }()
        let isWarning = overLimit || overQuota || remaining <= 0
        return Text(text)
            .font(.system(.caption2, design: .default, weight: .medium))
            .foregroundStyle(isWarning ? DT.Color.palette("F43F5E") : DT.Color.textSecondary)
            .padding(.horizontal, DT.Spacing.pagePad)
            .contentTransition(.numericText())
            .animation(.default, value: remaining)
    }

    private var autoApproveBanner: some View {
        Text("This request will be approved automatically.")
            .font(.system(.caption2, design: .default, weight: .medium))
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
                    if try await seerrRepo.createRequest(mediaType: captured.mediaType, mediaId: captured.id, seasons: seasons) {
                        isSubmitting = false
                        submitError = String(localized: "Seerr can't be reached right now. Your server will send this request as soon as it can.")
                    } else {
                        HapticManager.success()
                        requestingItem = nil
                    }
                } catch is SeerrRepository.AlreadyRequested {
                    isSubmitting = false
                    alreadyRequested = true
                } catch SeerrError.requestFailed(status: 403, body: _) {
                    HapticManager.error()
                    isSubmitting = false
                    submitError = String(localized: "Your Seerr account can't request this. Ask your Seerr admin for request permission, or check your request limit.")
                } catch {
                    HapticManager.error()
                    isSubmitting = false
                    submitError = String(localized: "Couldn't send request: \(error.localizedDescription)")
                }
            }
        } label: {
            HStack(spacing: 8) {
                if isSubmitting { ProgressView().tint(DT.Color.onAccent) }
                Text(requestLabel)
            }
                .font(.system(.subheadline, design: .default, weight: .bold))
                .foregroundStyle(DT.Color.onAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(LinearGradient(
                    colors: [DT.Color.accentDeep, DT.Color.accent],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                .clipShape(RoundedRectangle(cornerRadius: DT.Radius.lg))
                .shadow(color: DT.Color.accent.opacity(0.35), radius: 16)
                .opacity(requestDisabled ? 0.5 : 1)
        }
        .arcfinPlainButton(cornerRadius: DT.Radius.lg, pressable: true)
        .disabled(requestDisabled)
        .padding(.horizontal, DT.Spacing.pagePad)
    }
}
