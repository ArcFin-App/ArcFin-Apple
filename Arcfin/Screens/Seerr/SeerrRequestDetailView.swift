import SwiftUI
import SeerrAPI

struct SeerrRequestDetailView: View {
    let request: SeerrRequestItem

    @Environment(SeerrRepository.self) private var seerrRepo
    @Environment(\.dismiss) private var dismiss

    @State private var isCancelling = false
    @State private var errorMessage: String?
    @State private var showCancelConfirm = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                backdrop

                VStack(alignment: .leading, spacing: DT.Spacing.md) {
                    HStack(spacing: 8) {
                        Text(request.mediaType == .tv ? "Series" : "Movie")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DT.Color.textSecondary)
                        Text("·")
                            .foregroundStyle(.white.opacity(0.2))
                        Text(request.requestedAt, style: .date)
                            .font(.system(size: 11))
                            .foregroundStyle(DT.Color.textSecondary)
                    }

                    statusRow

                    if let error = errorMessage {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundStyle(Color(hex: "EF4444"))
                    }

                    Button(role: .destructive) {
                        showCancelConfirm = true
                    } label: {
                        HStack {
                            if isCancelling {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "trash")
                            }
                            Text("Remove Request")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(hex: "EF4444").opacity(0.85))
                        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.lg))
                    }
                    .disabled(isCancelling)
                    .padding(.top, DT.Spacing.sm)
                }
                .padding(DT.Spacing.pagePad)
            }
        }
        .background(DT.Color.backgroundPrimary)
        .ignoresSafeArea(edges: .top)
        .navigationTitle(request.mediaTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .confirmationDialog(
            "Remove this request?",
            isPresented: $showCancelConfirm,
            titleVisibility: .visible
        ) {
            Button("Remove Request", role: .destructive) { cancel() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var backdrop: some View {
        ZStack(alignment: .bottomLeading) {
            if let url = request.backdropURL ?? request.posterURL {
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
            Text(request.mediaTitle)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .padding(DT.Spacing.pagePad)
                .shadow(color: .black.opacity(0.6), radius: 6)
        }
        .frame(height: 220)
    }

    private var statusRow: some View {
        HStack {
            Text("Status")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DT.Color.textPrimary)
            Spacer()
            statusPill
        }
        .padding(12)
        .background(.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.md))
    }

    private var statusPill: some View {
        let (label, hex): (String, String) = switch request.status {
        case .approved:  ("Approved", "10b981")
        case .available: ("Available", "10b981")
        case .declined:  ("Declined", "EF4444")
        case .pending:   ("Pending", "f59e0b")
        }
        return Text(label)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Color(hex: hex))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Color(hex: hex).opacity(0.15))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color(hex: hex).opacity(0.3), lineWidth: 1))
    }

    private func cancel() {
        isCancelling = true
        errorMessage = nil
        Task {
            do {
                try await seerrRepo.cancelRequest(id: request.id)
                dismiss()
            } catch {
                errorMessage = "Couldn't remove request: \(error.localizedDescription)"
                isCancelling = false
            }
        }
    }
}
