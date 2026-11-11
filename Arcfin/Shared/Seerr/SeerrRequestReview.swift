// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import SeerrAPI

/// Approving and declining pending requests, for a Seerr user who manages them. Declining
/// asks first; a failure is shown as an alert.
@MainActor @Observable
final class SeerrRequestReview {
    var declining: SeerrRequestItem?
    var error: String?
    private(set) var inProgress: Set<Int> = []

    func approve(_ request: SeerrRequestItem, seerrRepo: SeerrRepository) {
        Task { await set(request, approved: true, seerrRepo: seerrRepo) }
    }

    func decline(_ request: SeerrRequestItem, seerrRepo: SeerrRepository) {
        Task { await set(request, approved: false, seerrRepo: seerrRepo) }
    }

    private func set(_ request: SeerrRequestItem, approved: Bool, seerrRepo: SeerrRepository) async {
        inProgress.insert(request.id)
        defer { inProgress.remove(request.id) }
        do {
            try await seerrRepo.setRequestApproved(request, approved: approved)
            HapticManager.impact(.medium)
        } catch {
            self.error = approved
                ? String(localized: "Couldn't approve “\(request.mediaTitle)”. \(error.localizedDescription)")
                : String(localized: "Couldn't decline “\(request.mediaTitle)”. \(error.localizedDescription)")
        }
    }
}

extension SeerrRepository {
    /// Approve and Decline apply: the user manages requests and this one is waiting.
    func canReview(_ request: SeerrRequestItem) -> Bool {
        canManageRequests && request.status == .pending
    }

    /// "Requested by" is worth saying: the list holds other people's requests too.
    func requesterName(of request: SeerrRequestItem) -> String? {
        guard canManageRequests, let name = request.requestedByName, !name.isEmpty,
              request.requestedByID != currentUser?.id else { return nil }
        return name
    }
}

/// Approve and Decline, for a request's context menu.
struct SeerrRequestReviewMenu: View {
    let request: SeerrRequestItem
    let review: SeerrRequestReview

    @Environment(SeerrRepository.self) private var seerrRepo

    var body: some View {
        if seerrRepo.canReview(request) {
            Button { review.approve(request, seerrRepo: seerrRepo) } label: {
                Label("Approve", systemImage: "checkmark.circle")
            }
            Button(role: .destructive) { review.declining = request } label: {
                Label("Decline", systemImage: "xmark.circle")
            }
        }
    }
}

/// Approve and Decline as buttons, for a request's own page.
struct SeerrRequestReviewButtons: View {
    let request: SeerrRequestItem
    let review: SeerrRequestReview

    @Environment(SeerrRepository.self) private var seerrRepo

    var body: some View {
        if seerrRepo.canReview(request) {
            let busy = review.inProgress.contains(request.id)
            HStack(spacing: 12) {
                Button { review.approve(request, seerrRepo: seerrRepo) } label: {
                    Label("Approve", systemImage: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(DT.Color.palette("10b981"))
                Button(role: .destructive) { review.declining = request } label: {
                    Label("Decline", systemImage: "xmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(DT.Color.palette("F43F5E"))
            }
            .font(.system(.footnote, weight: .semibold))
            .controlSize(.large)
            .disabled(busy)
            .overlay { if busy { ProgressView() } }
        }
    }
}

extension View {
    /// The decline confirmation and the error alert for `review`.
    func seerrRequestReview(_ review: SeerrRequestReview) -> some View {
        modifier(SeerrRequestReviewPresentations(review: review))
    }
}

private struct SeerrRequestReviewPresentations: ViewModifier {
    @Bindable var review: SeerrRequestReview
    @Environment(SeerrRepository.self) private var seerrRepo

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                review.declining.map { String(localized: "Decline “\($0.mediaTitle)”?") } ?? "",
                isPresented: Binding(get: { review.declining != nil }, set: { if !$0 { review.declining = nil } }),
                titleVisibility: .visible,
                presenting: review.declining
            ) { request in
                Button("Decline Request", role: .destructive) { review.decline(request, seerrRepo: seerrRepo) }
                Button("Cancel", role: .cancel) {}
            } message: { request in
                if let name = request.requestedByName, !name.isEmpty {
                    Text("\(name) will see that their request was declined.")
                }
            }
            .alert("Requests", isPresented: Binding(get: { review.error != nil }, set: { if !$0 { review.error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(review.error ?? "")
            }
    }
}
