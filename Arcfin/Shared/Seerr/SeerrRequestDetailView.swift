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

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                heroSection
                titleBlock
                removeRequestButton
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
                            .foregroundStyle(DT.Color.palette("EF4444"))
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
        .confirmationDialog(
            "Remove this request?",
            isPresented: $showCancelConfirm,
            titleVisibility: .visible
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
        VStack(alignment: .leading, spacing: 6) {
            Text("Cast")
                .font(.system(.caption, design: .default, weight: .semibold))
                .foregroundStyle(DT.Color.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(cast.prefix(12)) { member in
                        VStack(spacing: 4) {
                            CachedAsyncImage(url: member.profileURL) { phase in
                                switch phase {
                                case .success(let img): img.resizable().scaledToFill()
                                default: DT.Color.backgroundSecondary
                                }
                            }
                            .frame(width: 56, height: 56)
                            .clipShape(Circle())

                            Text(member.name)
                                .font(.system(.caption2, design: .default, weight: .semibold))
                                .foregroundStyle(DT.Color.textPrimary)
                                .lineLimit(1)
                            if let character = member.character {
                                Text(character)
                                    .font(.system(.caption2))
                                    .foregroundStyle(DT.Color.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                        .frame(width: 64)
                    }
                }
            }
            .shelfScrollButtons()
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        ZStack(alignment: .bottom) {
            if let url = request.backdropURL ?? request.posterURL {
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    default: fallbackHero
                    }
                }
            } else { fallbackHero }

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: DT.Color.backgroundPrimary.opacity(0.5), location: 0.6),
                    .init(color: DT.Color.backgroundPrimary, location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
        }
        .frame(height: 260)
        .containerRelativeFrame(.horizontal)
        .clipped()
    }

    private var fallbackHero: some View {
        LinearGradient(
            colors: [DT.Color.accentDeep, DT.Color.backgroundPrimary],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
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
            .background(DT.Color.palette("EF4444").opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.lg))
        }
        .disabled(isCancelling)
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.bottom, DT.Spacing.md)
    }

    // MARK: - Title block

    private var titleBlock: some View {
        HStack(alignment: .top, spacing: 14) {
            if let url = request.posterURL {
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: RoundedRectangle(cornerRadius: 10).fill(DT.Color.backgroundSecondary)
                    }
                }
                .frame(width: 90, height: 132)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(DT.Color.textPrimary.opacity(0.1), lineWidth: 1))
                .shadow(color: .black.opacity(0.6), radius: 12, y: 4)
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(DT.Color.backgroundSecondary)
                    .frame(width: 90, height: 132)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(request.mediaTitle)
                    .font(.system(.title3, design: .default, weight: .heavy))
                    .foregroundStyle(DT.Color.textPrimary)
                    .tracking(-0.5)
                    .lineLimit(3)

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
                            Text(String(format: "%.1f", rating))
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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.top, -50)
        .padding(.bottom, DT.Spacing.md)
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
            if let mediaStatus = request.mediaStatus {
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
        let (label, hex): (String, String) = switch request.status {
        case .approved:  ("Approved", "10b981")
        case .declined:  ("Declined", "EF4444")
        case .pending:   ("Pending", "f59e0b")
        }
        return statusPillView(label: label, hex: hex)
    }

    private func mediaStatusPill(_ status: SeerrAvailabilityStatus) -> some View {
        statusPillView(label: status.label, hex: status.colorHex)
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
                errorMessage = "Couldn't remove request: \(error.localizedDescription)"
                isCancelling = false
            }
        }
    }
}
