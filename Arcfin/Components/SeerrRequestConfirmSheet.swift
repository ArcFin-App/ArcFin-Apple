import SwiftUI
import SeerrAPI

struct SeerrRequestConfirmSheet: View {
    @Environment(SeerrRepository.self) private var seerrRepo

    let item: SeerrItem
    @Binding var requestingItem: SeerrItem?

    @State private var detail: SeerrMediaDetail?
    @State private var isLoadingDetail = true

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // Poster + title preview
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

                if isLoadingDetail {
                    ProgressView()
                        .scaleEffect(0.8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, DT.Spacing.pagePad)
                        .padding(.bottom, DT.Spacing.sm)
                }

                if let genres = detail?.genres, !genres.isEmpty {
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

                Button {
                    HapticManager.impact(.medium)
                    let captured = item
                    requestingItem = nil
                    Task { try? await seerrRepo.createRequest(mediaType: captured.mediaType, mediaId: captured.id) }
                } label: {
                    Text("Confirm Request")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(LinearGradient(
                            colors: [DT.Color.accentDeep, DT.Color.accent],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.lg))
                        .shadow(color: DT.Color.accent.opacity(0.35), radius: 16)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, DT.Spacing.pagePad)

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
        .task {
            detail = await seerrRepo.mediaDetail(mediaType: item.mediaType, tmdbId: item.id)
            isLoadingDetail = false
        }
    }
}
