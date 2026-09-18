import SwiftUI
import SeerrAPI

struct SeerrRequestConfirmSheet: View {
    @Environment(SeerrRepository.self) private var seerrRepo

    let item: SeerrItem
    @Binding var requestingItem: SeerrItem?

    var body: some View {
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
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, DT.Spacing.pagePad)
            .padding(.top, DT.Spacing.lg)
            .padding(.bottom, DT.Spacing.md)

            Text("Send a request to your Seerr server. You'll be notified when it becomes available.")
                .font(DT.Font.caption)
                .foregroundStyle(DT.Color.textSecondary)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, DT.Spacing.pagePad)
                .padding(.bottom, DT.Spacing.lg)

            Button {
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
}
