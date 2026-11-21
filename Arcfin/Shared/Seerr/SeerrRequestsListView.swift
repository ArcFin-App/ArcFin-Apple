// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import SeerrAPI

/// The "view my existing requests" screen reached from Browse (Movies/Shows/Collections) —
/// same request row list Discover used to show inline, minus the search bar. `filter` narrows
/// to one media type; nil shows everything (the "Collections" entry).
struct SeerrRequestsListView: View {
    @Environment(SeerrRepository.self) private var seerrRepo

    let filter: RequestMediaType?
    let title: LocalizedStringKey

    @State private var selectedRequest: SeerrRequestItem? = nil
    @State private var statusFilter: RequestStatus? = nil
    @State private var review = SeerrRequestReview()

    private var pendingCount: Int {
        seerrRepo.requests.count { $0.status == .pending && (filter == nil || $0.mediaType == filter) }
    }

    private var filteredRequests: [SeerrRequestItem] {
        seerrRepo.requests.filter { request in
            (filter == nil || request.mediaType == filter) && (statusFilter == nil || request.status == statusFilter)
        }
    }

    private var statusFilterLabel: String {
        switch statusFilter {
        case nil: "All"
        case .pending: "Pending"
        case .approved: "Approved"
        case .declined: "Declined"
        case .failed: "Failed"
        case .completed: "Completed"
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                if seerrRepo.isLoadingRequests && seerrRepo.requests.isEmpty {
                    loadingList
                } else if filteredRequests.isEmpty {
                    ContentUnavailableView(
                        statusFilter == nil ? "No Requests" : "No \(statusFilterLabel) Requests",
                        systemImage: "clock",
                        description: Text(statusFilter == nil
                                          ? "Your media requests will appear here."
                                          : "Try a different status filter.")
                    )
                    .frame(height: 220)
                } else {
                    if seerrRepo.canManageRequests, statusFilter == nil, pendingCount > 0 {
                        pendingBanner
                    }
                    list
                }
                Spacer().frame(height: DT.Size.tabBarHeight + 16)
            }
        }
        .screenBackground()
        .navigationTitle(title)
        .arcfinNavTitleLarge(title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Picker("Status", selection: $statusFilter) {
                        Text("All").tag(RequestStatus?.none)
                        Text("Pending").tag(RequestStatus?.some(.pending))
                        Text("Approved").tag(RequestStatus?.some(.approved))
                        Text("Declined").tag(RequestStatus?.some(.declined))
                        Text("Completed").tag(RequestStatus?.some(.completed))
                        Text("Failed").tag(RequestStatus?.some(.failed))
                    }
                } label: {
                    Image(systemName: statusFilter == nil
                          ? "line.3.horizontal.decrease.circle"
                          : "line.3.horizontal.decrease.circle.fill")
                }
                .accessibilityLabel("Filter requests")
                .accessibilityValue(statusFilterLabel)
            }
        }
        .navigationDestination(item: $selectedRequest) { req in
            SeerrRequestDetailView(request: req)
        }
        .seerrRequestReview(review)
        .task {
            await seerrRepo.loadRequests()
        }
        .refreshable {
            await seerrRepo.loadRequests()
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(filteredRequests) { req in
                Button { selectedRequest = req } label: {
                    requestRow(req)
                }
                .buttonStyle(.plain)
                .contextMenu(menuItems: {
                    Button {
                        selectedRequest = req
                    } label: {
                        Label("View Details", systemImage: "info.circle")
                    }
                    SeerrRequestReviewMenu(request: req, review: review)
                    if seerrRepo.canRemove(req) {
                        Button(role: .destructive) {
                            review.removing = req
                        } label: {
                            Label("Remove Request", systemImage: "trash")
                        }
                    }
                }, preview: {
                    requestRowPreview(req)
                })
            }
        }
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.top, 12)
    }

    /// For someone who manages requests: how many are waiting, and a way to see only those.
    private var pendingBanner: some View {
        Button { withAnimation(DT.Animation.fast) { statusFilter = .pending } } label: {
            HStack(spacing: 10) {
                Image(systemName: "hourglass")
                    .foregroundStyle(DT.Color.palette("f59e0b"))
                Text(pendingCount == 1 ? "1 request is waiting for approval" : "\(pendingCount) requests are waiting for approval")
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(DT.Color.textPrimary)
                Spacer(minLength: 0)
                Text("Review")
                    .font(.system(.footnote, weight: .semibold))
                    .foregroundStyle(DT.Color.accent)
            }
            .padding(12)
            .background(DT.Color.palette("f59e0b").opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.top, 12)
    }

    private var loadingList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Self.placeholderRequests) { req in
                requestRow(req)
            }
        }
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.top, 12)
        .redacted(reason: .placeholder)
    }

    private static let placeholderRequests: [SeerrRequestItem] = (0..<6).map { i in
        SeerrRequestItem(
            id: -(i + 1),
            mediaTitle: "Loading Title",
            mediaType: .movie,
            status: .pending,
            requestedAt: .now
        )
    }

    private func requestRow(_ req: SeerrRequestItem) -> some View {
        HStack(spacing: 10) {
            if let url = req.posterURL {
                CachedAsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: posterMiniFallback
                    }
                }
                .frame(width: 32, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                posterMiniFallback
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .frame(width: 32, height: 44)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(req.mediaTitle)
                    .font(.system(.caption, design: .default, weight: .semibold))
                    .foregroundStyle(DT.Color.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(req.mediaType == .tv ? "Series" : "Movie")
                        .font(DT.Font.caption2)
                        .foregroundStyle(DT.Color.textSecondary)
                    Text("·").accessibilityHidden(true)
                        .font(DT.Font.caption2)
                        .foregroundStyle(DT.Color.textPrimary.opacity(0.2))
                    Text(req.requestedAt, style: .date)
                        .font(DT.Font.caption2)
                        .foregroundStyle(DT.Color.textSecondary)
                    requestStatusPill(req.status)
                    if let mediaStatus = req.mediaStatus {
                        mediaStatusPill(mediaStatus)
                    }
                }
                if let name = seerrRepo.requesterName(of: req) {
                    Label("Requested by \(name)", systemImage: "person")
                        .font(DT.Font.caption2)
                        .foregroundStyle(DT.Color.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12).padding(.vertical, 11)
        .background(DT.Color.textPrimary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(DT.Color.textPrimary.opacity(0.06), lineWidth: 1))
    }

    private func requestRowPreview(_ req: SeerrRequestItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if let url = req.posterURL {
                    CachedAsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFill()
                        default: posterMiniFallback
                        }
                    }
                } else {
                    posterMiniFallback
                }
            }
            .frame(width: 200, height: 300)
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.card))

            Text(req.mediaTitle)
                .font(.system(.footnote, design: .default, weight: .semibold))
                .foregroundStyle(DT.Color.textPrimary)
                .lineLimit(2)
                .frame(width: 200, alignment: .leading)
        }
        .padding(DT.Spacing.sm)
    }

    private var posterMiniFallback: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(LinearGradient(
                colors: [DT.Color.accent.opacity(0.08), Color(hex: "0B0B0C")],
                startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(DT.Color.textPrimary.opacity(0.06), lineWidth: 1))
    }

    private func requestStatusPill(_ status: RequestStatus) -> some View {
        let (label, hex): (String, String) = switch status {
        case .approved:  ("Approved", "10b981")
        case .declined:  ("Declined", "F43F5E")
        case .failed:  ("Failed", "F43F5E")
        case .completed: ("Completed", "10b981")
        case .pending:   ("Pending", "f59e0b")
        }
        return statusPillView(label: label, hex: hex)
    }

    private func mediaStatusPill(_ status: SeerrAvailabilityStatus) -> some View {
        statusPillView(label: status.label, hex: status.colorHex)
    }

    private func statusPillView(label: String, hex: String) -> some View {
        StatusPill(label: label, color: DT.Color.palette(hex))
    }
}
