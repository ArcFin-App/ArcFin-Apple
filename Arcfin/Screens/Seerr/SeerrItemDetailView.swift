// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import SeerrAPI

/// Full detail for a Discover item — tapping a poster used to do nothing at all (only the
/// small in-card Request button had any action). This is that missing destination: overview,
/// cast, seasons, availability, and Request/Watchlist actions, same data source
/// (SeerrRepository.mediaDetail) SeerrRequestDetailView already uses for an existing request.
struct SeerrItemDetailView: View {
    let item: SeerrItem

    @Environment(SeerrRepository.self) private var seerrRepo

    @State private var detail: SeerrMediaDetail?
    @State private var isLoadingDetail = false
    @State private var requestingItem: SeerrItem? = nil

    private var alreadyRequested: Bool {
        seerrRepo.matchingRequest(for: item) != nil
    }

    private var isAvailable: Bool { item.availabilityStatus == .available }

    var body: some View {
        // This view had no adaptive/macOS-specific layout at all — a single fixed-height
        // backdrop plus whatever content the item has, with no minimum height tying it to
        // the actual window/screen. On a short item (sparse metadata) or a tall macOS
        // window, that left a large empty gap below the content instead of the layout
        // filling the space it actually has.
        GeometryReader { proxy in
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                backdrop

                VStack(alignment: .leading, spacing: DT.Spacing.md) {
                    HStack(spacing: 8) {
                        Text(item.mediaType == .tv ? "Series" : "Movie")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DT.Color.textSecondary)
                        if let year = item.year {
                            Text("·").foregroundStyle(.white.opacity(0.2))
                            Text(year)
                                .font(.system(size: 11))
                                .foregroundStyle(DT.Color.textSecondary)
                        }
                        if let runtime = detail?.runtimeMinutes {
                            Text("·").foregroundStyle(.white.opacity(0.2))
                            Text("\(runtime) min")
                                .font(.system(size: 11))
                                .foregroundStyle(DT.Color.textSecondary)
                        }
                        if let rating = detail?.voteAverage, rating > 0 {
                            Text("·").foregroundStyle(.white.opacity(0.2))
                            HStack(spacing: 2) {
                                Image(systemName: "star.fill").font(.system(size: 9))
                                Text(String(format: "%.1f", rating))
                            }
                            .font(.system(size: 11))
                            .foregroundStyle(Color(hex: "f59e0b"))
                        }
                    }

                    if let genres = detail?.genres, !genres.isEmpty {
                        Text(genres.joined(separator: " · "))
                            .font(.system(size: 12))
                            .foregroundStyle(DT.Color.textSecondary)
                    }

                    if let availabilityStatus = item.availabilityStatus {
                        availabilityRow(label: "Availability", status: (availabilityStatus.label, availabilityStatus.colorHex))
                    } else if let request = seerrRepo.matchingRequest(for: item) {
                        availabilityRow(label: "Request", status: request.displayStatus)
                    }

                    if isLoadingDetail {
                        ProgressView().frame(maxWidth: .infinity, alignment: .center)
                    }

                    if let tagline = detail?.tagline, !tagline.isEmpty {
                        Text(tagline)
                            .font(.system(size: 12, weight: .medium))
                            .italic()
                            .foregroundStyle(DT.Color.accent)
                    }

                    if let overview = detail?.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.system(size: 13))
                            .foregroundStyle(DT.Color.textPrimary.opacity(0.85))
                            .lineSpacing(3)
                    }

                    if let seasons = detail?.seasons, !seasons.isEmpty {
                        seasonsRow(seasons)
                    }

                    if let cast = detail?.cast, !cast.isEmpty {
                        castRow(cast)
                    }

                    actionButtons
                }
                .padding(DT.Spacing.pagePad)
            }
            .frame(minHeight: proxy.size.height)
        }
        }
        .background(DT.Color.backgroundPrimary)
        .ignoresSafeArea(edges: .top)
        .navigationTitle("")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        #endif
        .sheet(item: $requestingItem) { item in
            SeerrRequestConfirmSheet(item: item, requestingItem: $requestingItem)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .task {
            isLoadingDetail = true
            detail = await seerrRepo.mediaDetail(mediaType: item.mediaType, tmdbId: item.id)
            isLoadingDetail = false
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 10) {
            if !isAvailable && !alreadyRequested {
                Button {
                    requestingItem = item
                } label: {
                    HStack {
                        Image(systemName: "plus.circle")
                        Text("Request")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DT.Color.backgroundPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(DT.Color.accent)
                    .clipShape(RoundedRectangle(cornerRadius: DT.Radius.lg))
                }
            }

            Button {
                toggleWatchlist()
            } label: {
                Image(systemName: seerrRepo.isInWatchlist(item) ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DT.Color.textPrimary)
                    .frame(width: 48)
                    .padding(.vertical, 12)
                    .background(.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: DT.Radius.lg))
            }
        }
        .padding(.top, DT.Spacing.sm)
    }

    private func toggleWatchlist() {
        HapticManager.impact(.light)
        Task {
            if seerrRepo.isInWatchlist(item) {
                try? await seerrRepo.removeFromWatchlist(item)
            } else {
                try? await seerrRepo.addToWatchlist(item)
            }
        }
    }

    private func seasonsRow(_ seasons: [SeerrSeasonInfo]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Seasons")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DT.Color.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(seasons) { season in
                        VStack(spacing: 2) {
                            Text(season.label)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(DT.Color.textPrimary)
                            if let count = season.episodeCount {
                                Text("\(count) episodes")
                                    .font(.system(size: 9))
                                    .foregroundStyle(DT.Color.textSecondary)
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(.white.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.md))
                    }
                }
            }
        }
    }

    private func castRow(_ cast: [SeerrCastMember]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Cast")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DT.Color.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(cast.prefix(12)) { member in
                        VStack(spacing: 4) {
                            AsyncImage(url: member.profileURL) { phase in
                                switch phase {
                                case .success(let img): img.resizable().scaledToFill()
                                default: DT.Color.backgroundSecondary
                                }
                            }
                            .frame(width: 56, height: 56)
                            .clipShape(Circle())

                            Text(member.name)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(DT.Color.textPrimary)
                                .lineLimit(1)
                            if let character = member.character {
                                Text(character)
                                    .font(.system(size: 9))
                                    .foregroundStyle(DT.Color.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                        .frame(width: 64)
                    }
                }
            }
        }
    }

    private var backdrop: some View {
        ZStack(alignment: .bottomLeading) {
            if let url = item.backdropURL ?? item.posterURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: DT.Color.backgroundSecondary
                    }
                }
                .clipped()
            } else {
                DT.Color.backgroundSecondary
            }
            LinearGradient(colors: [.black.opacity(0.85), .clear], startPoint: .bottom, endPoint: .center)
            Text(item.title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .padding(DT.Spacing.pagePad)
                .shadow(color: .black.opacity(0.6), radius: 6)
        }
        .frame(height: 220)
    }

    private func availabilityRow(label: String, status: (label: String, colorHex: String)) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DT.Color.textPrimary)
            Spacer()
            Text(status.label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color(hex: status.colorHex))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Color(hex: status.colorHex).opacity(0.15))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color(hex: status.colorHex).opacity(0.3), lineWidth: 1))
        }
        .padding(12)
        .background(.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.md))
    }
}
