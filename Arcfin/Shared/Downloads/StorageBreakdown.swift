// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import Persistence

/// What Arcfin's downloads take, split into shows and movies as one bar with a legend, and
/// what's free on the device. Under it, Smart Downloads against its limit.
struct StorageBreakdown: View {
    let items: [DownloadedItem]
    let smartUsedBytes: Int64
    let freeBytes: Int64?

    @AppStorage("smartDownloadsEnabled") private var smartEnabled = false
    @AppStorage("smartDownloadsStorageBudgetGB") private var smartBudgetGB = 10

    static let showsColor = DT.Color.accent
    static let moviesColor = DT.Color.palette("60A5FA")
    static let smartColor = DT.Color.palette("F59E0B")

    private struct Segment: Identifiable {
        let id: String
        let label: String
        let bytes: Int64
        let color: Color
    }

    private var showsBytes: Int64 { StorageManagement.size(of: items.filter { $0.seriesId != nil }) }
    private var moviesBytes: Int64 { StorageManagement.size(of: items.filter { $0.seriesId == nil }) }
    private var arcfinBytes: Int64 { showsBytes + moviesBytes }

    private var segments: [Segment] {
        [
            Segment(id: "shows", label: String(localized: "Shows"), bytes: showsBytes, color: Self.showsColor),
            Segment(id: "movies", label: String(localized: "Movies"), bytes: moviesBytes, color: Self.moviesColor),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            bar
            legend
            if smartEnabled { smartGauge }
        }
        .accessibilityElement(children: .combine)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(StorageManagement.formatted(arcfinBytes))
                .font(.system(.title2, weight: .bold))
                .foregroundStyle(DT.Color.textPrimary)
                .contentTransition(.numericText())
            Text("used by Arcfin")
                .font(.system(.subheadline))
                .foregroundStyle(DT.Color.textSecondary)
            Spacer(minLength: 8)
            if let freeBytes {
                Text("\(StorageManagement.formatted(freeBytes)) free on device")
                    .font(.system(.caption, weight: .medium))
                    .foregroundStyle(DT.Color.textSecondary)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    /// Arcfin's own space, shows against movies. A part that isn't empty keeps a sliver.
    private var bar: some View {
        let total = Double(max(arcfinBytes, 1))
        let visible = segments.filter { $0.bytes > 0 }
        return GeometryReader { geo in
            let spacing: CGFloat = 2
            let width = geo.size.width - spacing * CGFloat(max(visible.count - 1, 0))
            HStack(spacing: spacing) {
                ForEach(visible) { segment in
                    Rectangle()
                        .fill(segment.color)
                        .frame(width: max(width * Double(segment.bytes) / total, 4))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DT.Color.textPrimary.opacity(0.1))
            .clipShape(Capsule())
        }
        .frame(height: 12)
        .accessibilityHidden(true)
    }

    private var legend: some View {
        HStack(spacing: 18) {
            ForEach(segments) { segment in
                legendItem(segment.label, bytes: segment.bytes, color: segment.color)
            }
        }
    }

    private func legendItem(_ label: String, bytes: Int64, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .overlay(Circle().stroke(DT.Color.textPrimary.opacity(0.15), lineWidth: 0.5))
            Text(label)
                .font(.system(.caption))
                .foregroundStyle(DT.Color.textSecondary)
            Text(StorageManagement.formatted(bytes))
                .font(.system(.caption, weight: .semibold))
                .foregroundStyle(DT.Color.textPrimary)
                .monospacedDigit()
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private var smartGauge: some View {
        let limit = Int64(smartBudgetGB) * 1_000_000_000
        let share = limit > 0 ? min(Double(smartUsedBytes) / Double(limit), 1) : 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Label("Smart Downloads", systemImage: "sparkles")
                    .font(.system(.caption, weight: .semibold))
                    .foregroundStyle(DT.Color.textPrimary)
                Spacer(minLength: 8)
                Text("\(StorageManagement.formatted(smartUsedBytes)) of \(StorageManagement.formatted(limit)) · \(StorageManagement.formatted(max(limit - smartUsedBytes, 0))) left")
                    .font(.system(.caption))
                    .foregroundStyle(DT.Color.textSecondary)
                    .monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DT.Color.textPrimary.opacity(0.1))
                    Capsule()
                        .fill(Self.smartColor)
                        .frame(width: max(geo.size.width * share, smartUsedBytes > 0 ? 4 : 0))
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
        }
        .padding(.top, 10)
        .overlay(alignment: .top) {
            Rectangle().fill(DT.Color.textPrimary.opacity(0.08)).frame(height: 1)
        }
    }
}
