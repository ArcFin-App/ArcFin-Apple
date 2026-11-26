// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import SeerrAPI

struct SeerrRequestDetailView: View {
    let request: SeerrRequestItem

    @Environment(SeerrRepository.self) private var seerrRepo
    @Environment(\.dismiss) private var dismiss

    @State private var isCancelling = false
    @State private var errorMessage: String?
    @State private var showCancelConfirm = false
    @State private var detail: SeerrMediaDetail?
    @State private var isLoadingDetail = false
    @State private var review = SeerrRequestReview()

    /// The list's copy, which approving or declining brings up to date.
    private var current: SeerrRequestItem {
        seerrRepo.requests.first { $0.id == request.id } ?? request
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                heroSection
                SeerrRequestReviewButtons(request: current, review: review)
                    .padding(.horizontal, DT.Spacing.pagePad)
                    .padding(.bottom, DT.Spacing.sm)
                if seerrRepo.canRemove(current) {
                    removeRequestButton
                }
                if let key = detail?.trailerYouTubeKey {
                    SeerrTrailerButton(videoID: key, title: request.mediaTitle)
                }

                VStack(alignment: .leading, spacing: DT.Spacing.md) {
                    if let genres = detail?.genres, !genres.isEmpty {
                        Text(genres.joined(separator: " · "))
                            .font(.system(.caption))
                            .foregroundStyle(DT.Color.textSecondary)
                    }

                    statusRow

                    if isLoadingDetail {
                        ProgressView().frame(maxWidth: .infinity, alignment: .center)
                    }

                    if let tagline = detail?.tagline, !tagline.isEmpty {
                        Text(tagline)
                            .font(.system(.caption, design: .default, weight: .medium))
                            .italic()
                            .foregroundStyle(DT.Color.accent)
                    }

                    if let overview = detail?.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.system(.footnote))
                            .foregroundStyle(DT.Color.textPrimary.opacity(0.85))
                            .lineSpacing(3)
                    }

                    if let seasons = detail?.seasons, !seasons.isEmpty {
                        seasonsRow(seasons)
                    }

                    if let cast = detail?.cast, !cast.isEmpty {
                        castRow(cast)
                    }

                    if let error = errorMessage {
                        Text(error)
                            .font(.system(.caption))
                            .foregroundStyle(DT.Color.palette("F43F5E"))
                    }
                }
                .padding(.horizontal, DT.Spacing.pagePad)
                .padding(.bottom, DT.Spacing.md)

                Spacer().frame(height: DT.Size.tabBarHeight + 24)
            }
        }
        .screenBackground()
        .ignoresSafeArea(edges: .top)
        .navigationTitle("")
        .transparentInlineNavigationBar()
        .seerrRequestReview(review)
        .alert(
            "Remove this request?",
            isPresented: $showCancelConfirm
        ) {
            Button("Remove Request", role: .destructive) { cancel() }
            Button("Cancel", role: .cancel) {}
        }
        .task {
            guard let tmdbId = request.tmdbId else { return }
            isLoadingDetail = true
            detail = await seerrRepo.mediaDetail(mediaType: request.mediaType, tmdbId: tmdbId)
            isLoadingDetail = false
        }
    }

    private func seasonsRow(_ seasons: [SeerrSeasonInfo]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Seasons")
                .font(.system(.caption, design: .default, weight: .semibold))
                .foregroundStyle(DT.Color.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(seasons) { season in
                        VStack(spacing: 2) {
                            Text(season.label)
                                .font(.system(.caption2, design: .default, weight: .semibold))
                                .foregroundStyle(DT.Color.textPrimary)
                            if let count = season.episodeCount {
                                Text("\(count) episodes")
                                    .font(.system(.caption2))
                                    .foregroundStyle(DT.Color.textSecondary)
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(DT.Color.textPrimary.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.md))
                    }
                }
            }
            .shelfScrollButtons()
        }
    }

    private func castRow(_ cast: [SeerrCastMember]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            DetailSectionTitle(title: "Cast")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(cast.prefix(20)) { member in
                        CastPersonCard(imageURL: member.profileURL, name: member.name, role: member.character) {
                            DetailPersonPlaceholder()
                        }
                    }
                }
            }
            .shelfScrollButtons()
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        ShowcaseHero(urls: [request.backdropURL ?? request.posterURL].compactMap { $0 }, landscapeHeight: 340) {
            ShowcaseTitle(logoURL: nil, name: request.mediaTitle, nameStyle: .title)
            metaRow
        }
        .padding(.bottom, DT.Spacing.md)
    }

    // MARK: - Actions (positioned like MediaDetailView's playButton/trailerButton — see
    // SeerrItemDetailView's actionButtons for the same pattern applied to Request)

    private var removeRequestButton: some View {
        Button(role: .destructive) {
            showCancelConfirm = true
        } label: {
            HStack {
                if isCancelling {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "trash")
                }
                Text("Remove Request")
            }
            .font(.system(.footnote, design: .default, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(DT.Color.palette("F43F5E").opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.lg))
        }
        .buttonStyle(.plain)
        .disabled(isCancelling)
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.bottom, DT.Spacing.md)
    }

    // MARK: - Details

    private var metaRow: some View {
        HStack(spacing: 8) {
            Text(request.mediaType == .tv ? "Series" : "Movie")
                .font(.system(.caption2, design: .default, weight: .semibold))
                .foregroundStyle(DT.Color.textSecondary)
            Text("·").accessibilityHidden(true)
                .foregroundStyle(DT.Color.textPrimary.opacity(0.2))
            Text(request.requestedAt, style: .date)
                .font(.system(.caption2))
                .foregroundStyle(DT.Color.textSecondary)
            if let runtime = detail?.runtimeMinutes {
                Text("·").accessibilityHidden(true)
                    .foregroundStyle(DT.Color.textPrimary.opacity(0.2))
                Text("\(runtime) min")
                    .font(.system(.caption2))
                    .foregroundStyle(DT.Color.textSecondary)
            }
            if let rating = detail?.voteAverage, rating > 0 {
                Text("·").accessibilityHidden(true)
                    .foregroundStyle(DT.Color.textPrimary.opacity(0.2))
                HStack(spacing: 2) {
                    Image(systemName: "star.fill").font(.system(.caption2))
                    Text(rating.formatted(.number.precision(.fractionLength(1))))
                }
                .font(.system(.caption2))
                .foregroundStyle(DT.Color.palette("f59e0b"))
            }
        }
        // Lets HStack compress/truncate these Text children when every optional
        // field is present at once, instead of overflowing past the screen edge —
        // same fix as MediaDetailView.metaRow.
        .lineLimit(1)
    }

    private var statusRow: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Request Status")
                    .font(.system(.footnote, design: .default, weight: .semibold))
                    .foregroundStyle(DT.Color.textPrimary)
                Spacer()
                requestStatusPill
            }
            if let name = seerrRepo.requesterName(of: current) {
                HStack {
                    Text("Requested By")
                        .font(.system(.footnote, design: .default, weight: .semibold))
                        .foregroundStyle(DT.Color.textPrimary)
                    Spacer()
                    Text(name)
                        .font(.system(.footnote))
                        .foregroundStyle(DT.Color.textSecondary)
                }
            }
            if let mediaStatus = current.mediaStatus {
                HStack {
                    Text("Media Status")
                        .font(.system(.footnote, design: .default, weight: .semibold))
                        .foregroundStyle(DT.Color.textPrimary)
                    Spacer()
                    mediaStatusPill(mediaStatus)
                }
            }
        }
        .padding(12)
        .background(DT.Color.textPrimary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.md))
    }

    private var requestStatusPill: some View {
        let (label, hex): (String, String) = switch current.status {
        case .approved:  (String(localized: "Approved"), "10b981")
        case .declined:  (String(localized: "Declined"), "F43F5E")
        case .failed:  (String(localized: "Failed"), "F43F5E")
        case .completed: (String(localized: "Completed"), "10b981")
        case .pending:   (String(localized: "Pending"), "f59e0b")
        }
        return statusPillView(label: label, hex: hex)
    }

    private func mediaStatusPill(_ status: SeerrAvailabilityStatus) -> some View {
        statusPillView(label: status.localizedLabel, hex: status.colorHex)
    }

    private func statusPillView(label: String, hex: String) -> some View {
        Text(label)
            .font(.system(.caption2, design: .default, weight: .bold))
            .foregroundStyle(DT.Color.palette(hex))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(DT.Color.palette(hex).opacity(0.15))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(DT.Color.palette(hex).opacity(0.3), lineWidth: 1))
    }

    private func cancel() {
        isCancelling = true
        errorMessage = nil
        Task {
            do {
                try await seerrRepo.cancelRequest(id: request.id)
                dismiss()
            } catch {
                errorMessage = String(localized: "Seerr didn't remove “\(request.mediaTitle)”. Check your connection and try again.")
                isCancelling = false
            }
        }
    }
}
