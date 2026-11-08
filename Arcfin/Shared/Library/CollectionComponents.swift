// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

/// A Jellyfin BoxSet (Collection): a tall tinted hero, play-through and shuffle for the
/// whole collection, how much of it has been watched, and its titles in release order as a
/// numbered list (or a poster grid), sortable. The page's content, shared by the iPhone,
/// iPad and Mac `CollectionDetailView`.
struct CollectionContent: View {
    let collection: MediaItem
    let model: CollectionModel
    @Binding var sort: CollectionSort
    @Binding var showsGrid: Bool
    let columns: [GridItem]
    let zoomNamespace: Namespace.ID?

    @Environment(MediaRepository.self) private var mediaRepo

    private var items: [MediaItem] { model.items }
    private var sortedItems: [MediaItem] { model.sortedItems(by: sort) }
    private var watchedCount: Int { model.watchedCount }

    var body: some View {
        GeometryReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    heroSection

                    if model.isLoading {
                        ProgressView()
                            .tint(DT.Color.accent)
                            .frame(maxWidth: .infinity, minHeight: 240)
                    } else {
                        VStack(alignment: .leading, spacing: DT.Spacing.lg) {
                            actionRow
                            if !items.isEmpty { progressSection }
                            if let overview = model.detail?.item.overview ?? collection.overview, !overview.isEmpty {
                                Text(overview)
                                    .font(.system(.footnote))
                                    .foregroundStyle(DT.Color.textPrimary.opacity(0.8))
                                    .lineSpacing(4)
                                    .lineLimit(5)
                                    .padding(.horizontal, DT.Spacing.pagePad)
                            }
                            if !items.isEmpty { titlesSection }
                            if let people = model.detail?.people, !people.isEmpty { castSection(people) }
                        }
                        .padding(.top, DT.Spacing.md)
                    }

                    Spacer().frame(height: DT.Size.tabBarHeight + 24)
                }
                // A page-wide frame from the GeometryReader, not containerRelativeFrame: it follows an
                // iPhone turn (#325) and, on the Mac, can't feed the page's width back into the
                // window's layout (#345).
                .frame(width: proxy.size.width)
            }
        }
    }

    // MARK: - Hero

    /// The same hero as a title's page, with the fanned posters and title over its fade.
    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            DetailHeroBackdrop(url: mediaRepo.imageURL(for: collection, type: .backdrop, fillWidth: 1200), height: 300)

            HStack(alignment: .bottom, spacing: 14) {
                posterStack
                VStack(alignment: .leading, spacing: 6) {
                    Text("COLLECTION")
                        .font(.system(.caption2, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(DT.Color.accent)
                    Text(collection.name)
                        .font(.system(.title2, design: .default, weight: .heavy))
                        .foregroundStyle(DT.Color.textPrimary)
                        .tracking(-0.5)
                        .lineLimit(3)
                        .minimumScaleFactor(0.8)
                    Text(metaLine)
                        .font(.system(.caption))
                        .foregroundStyle(DT.Color.textSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, DT.Spacing.pagePad)
            .padding(.top, -96)
        }
    }

    private var metaLine: String {
        var parts: [String] = []
        if !items.isEmpty { parts.append("\(items.count) title\(items.count == 1 ? "" : "s")") }
        if let yearSpan = model.yearSpan { parts.append(yearSpan) }
        if let rating = collection.communityRating { parts.append("★ \(String(format: "%.1f", rating))") }
        return parts.joined(separator: " · ")
    }

    /// The first few posters fanned out, so the collection reads as a set at a glance.
    private var posterStack: some View {
        let fan = Array(sortedItems.prefix(3))
        return FannedPosters(urls: fan.isEmpty
            ? [mediaRepo.imageURL(for: collection, type: .primary, fillWidth: 240)]
            : fan.map { mediaRepo.imageURL(for: $0, type: .primary, fillWidth: 240) })
    }

    // MARK: - Actions & progress

    private var actionRow: some View {
        HStack(spacing: 12) {
            Button { model.playThrough(by: sort) } label: {
                Label(model.playLabel(by: sort), systemImage: "play.fill")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(DT.Color.backgroundPrimary)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(DT.Color.textPrimary, in: RoundedRectangle(cornerRadius: DT.Radius.md))
            }
            .buttonStyle(PressableButtonStyle())
            Button { model.shuffle(by: sort) } label: {
                Label("Shuffle", systemImage: "shuffle")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(DT.Color.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(DT.Color.textPrimary.opacity(0.1), in: RoundedRectangle(cornerRadius: DT.Radius.md))
            }
            .buttonStyle(PressableButtonStyle())
        }
        .disabled(model.playable(by: sort).isEmpty)
        .padding(.horizontal, DT.Spacing.pagePad)
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(watchedCount == items.count ? "All watched" : "\(watchedCount) of \(items.count) watched")
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(DT.Color.textSecondary)
                Spacer()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DT.Color.progressTrack)
                    Capsule().fill(DT.Color.accent)
                        .frame(width: geo.size.width * CGFloat(watchedCount) / CGFloat(max(items.count, 1)))
                }
            }
            .frame(height: 4)
        }
        .padding(.horizontal, DT.Spacing.pagePad)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Titles

    private var titlesSection: some View {
        VStack(alignment: .leading, spacing: DT.Spacing.sm) {
            HStack {
                Text("Titles")
                    .font(DT.Font.cardTitle)
                    .foregroundStyle(DT.Color.textPrimary)
                Spacer()
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(CollectionSort.allCases) { Text($0.label).tag($0) }
                    }
                } label: {
                    Label(sort.label, systemImage: "arrow.up.arrow.down")
                        .font(.system(.footnote, weight: .semibold))
                        .foregroundStyle(DT.Color.accent)
                        .frame(minHeight: 44)
                }
                .accessibilityLabel("Sort by \(sort.label)")
                Button {
                    withAnimation(DT.Animation.fast) { showsGrid.toggle() }
                } label: {
                    Image(systemName: showsGrid ? "list.bullet" : "square.grid.3x2")
                        .font(.system(.footnote, weight: .semibold))
                        .foregroundStyle(DT.Color.accent)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(showsGrid ? "Show as list" : "Show as grid")
            }
            .padding(.horizontal, DT.Spacing.pagePad)

            if showsGrid {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(sortedItems) { item in
                        Button { model.selectedItem = item } label: {
                            PosterCard(
                                title: item.name,
                                subtitle: item.productionYear.map { String($0) },
                                progress: item.userData?.playedPercentage.map { $0 / 100 },
                                imageURL: mediaRepo.imageURL(for: item)
                            )
                            .overlay(alignment: .topTrailing) { watchedBadge(item) }
                        }
                        .modifier(CollectionCardButtonStyle(id: item.id, namespace: zoomNamespace))
                    }
                }
                .padding(.horizontal, DT.Spacing.pagePad)
            } else {
                LazyVStack(spacing: 14) {
                    ForEach(Array(sortedItems.enumerated()), id: \.element.id) { index, item in
                        Button { model.selectedItem = item } label: { titleRow(item, number: index + 1) }
                            .modifier(CollectionCardButtonStyle(id: item.id, namespace: zoomNamespace))
                    }
                }
                .padding(.horizontal, DT.Spacing.pagePad)
            }
        }
    }

    private func titleRow(_ item: MediaItem, number: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if sort == .release {
                Text("\(number)")
                    .font(.system(.title3, design: .rounded, weight: .heavy))
                    .foregroundStyle(DT.Color.textSecondary)
                    .frame(width: 26, alignment: .trailing)
                    .padding(.top, 22)
            }
            CachedAsyncImage(url: mediaRepo.imageURL(for: item, type: .thumb, fillWidth: 360)) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                default: DT.Color.backgroundSecondary
                }
            }
            .frame(width: 128, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .bottom) {
                if let pct = item.userData?.playedPercentage, pct > 0, pct < 100 {
                    GeometryReader { geo in
                        Capsule().fill(DT.Color.accent)
                            .frame(width: geo.size.width * pct / 100, height: 3)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                    .padding(4)
                }
            }
            .overlay(alignment: .topTrailing) { watchedBadge(item) }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(DT.Color.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    if let year = item.productionYear { Text(String(year)) }
                    if let rating = item.communityRating {
                        Text("★ \(String(format: "%.1f", rating))").foregroundStyle(DT.Color.accent)
                    }
                }
                .font(.system(.caption))
                .foregroundStyle(DT.Color.textSecondary)
                if let overview = item.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.system(.caption2))
                        .foregroundStyle(DT.Color.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func watchedBadge(_ item: MediaItem) -> some View {
        if item.userData?.played == true {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(.footnote))
                .foregroundStyle(.white, DT.Color.accent)
                .padding(5)
                .accessibilityLabel("Watched")
        }
    }

    // MARK: - Cast

    private func castSection(_ people: [MediaPerson]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cast")
                .font(DT.Font.cardTitle)
                .foregroundStyle(DT.Color.textPrimary)
                .padding(.horizontal, DT.Spacing.pagePad)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(people) { person in
                        Button { model.selectedPerson = person } label: {
                            CastPersonCard(
                                imageURL: person.primaryImageTag.flatMap {
                                    mediaRepo.personImageURL(personId: person.id, tag: $0, fillWidth: 120)
                                },
                                name: person.name,
                                role: person.role,
                                placeholder: { personPlaceholder }
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, DT.Spacing.pagePad)
            }
            .shelfScrollButtons()
        }
    }

    private var personPlaceholder: some View {
        Circle()
            .fill(DT.Color.backgroundSecondary)
            .overlay(Image(systemName: "person.fill")
                .font(.system(.title2))
                .foregroundStyle(DT.Color.textSecondary.opacity(0.4)))
    }
}
