import SwiftUI

// MARK: - Data

private struct TrendingItem: Identifiable {
    let id = UUID()
    var title: String
    var year: String
    var type: String
    var hue: Color
    var status: RequestStatus?
}

private struct MyRequest: Identifiable {
    let id = UUID()
    var title: String
    var type: String
    var status: RequestStatus
    var date: String
    var progress: Double?
}

private let trending: [TrendingItem] = [
    TrendingItem(title: "Sinners",         year: "2025", type: "Movie",  hue: Color(arcfinHex: "1a0808"), status: nil),
    TrendingItem(title: "The Pitt",        year: "2025", type: "Series", hue: Color(arcfinHex: "080e1a"), status: nil),
    TrendingItem(title: "White Lotus S3",  year: "2025", type: "Series", hue: Color(arcfinHex: "0a1208"), status: .available),
    TrendingItem(title: "Thunderbolts*",   year: "2025", type: "Movie",  hue: Color(arcfinHex: "0a0a1a"), status: .downloading),
    TrendingItem(title: "Mickey 17",       year: "2025", type: "Movie",  hue: Color(arcfinHex: "120808"), status: nil),
    TrendingItem(title: "Warfare",         year: "2025", type: "Movie",  hue: Color(arcfinHex: "080a0a"), status: nil),
]

private let myRequests: [MyRequest] = [
    MyRequest(title: "I Saw the TV Glow", type: "Movie", status: .downloading, date: "Apr 28", progress: 0.64),
    MyRequest(title: "The Substance",     type: "Movie", status: .pending,     date: "Apr 20", progress: nil),
    MyRequest(title: "A Real Pain",       type: "Movie", status: .approved,    date: "Apr 15", progress: nil),
    MyRequest(title: "Eddington",         type: "Movie", status: .pending,     date: "May 1",  progress: nil),
]

private let categories = ["All", "Movies", "Series", "Anime", "4K"]

// MARK: - View

struct JellyseerrView: View {
    @State private var selectedCategory = "All"
    @State private var searchText = ""
    @State private var requestedTitles: Set<String> = []
    @State private var confirmingTitle: String? = nil

    private var totalRequests: Int { myRequests.count + requestedTitles.count }

    var body: some View {
        ZStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    header
                    trendingGrid
                    requestsList

                    Spacer().frame(height: DT.Size.tabBarHeight + 16)
                }
            }

            if let title = confirmingTitle {
                confirmSheet(title: title)
            }
        }
        .background(DT.Color.backgroundPrimary)
        .ignoresSafeArea(edges: .top)
        .animation(DT.Animation.standard, value: confirmingTitle)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(LinearGradient(
                            colors: [DT.Color.accentDeep, DT.Color.accent],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 22, height: 22)

                    Image(systemName: "clock.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.white)
                }

                Text("Jellyseerr")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(DT.Color.accent)
            }

            Text("Discover & Request")
                .font(.system(size: 24, weight: .heavy))
                .foregroundStyle(DT.Color.textPrimary)
                .tracking(-0.8)
                .padding(.top, 4)
                .padding(.bottom, DT.Spacing.sm)

            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(DT.Color.textSecondary)

                TextField("Search movies, series, anime…", text: $searchText)
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
                                .padding(.horizontal, 14)
                                .padding(.vertical, 5)
                                .background(selectedCategory == cat ? DT.Color.accent.opacity(0.15) : Color.white.opacity(0.05))
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule().stroke(
                                        selectedCategory == cat ? DT.Color.accent.opacity(0.45) : Color.white.opacity(0.08),
                                        lineWidth: 1
                                    )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.bottom, DT.Spacing.md)
        }
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.top, 52)
        .background(
            LinearGradient(
                colors: [DT.Color.accent.opacity(0.05), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: - Trending 2-col grid

    private var trendingGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Trending Now")
                    .font(DT.Font.cardTitle)
                    .foregroundStyle(DT.Color.textPrimary)
                Spacer()
                Button("Browse All") {}
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DT.Color.accent)
                    .buttonStyle(.plain)
            }

            LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 8) {
                ForEach(trending) { item in
                    trendingCard(item)
                }
            }
        }
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.bottom, DT.Spacing.md)
    }

    private func trendingCard(_ item: TrendingItem) -> some View {
        let isRequested = requestedTitles.contains(item.title)
        let effectiveStatus = isRequested ? RequestStatus.pending : item.status

        return ZStack(alignment: .bottomLeading) {
            // Background
            LinearGradient(
                colors: [item.hue, DT.Color.backgroundPrimary],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Texture
            Canvas { context, size in
                for y in stride(from: 0, through: size.height, by: 4) {
                    context.fill(
                        Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                        with: .color(.white.opacity(0.01))
                    )
                }
            }
            .allowsHitTesting(false)

            // Glass sheen
            LinearGradient(colors: [.white.opacity(0.05), .clear], startPoint: .top, endPoint: .init(x: 0.5, y: 0.35))

            // Type badge
            VStack {
                HStack {
                    Text(item.type.uppercased())
                        .font(.system(size: 7, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.5))
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.white.opacity(0.1), lineWidth: 1))
                    Spacer()
                }
                Spacer()
            }
            .padding(8)

            // Bottom info
            VStack(alignment: .leading, spacing: 4) {
                if let status = effectiveStatus {
                    RequestStatusPill(status: status)
                }

                Text(item.title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(DT.Color.textPrimary)
                    .lineLimit(2)

                Text(item.year)
                    .font(DT.Font.caption2)
                    .foregroundStyle(DT.Color.textSecondary)

                if effectiveStatus == nil {
                    Button {
                        confirmingTitle = item.title
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 9))
                            Text("Request")
                                .font(.system(size: 9, weight: .bold))
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
                    .padding(.top, 4)
                } else if isRequested {
                    Text("✓ Requested")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color(arcfinHex: "f59e0b"))
                        .padding(.top, 4)
                }
            }
            .padding(10)
            .background(
                LinearGradient(
                    colors: [.black.opacity(0.95), .clear],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
        }
        .aspectRatio(2/3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.06), lineWidth: 1))
    }

    // MARK: - My requests list

    private var requestsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("My Requests")
                    .font(DT.Font.cardTitle)
                    .foregroundStyle(DT.Color.textPrimary)
                Spacer()
                Text("\(totalRequests) total")
                    .font(DT.Font.caption2)
                    .foregroundStyle(DT.Color.textSecondary)
            }

            ForEach(myRequests) { req in
                requestRow(req)
            }

            // User-added requests
            ForEach(Array(requestedTitles), id: \.self) { title in
                requestRow(MyRequest(title: title, type: "Movie", status: .pending, date: "Just now", progress: nil))
            }
        }
        .padding(.horizontal, DT.Spacing.pagePad)
    }

    private func requestRow(_ req: MyRequest) -> some View {
        ZStack(alignment: .leading) {
            if let progress = req.progress {
                LinearGradient(
                    colors: [DT.Color.accent.opacity(0.05), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(maxWidth: .infinity)
                .scaleEffect(x: progress, anchor: .leading)
            }

            HStack(spacing: 10) {
                // Mini poster placeholder
                RoundedRectangle(cornerRadius: 6)
                    .fill(LinearGradient(
                        colors: [DT.Color.accent.opacity(0.08), Color(arcfinHex: "0a0a14")],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.06), lineWidth: 1))
                    .frame(width: 32, height: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text(req.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DT.Color.textPrimary)

                    HStack(spacing: 6) {
                        Text(req.type)
                            .font(DT.Font.caption2)
                            .foregroundStyle(DT.Color.textSecondary)
                        Text("·")
                            .font(DT.Font.caption2)
                            .foregroundStyle(.white.opacity(0.2))
                        Text(req.date)
                            .font(DT.Font.caption2)
                            .foregroundStyle(DT.Color.textSecondary)
                        RequestStatusPill(status: req.status)
                    }

                    if let progress = req.progress {
                        HStack(spacing: 6) {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 2).fill(.white.opacity(0.08))
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(LinearGradient(
                                            colors: [DT.Color.accentDeep, DT.Color.accent],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        ))
                                        .frame(width: geo.size.width * progress)
                                }
                            }
                            .frame(height: 2)

                            Text("\(Int(progress * 100))%")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(DT.Color.accent)
                        }
                        .padding(.top, 2)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
        }
        .background(.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.06), lineWidth: 1))
    }

    // MARK: - Confirm sheet

    private func confirmSheet(title: String) -> some View {
        ZStack(alignment: .bottom) {
            // Scrim
            Color.black.opacity(0.7)
                .background(.ultraThinMaterial.opacity(0.5))
                .ignoresSafeArea()
                .onTapGesture { confirmingTitle = nil }

            // Sheet
            VStack(spacing: 0) {
                // Handle
                Capsule()
                    .fill(.white.opacity(0.2))
                    .frame(width: 36, height: 4)
                    .padding(.top, DT.Spacing.lg)
                    .padding(.bottom, DT.Spacing.lg)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Request \"\(title)\"")
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(DT.Color.textPrimary)

                    Text("This will send a request to your Jellyseerr server. You'll be notified when it's available.")
                        .font(DT.Font.caption)
                        .foregroundStyle(DT.Color.textSecondary)
                        .lineSpacing(4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DT.Spacing.pagePad)
                .padding(.bottom, DT.Spacing.lg)

                // Quality options
                HStack(spacing: 8) {
                    ForEach(["Any Quality", "1080p", "4K HDR"], id: \.self) { q in
                        Text(q)
                            .font(.system(size: 10, weight: q == "Any Quality" ? .bold : .regular))
                            .foregroundStyle(q == "Any Quality" ? DT.Color.accent : DT.Color.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(q == "Any Quality" ? DT.Color.accent.opacity(0.12) : Color.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(q == "Any Quality" ? DT.Color.accent.opacity(0.4) : Color.white.opacity(0.08), lineWidth: 1)
                            )
                    }
                }
                .padding(.horizontal, DT.Spacing.pagePad)
                .padding(.bottom, DT.Spacing.lg)

                // CTA
                Button {
                    requestedTitles.insert(title)
                    confirmingTitle = nil
                } label: {
                    Text("Confirm Request")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(LinearGradient(
                            colors: [DT.Color.accentDeep, DT.Color.accent],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.lg))
                        .shadow(color: DT.Color.accent.opacity(0.35), radius: 16)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, DT.Spacing.pagePad)

                Button {
                    confirmingTitle = nil
                } label: {
                    Text("Cancel")
                        .font(.system(size: 13))
                        .foregroundStyle(DT.Color.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, DT.Spacing.pagePad)
                .padding(.bottom, DT.Spacing.xl)
            }
            .background(Color(arcfinHex: "0e121c").opacity(0.95))
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.sheet, style: .continuous))
            .overlay(
                VStack {
                    RoundedRectangle(cornerRadius: DT.Radius.sheet, style: .continuous)
                        .stroke(DT.Color.accent.opacity(0.2), lineWidth: 1)
                        .frame(height: 1)
                    Spacer()
                }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .ignoresSafeArea()
    }
}

#Preview {
    JellyseerrView()
}
