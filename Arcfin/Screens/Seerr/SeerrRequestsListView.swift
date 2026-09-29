// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import SeerrAPI

/// The "view my existing requests" screen reached from Browse (Movies/Shows/Collections) —
/// same request row list Discover used to show inline, minus the search bar. `filter` narrows
/// to one media type; nil shows everything (the "Collections" entry).
struct SeerrRequestsListView: View {
    @Environment(SeerrRepository.self) private var seerrRepo

    let filter: RequestMediaType?
    let title: String

    @State private var selectedRequest: SeerrRequestItem? = nil

    private var filteredRequests: [SeerrRequestItem] {
        guard let filter else { return seerrRepo.requests }
        return seerrRepo.requests.filter { $0.mediaType == filter }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                if seerrRepo.isLoadingRequests && seerrRepo.requests.isEmpty {
                    loadingList
                } else if filteredRequests.isEmpty {
                    ContentUnavailableView(
                        "No Requests",
                        systemImage: "clock",
                        description: Text("Your media requests will appear here.")
                    )
                    .frame(height: 220)
                } else {
                    list
                }
                Spacer().frame(height: DT.Size.tabBarHeight + 16)
            }
        }
        .background(DT.Color.backgroundPrimary)
        .navigationTitle(title)
        .arcfinNavTitleLarge(title)
        .navigationDestination(item: $selectedRequest) { req in
            SeerrRequestDetailView(request: req)
        }
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
                .contextMenu {
                    Button {
                        selectedRequest = req
                    } label: {
                        Label("View Details", systemImage: "info.circle")
                    }
                    Button(role: .destructive) {
                        Task { try? await seerrRepo.cancelRequest(id: req.id) }
                    } label: {
                        Label("Remove Request", systemImage: "trash")
                    }
                }
            }
        }
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.top, 12)
    }

    private var loadingList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<6, id: \.self) { _ in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 32, height: 44)
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 140, height: 12)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white.opacity(0.06))
                            .frame(width: 90, height: 9)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12).padding(.vertical, 11)
                .frame(height: 66)
                .background(.white.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.06), lineWidth: 1))
            }
        }
        .padding(.horizontal, DT.Spacing.pagePad)
        .padding(.top, 12)
    }

    private func requestRow(_ req: SeerrRequestItem) -> some View {
        HStack(spacing: 10) {
            if let url = req.posterURL {
                AsyncImage(url: url) { phase in
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
                    if let mediaStatus = req.mediaStatus {
                        mediaStatusPill(mediaStatus)
                    }
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
            .font(.system(size: 7, weight: .bold))
            .foregroundStyle(Color(hex: hex))
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Color(hex: hex).opacity(0.15))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color(hex: hex).opacity(0.3), lineWidth: 1))
    }
}
