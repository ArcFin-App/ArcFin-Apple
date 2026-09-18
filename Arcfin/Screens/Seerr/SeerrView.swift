import SwiftUI
import SeerrAPI

struct SeerrView: View {
    @Environment(SeerrRepository.self) private var seerrRepo

    @State private var selectedCategory = "All"
    @State private var searchText = ""
    @State private var searchResults: [SeerrItem] = []
    @State private var isSearching = false
    @State private var requestingItem: SeerrItem? = nil
    @State private var selectedRequest: SeerrRequestItem? = nil
    @State private var isBootstrapping = false

    private let categories = ["All", "Movies", "Series"]

    private var displayItems: [SeerrItem] {
        let all = seerrRepo.trending + seerrRepo.popularMovies + seerrRepo.popularTV
        let deduped = Array(Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }).values)
        switch selectedCategory {
        case "Movies": return deduped.filter { $0.mediaType == .movie }
        case "Series": return deduped.filter { $0.mediaType == .tv }
        default:       return deduped
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if !seerrRepo.isConfigured {
                    notConfiguredView
                } else {
                    mainContent
                }
            }
            .background(DT.Color.backgroundPrimary)
            .navigationTitle("Requests")
            .arcfinNavTitleLarge("Requests")
            .navigationDestination(item: $selectedRequest) { req in
                SeerrRequestDetailView(request: req)
            }
        }
        .task(id: seerrRepo.isConfigured) {
            guard seerrRepo.isConfigured else { return }
            isBootstrapping = true
            await seerrRepo.loadDiscover()
            await seerrRepo.loadRequests()
            isBootstrapping = false
        }
        .onChange(of: searchText) { _, query in
            performSearch(query: query)
        }
        .sheet(item: $requestingItem) { item in
            SeerrRequestConfirmSheet(item: item, requestingItem: $requestingItem)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
    }

    // MARK: - Not configured

    private var notConfiguredView: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.fill")
                .font(.system(size: 48))
                .foregroundStyle(DT.Color.accent)
            Text("Seerr Not Connected")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(DT.Color.textPrimary)
            Text("Add your Seerr server URL and credentials in Settings → Plugins → Seerr.")
                .font(.system(size: 14))
                .foregroundStyle(DT.Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Main content

    private var mainContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                header
                if !searchText.isEmpty {
                    searchResultsSection
                } else {
                    if isBootstrapping || (seerrRepo.isLoadingDiscover && displayItems.isEmpty) {
                        loadingGrid
                        requestsLoadingList
                    } else {
                        discoverGrid
                        requestsList
                    }
                }
                Spacer().frame(height: DT.Size.tabBarHeight + 16)
            }
        }
    }

    private var requestsLoadingList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("My Requests")
                    .font(DT.Font.cardTitle)
                    .foregroundStyle(DT.Color.textPrimary)
                Spacer()
            }
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 66)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.06), lineWidth: 1))
            }
        }
        .padding(.horizontal, DT.Spacing.pagePad)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(DT.Color.textSecondary)
                TextField("Search movies, series…", text: $searchText)
                    .font(DT.Font.caption)
                    .foregroundStyle(DT.Color.textPrimary)
                    .autocorrectionDisabled()
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(DT.Color.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.white.opacity(0.06))
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.1), lineWidth: 1))
            .padding(.bottom, DT.Spacing.sm)

            // Category chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(categories, id: \.self) { cat in
                        Button {
                            withAnimation(DT.Animation.fast) { selectedCategory = cat }
                        } label: {
                            Text(cat)
                                .font(.system(size: 11, weight: selectedCategory == cat ? .bold : .regular))
                                .foregroundStyle(selectedCategory == cat ? DT.Color.accent : DT.Color.textSecondary)
                                .padding(.horizontal, 14).padding(.vertical, 5)
                                .background(selectedCategory == cat ? DT.Color.accent.opacity(0.15) : Color.white.opacity(0.05))
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(
                                    selectedCategory == cat ? DT.Color.accent.opacity(0.45) : Color.white.opacity(0.08),
                                    lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.bottom, DT.Spacing.md)
        }
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.top, 12)
        .background(LinearGradient(
            colors: [DT.Color.accent.opacity(0.05), .clear],
            startPoint: .top, endPoint: .bottom))
    }

    // MARK: - Discover grid

    private var discoverGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(selectedCategory == "All" ? "Trending Now" : selectedCategory)
                    .font(DT.Font.cardTitle)
                    .foregroundStyle(DT.Color.textPrimary)
                Spacer()
                if seerrRepo.isLoadingDiscover {
                    ProgressView().scaleEffect(0.7)
                }
            }
            .padding(.horizontal, DT.Spacing.pagePad)

#if os(tvOS)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DT.Spacing.shelfGap) {
                    ForEach(displayItems) { item in
                        Button { requestingItem = item } label: {
                            PosterCard(
                                title: item.title,
                                subtitle: item.year,
                                imageURL: item.backdropURL ?? item.posterURL
                            )
                        }
                        .buttonStyle(TVCardButtonStyle())
                        .focusEffectDisabled()
                    }
                }
                .padding(.horizontal, DT.Spacing.pagePad)
                .focusSection()
            }
#else
            LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 8) {
                ForEach(displayItems) { item in
                    discoverCard(item)
                }
            }
            .padding(.horizontal, DT.Spacing.pagePad)
#endif
        }
        .padding(.bottom, DT.Spacing.md)
    }

    private func discoverCard(_ item: SeerrItem) -> some View {
        let alreadyRequested = seerrRepo.requests.contains { $0.mediaTitle == item.title }
        let isAvailable = item.availabilityStatus == .available

        return ZStack(alignment: .bottomLeading) {
            // Poster
            if let url = item.posterURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: posterPlaceholder(item: item)
                    }
                }
                .clipped()
            } else {
                posterPlaceholder(item: item)
            }

            // Type badge
            VStack {
                HStack {
                    Text(item.mediaType == .tv ? "SERIES" : "MOVIE")
                        .font(.system(size: 7, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(.black.opacity(0.5))
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    Spacer()
                }
                Spacer()
            }
            .padding(8)

            // Bottom info
            VStack(alignment: .leading, spacing: 4) {
                if isAvailable {
                    availabilityPill(label: "Available", hex: "10b981")
                } else if alreadyRequested {
                    availabilityPill(label: "Requested", hex: "f59e0b")
                }

                Text(item.title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(DT.Color.textPrimary)
                    .lineLimit(2)

                if let year = item.year {
                    Text(year)
                        .font(.system(size: 9))
                        .foregroundStyle(DT.Color.textSecondary)
                }

                if !isAvailable && !alreadyRequested {
                    Button { requestingItem = item } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle").font(.system(size: 9))
                            Text("Request").font(.system(size: 9, weight: .bold))
                        }
                        .foregroundStyle(DT.Color.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(DT.Color.accent.opacity(0.15))
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(DT.Color.accent.opacity(0.4), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
            .padding(10)
            .background(LinearGradient(
                colors: [.black.opacity(0.95), .clear],
                startPoint: .bottom, endPoint: .top))
        }
        .aspectRatio(2/3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.06), lineWidth: 1))
    }

    private func posterPlaceholder(item: SeerrItem) -> some View {
        LinearGradient(
            colors: [DT.Color.accentDeep, DT.Color.backgroundPrimary],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private func availabilityPill(label: String, hex: String) -> some View {
        Text(label)
            .font(.system(size: 7, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(Color(hex: hex))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color(hex: hex).opacity(0.15))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color(hex: hex).opacity(0.3), lineWidth: 1))
    }

    // MARK: - Loading skeleton

    private var loadingGrid: some View {
        LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 8) {
            ForEach(0..<6, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.06))
                    .aspectRatio(2/3, contentMode: .fit)
            }
        }
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.bottom, DT.Spacing.md)
    }

    // MARK: - Search results

    private var searchResultsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Search Results")
                    .font(DT.Font.cardTitle)
                    .foregroundStyle(DT.Color.textPrimary)
                Spacer()
                if isSearching { ProgressView().scaleEffect(0.7) }
            }
            .padding(.horizontal, DT.Spacing.pagePad)

            if !isSearching && searchResults.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .frame(height: 200)
            } else {
#if os(tvOS)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DT.Spacing.shelfGap) {
                        ForEach(searchResults) { item in
                            Button { requestingItem = item } label: {
                                PosterCard(
                                    title: item.title,
                                    subtitle: item.year,
                                    imageURL: item.backdropURL ?? item.posterURL
                                )
                            }
                            .buttonStyle(TVCardButtonStyle())
                            .focusEffectDisabled()
                        }
                    }
                    .padding(.horizontal, DT.Spacing.pagePad)
                    .focusSection()
                }
#else
                LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 8) {
                    ForEach(searchResults) { item in
                        discoverCard(item)
                    }
                }
                .padding(.horizontal, DT.Spacing.pagePad)
#endif
            }
        }
        .padding(.bottom, DT.Spacing.md)
    }

    // MARK: - My Requests

    private var requestsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("My Requests")
                    .font(DT.Font.cardTitle)
                    .foregroundStyle(DT.Color.textPrimary)
                Spacer()
                if seerrRepo.isLoadingRequests {
                    ProgressView().scaleEffect(0.7)
                } else {
                    Text("\(seerrRepo.requests.count) total")
                        .font(DT.Font.caption2)
                        .foregroundStyle(DT.Color.textSecondary)
                }
            }

            if seerrRepo.requests.isEmpty && !seerrRepo.isLoadingRequests {
                ContentUnavailableView(
                    "No Requests",
                    systemImage: "clock",
                    description: Text("Your media requests will appear here.")
                )
                .frame(height: 160)
            } else {
                ForEach(seerrRepo.requests) { req in
                    Button { selectedRequest = req } label: {
                        requestRow(req)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, DT.Spacing.pagePad)
    }

    private func requestRow(_ req: SeerrRequestItem) -> some View {
#if os(tvOS)
        let thumbW: CGFloat = 96
        let thumbH: CGFloat = 54
        let thumbRadius: CGFloat = 6
        let thumbURL: URL? = req.backdropURL ?? req.posterURL
#else
        let thumbW: CGFloat = 32
        let thumbH: CGFloat = 44
        let thumbRadius: CGFloat = 6
        let thumbURL: URL? = req.posterURL
#endif
        return HStack(spacing: 10) {
            // Thumbnail
            if let url = thumbURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: posterMiniFallback
                    }
                }
                .frame(width: thumbW, height: thumbH)
                .clipShape(RoundedRectangle(cornerRadius: thumbRadius))
            } else {
                posterMiniFallback
                    .clipShape(RoundedRectangle(cornerRadius: thumbRadius))
                    .frame(width: thumbW, height: thumbH)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(req.mediaTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DT.Color.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(req.mediaType == .tv ? "Series" : "Movie")
                        .font(DT.Font.caption2)
                        .foregroundStyle(DT.Color.textSecondary)
                    Text("·")
                        .font(DT.Font.caption2)
                        .foregroundStyle(.white.opacity(0.2))
                    Text(req.requestedAt, style: .date)
                        .font(DT.Font.caption2)
                        .foregroundStyle(DT.Color.textSecondary)
                    requestStatusPill(req.status)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 11)
        .background(.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.06), lineWidth: 1))
    }

    private var posterMiniFallback: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(LinearGradient(
                colors: [DT.Color.accent.opacity(0.08), Color(hex: "0a0a14")],
                startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.06), lineWidth: 1))
    }

    private func requestStatusPill(_ status: RequestStatus) -> some View {
        let (label, hex): (String, String) = switch status {
        case .approved:  ("Approved", "10b981")
        case .available: ("Available", "10b981")
        case .declined:  ("Declined", "EF4444")
        case .pending:   ("Pending", "f59e0b")
        }
        return Text(label)
            .font(.system(size: 7, weight: .bold))
            .foregroundStyle(Color(hex: hex))
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Color(hex: hex).opacity(0.15))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color(hex: hex).opacity(0.3), lineWidth: 1))
    }

    // MARK: - Confirm sheet


    // MARK: - Search

    private func performSearch(query: String) {
        guard !query.isEmpty else { searchResults = []; return }
        isSearching = true
        Task {
            searchResults = await seerrRepo.search(query: query)
            isSearching = false
        }
    }
}

#Preview {
    SeerrView()
        .environment(SeerrRepository())
}
