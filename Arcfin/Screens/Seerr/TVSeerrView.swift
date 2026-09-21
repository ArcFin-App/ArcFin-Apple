#if os(tvOS)
import SwiftUI
import SeerrAPI

struct TVSeerrView: View {
    @Environment(SeerrRepository.self) private var seerrRepo

    @State private var requestingItem: SeerrItem? = nil
    @State private var showRequestAlert = false

    var body: some View {
        NavigationStack {
            Group {
                if !seerrRepo.isConfigured {
                    notConfiguredView
                } else if seerrRepo.authFailed {
                    authFailedView
                } else {
                    mainContent
                }
            }
            .background(DT.Color.backgroundPrimary)
            .navigationTitle("Requests")
        }
        .task(id: seerrRepo.isConfigured) {
            guard seerrRepo.isConfigured else { return }
            await seerrRepo.loadDiscover()
            await seerrRepo.loadRequests()
        }
        .alert(
            requestingItem.map { "Request \($0.title)" } ?? "Request",
            isPresented: $showRequestAlert,
            presenting: requestingItem
        ) { item in
            Button("Send Request") {
                Task { try? await seerrRepo.createRequest(mediaType: item.mediaType, mediaId: item.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { item in
            let year = item.year.map { " (\($0))" } ?? ""
            let type = item.mediaType == .tv ? "Series" : "Movie"
            return Text("\(type)\(year)")
        }
    }

    // MARK: - Auth failed

    private var authFailedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.slash.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color(hex: "EF4444"))
            Text("Authentication Failed")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(DT.Color.textPrimary)
            Text("Check your Seerr credentials in Profile → Plugins → Seerr.")
                .font(.system(size: 22))
                .foregroundStyle(DT.Color.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 600)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Not configured

    private var notConfiguredView: some View {
        VStack(spacing: 20) {
            Image(systemName: "clock.fill")
                .font(.system(size: 64))
                .foregroundStyle(DT.Color.accent)
            Text("Seerr Not Connected")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(DT.Color.textPrimary)
            Text("Add your Seerr server in Profile → Plugins → Seerr.")
                .font(.system(size: 22))
                .foregroundStyle(DT.Color.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 600)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Main content

    private var mainContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                watchlistLink
                    .padding(.horizontal, 80)
                    .padding(.bottom, 40)
                    .focusSection()

                if !seerrRepo.trending.isEmpty {
                    tvShelf(title: "Trending", items: seerrRepo.trending)
                }
                if !seerrRepo.popularMovies.isEmpty {
                    tvShelf(title: "Popular Movies", items: seerrRepo.popularMovies)
                }
                if !seerrRepo.popularTV.isEmpty {
                    tvShelf(title: "Popular Series", items: seerrRepo.popularTV)
                }

                requestsSection
                    .padding(.top, 16)
            }
            .padding(.vertical, 48)
            .focusSection()
        }
    }

    // MARK: - Watchlist entry

    private var watchlistLink: some View {
        NavigationLink {
            WatchlistView()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 20, weight: .semibold))
                Text("Watchlist")
                    .font(.system(size: 20, weight: .semibold))
            }
            .foregroundStyle(DT.Color.textPrimary)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Capsule().fill(Color.white.opacity(0.08)))
            .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
        }
        .buttonStyle(TVCardButtonStyle())
        .focusEffectDisabled()
    }

    // MARK: - Discover shelf

    private func tvShelf(title: String, items: [SeerrItem]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(DT.Color.textPrimary)
                .padding(.horizontal, 80)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(items) { item in
                        Button {
                            requestingItem = item
                            showRequestAlert = true
                        } label: {
                            TVSeerrCard(item: item)
                        }
                        .buttonStyle(TVCardButtonStyle())
                        .focusEffectDisabled()
                    }
                }
                .padding(.horizontal, 80)
                .padding(.top, 20)
                .focusSection()
            }
            .scrollClipDisabled()
        }
        .padding(.bottom, 40)
        .focusSection()
    }

    // MARK: - My Requests

    private var requestsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("My Requests")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(DT.Color.textPrimary)
                if seerrRepo.isLoadingRequests {
                    ProgressView().padding(.leading, 8)
                } else if !seerrRepo.requests.isEmpty {
                    Text("\(seerrRepo.requests.count)")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 4)
                        .background(Capsule().fill(DT.Color.accent.opacity(0.3)))
                        .overlay(Capsule().stroke(DT.Color.accent.opacity(0.5), lineWidth: 1))
                }
            }
            .padding(.horizontal, 80)

            if seerrRepo.requests.isEmpty && !seerrRepo.isLoadingRequests {
                ContentUnavailableView(
                    "No Requests",
                    systemImage: "clock",
                    description: Text("Your media requests will appear here.")
                )
                .frame(height: 260)
            } else {
                VStack(spacing: 12) {
                    ForEach(seerrRepo.requests) { req in
                        TVRequestRow(req: req)
                    }
                }
                .padding(.horizontal, 80)
                .focusSection()
            }
        }
    }
}

// MARK: - Seerr discover card

private struct TVSeerrCard: View {
    let item: SeerrItem
    @Environment(\.isFocused) private var isFocused

    private var statusColor: Color? {
        switch item.availabilityStatus {
        case .available: Color(hex: "10b981")
        default: nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                AsyncImage(url: item.backdropURL ?? item.posterURL) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default:
                        LinearGradient(
                            colors: [DT.Color.accentDeep.opacity(0.4), DT.Color.backgroundSecondary],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    }
                }
                .frame(width: DT.Size.posterCard.width, height: DT.Size.posterCard.height)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: DT.Radius.card))
                .overlay(
                    RoundedRectangle(cornerRadius: DT.Radius.card)
                        .stroke(isFocused ? DT.Color.accent : Color.clear, lineWidth: 3)
                )
                .shadow(color: isFocused ? DT.Color.accent.opacity(0.4) : .clear, radius: 10)
                .scaleEffect(isFocused ? 1.05 : 1.0)
                .animation(.spring(response: 0.2, dampingFraction: 0.75), value: isFocused)

                if let color = statusColor {
                    Text(item.availabilityStatus == .available ? "Available" : "")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(color)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(color.opacity(0.2))
                        .clipShape(Capsule())
                        .padding(10)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                if let year = item.year {
                    Text(year)
                        .font(.system(size: 10 * DT.Scale.font, weight: .medium))
                        .foregroundStyle(DT.Color.textSecondary)
                        .lineLimit(1)
                }
                Text(item.title)
                    .font(.system(size: 12 * DT.Scale.font, weight: .semibold))
                    .foregroundStyle(isFocused ? DT.Color.accent : DT.Color.textPrimary)
                    .lineLimit(2)
                    .animation(DT.Animation.fast, value: isFocused)
            }
            .frame(width: DT.Size.posterCard.width, height: 84, alignment: .topLeading)
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Request row

private struct TVRequestRow: View {
    let req: SeerrRequestItem
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        HStack(spacing: 20) {
            AsyncImage(url: req.backdropURL ?? req.posterURL) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFill()
                default:
                    RoundedRectangle(cornerRadius: DT.Radius.sm)
                        .fill(DT.Color.backgroundTertiary)
                }
            }
            .frame(width: 192, height: 108)
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.sm))

            VStack(alignment: .leading, spacing: 8) {
                Text(req.mediaTitle)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(DT.Color.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 10) {
                    Text(req.mediaType == .tv ? "Series" : "Movie")
                        .font(.system(size: 18))
                        .foregroundStyle(DT.Color.textSecondary)

                    Text("·").foregroundStyle(.white.opacity(0.2))

                    Text(req.requestedAt, style: .date)
                        .font(.system(size: 18))
                        .foregroundStyle(DT.Color.textSecondary)

                    statusPill(req.status)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: DT.Radius.md)
                .fill(isFocused ? Color.white.opacity(0.08) : Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DT.Radius.md)
                .stroke(isFocused ? DT.Color.accent.opacity(0.4) : Color.white.opacity(0.05), lineWidth: 1)
        )
        .animation(.spring(response: 0.18, dampingFraction: 0.8), value: isFocused)
    }

    private func statusPill(_ status: RequestStatus) -> some View {
        let (label, hex): (String, String) = switch status {
        case .approved:  ("Approved",  "10b981")
        case .available: ("Available", "10b981")
        case .declined:  ("Declined",  "EF4444")
        case .pending:   ("Pending",   "f59e0b")
        }
        return Text(label)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(Color(hex: hex))
            .padding(.horizontal, 12).padding(.vertical, 4)
            .background(Color(hex: hex).opacity(0.15))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color(hex: hex).opacity(0.3), lineWidth: 1))
    }
}
#endif
