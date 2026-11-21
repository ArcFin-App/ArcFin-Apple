// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI
import SeerrAPI

/// A person's page below the navigation bar: photo, name and bio, their titles in the library,
/// and what else they're in.
struct PersonDetailContent<ItemLink: View, CreditLink: View, Header: View>: View {
    @Environment(MediaRepository.self) private var mediaRepo
    @Environment(SeerrRepository.self) private var seerrRepo
    let model: PersonDetailModel
    let columns: [GridItem]
    let creditScale: CGFloat
    /// The artwork for a library title's card, where the platform's card isn't a portrait
    /// poster; the primary image otherwise.
    var cardImageURL: ((MediaItem) -> URL?)? = nil
    /// Each platform's button around a library title's poster.
    @ViewBuilder let itemLink: (MediaItem, PosterCard) -> ItemLink
    /// Each platform's button around a credit Seerr can request.
    @ViewBuilder let creditLink: (SeerrPersonCredit, PersonCreditCard) -> CreditLink
    /// Each platform's wrapper around the photo, name and role.
    @ViewBuilder let header: (PersonDetailHeader) -> Header

    var body: some View {
        let missingCredits = model.missingCredits(seerrRepo: seerrRepo)
        ScrollView(showsIndicators: false) {
            VStack(spacing: DT.Spacing.md) {
                header(PersonDetailHeader(person: model.person))

                if model.isLoading {
                    // Full width and a fixed height, so the page is already its final size
                    // while loading instead of starting narrow and widening once data lands.
                    ProgressView()
                        .tint(DT.Color.accent)
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    if let overview = model.detail?.overview, !overview.isEmpty {
                        Text(overview)
                            .contentFont(.footnote, design: .default)
                            .foregroundStyle(DT.Color.textPrimary.opacity(0.85))
                            .lineSpacing(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            // Apple TV scrolls only by moving focus: a long bio pushed the titles
                            // below the screen with nothing focusable in between.
                            .tvFocusable(cornerRadius: DT.Radius.md)
                            .padding(.horizontal, DT.Spacing.pagePad)
                    }

                    if !model.items.isEmpty {
                        PersonSectionHeader(title: "In Your Library")
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(model.items) { item in
                                itemLink(item, PosterCard(
                                    title: item.name,
                                    subtitle: item.productionYear.map { String($0) },
                                    imageURL: cardImageURL.map { $0(item) } ?? mediaRepo.imageURL(for: item)
                                ))
                            }
                        }
                        .padding(.horizontal, DT.Spacing.pagePad)
                    }

                    if !missingCredits.isEmpty {
                        PersonSectionHeader(title: "Also Appears In")
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(alignment: .top, spacing: 12) {
                                ForEach(missingCredits) { credit in
                                    creditLink(credit, PersonCreditCard(credit: credit, scale: creditScale))
                                }
                            }
                            .padding(.horizontal, DT.Spacing.pagePad)
                            .padding(.vertical, 12)
                        }
                        .shelfScrollButtons()
                        .scrollClipDisabled()
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, DT.Spacing.md)
        }
    }
}

extension PersonDetailContent where Header == PersonDetailHeader {
    init(
        model: PersonDetailModel, columns: [GridItem], creditScale: CGFloat,
        @ViewBuilder itemLink: @escaping (MediaItem, PosterCard) -> ItemLink,
        @ViewBuilder creditLink: @escaping (SeerrPersonCredit, PersonCreditCard) -> CreditLink
    ) {
        self.init(model: model, columns: columns, creditScale: creditScale,
                  itemLink: itemLink, creditLink: creditLink, header: { $0 })
    }
}

struct PersonDetailHeader: View {
    @Environment(MediaRepository.self) private var mediaRepo
    let person: MediaPerson

    var body: some View {
        VStack(spacing: 10) {
            Group {
                if let tag = person.primaryImageTag,
                   let url = mediaRepo.personImageURL(personId: person.id, tag: tag, fillWidth: 300) {
                    RetryingAsyncImage(
                        url: url,
                        logCategory: "PersonDetailView",
                        logContext: "header name=\(person.name)",
                        content: { img in img.resizable().scaledToFill() },
                        placeholder: { PersonPhotoPlaceholder() }
                    )
                } else {
                    PersonPhotoPlaceholder()
                }
            }
            .frame(width: 140, height: 140)
            .clipShape(Circle())
            .overlay(Circle().stroke(DT.Color.textPrimary.opacity(0.1), lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 12, y: 4)

            Text(person.name)
                .contentFont(.title3, design: .default, weight: .heavy)
                .foregroundStyle(DT.Color.textPrimary)
                .multilineTextAlignment(.center)

            if let role = person.role, !role.isEmpty {
                Text(role)
                    .contentFont(.footnote, design: .default)
                    .foregroundStyle(DT.Color.textSecondary)
            }
        }
        .padding(.top, DT.Spacing.md)
    }
}

private struct PersonPhotoPlaceholder: View {
    var body: some View {
        Circle()
            .fill(DT.Color.backgroundSecondary)
            .overlay(Image(systemName: "person.fill")
                .scaledFont(size: 44)
                .foregroundStyle(DT.Color.textSecondary.opacity(0.4)))
    }
}

private struct PersonSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .contentFont(.footnote, design: .default, weight: .semibold)
            .foregroundStyle(DT.Color.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DT.Spacing.pagePad)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A title Seerr can request: poster with a plus badge, name and role.
struct PersonCreditCard: View {
    let credit: SeerrPersonCredit
    /// Apple TV draws these larger, at the distance it's watched from.
    let scale: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let url = credit.posterURL {
                        RetryingAsyncImage(
                            url: url,
                            logCategory: "PersonDetailView",
                            logContext: "credit title=\(credit.title)",
                            content: { img in img.resizable().scaledToFill() },
                            placeholder: { DT.Color.backgroundSecondary }
                        )
                    } else {
                        DT.Color.backgroundSecondary
                    }
                }
                .frame(width: 110 * scale, height: 165 * scale)
                .clipShape(RoundedRectangle(cornerRadius: DT.Radius.md))

                Image(systemName: "plus.circle.fill")
                    .contentFont(.title3)
                    .foregroundStyle(.white, DT.Color.accent)
                    .background(Circle().fill(.black.opacity(0.3)))
                    .padding(6)
            }
            Text(credit.title)
                .contentFont(.caption2, design: .default, weight: .semibold)
                .foregroundStyle(DT.Color.textPrimary)
                .lineLimit(2, reservesSpace: true)
            Text(credit.role ?? "")
                .contentFont(.caption2, design: .default)
                .foregroundStyle(DT.Color.textSecondary)
                .lineLimit(1, reservesSpace: true)
        }
        .frame(width: 110 * scale)
    }
}
