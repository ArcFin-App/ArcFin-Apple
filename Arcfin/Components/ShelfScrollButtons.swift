// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

#if os(macOS)
/// A mouse wheel only scrolls up and down, so a sideways shelf had no way along it without a
/// trackpad. While the pointer is over the shelf, arrows at either end page through it.
private struct ShelfScrollButtons: ViewModifier {
    @State private var position = ScrollPosition(edge: .leading)
    @State private var offset: CGFloat = 0
    @State private var maxOffset: CGFloat = 0
    @State private var pageWidth: CGFloat = 0
    @State private var hovering = false

    private struct Metrics: Equatable {
        let offset: CGFloat
        let maxOffset: CGFloat
        let pageWidth: CGFloat
    }

    func body(content: Content) -> some View {
        content
            .scrollPosition($position)
            .onScrollGeometryChange(for: Metrics.self) { geometry in
                Metrics(offset: geometry.contentOffset.x,
                        maxOffset: max(geometry.contentSize.width - geometry.containerSize.width, 0),
                        pageWidth: geometry.containerSize.width)
            } action: { _, metrics in
                offset = metrics.offset
                maxOffset = metrics.maxOffset
                pageWidth = metrics.pageWidth
            }
            .overlay(alignment: .leading) {
                if hovering, offset > 1 { arrow("chevron.left", label: "Scroll back") { page(by: -1) } }
            }
            .overlay(alignment: .trailing) {
                if hovering, offset < maxOffset - 1 { arrow("chevron.right", label: "Scroll forward") { page(by: 1) } }
            }
            .animation(DT.Animation.fast, value: hovering)
            .onHover { hovering = $0 }
    }

    private func page(by direction: CGFloat) {
        let target = min(max(offset + direction * pageWidth * 0.8, 0), maxOffset)
        withAnimation(DT.Animation.motion(.easeInOut(duration: 0.35))) { position.scrollTo(x: target) }
    }

    private func arrow(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(.title3, weight: .semibold))
                .frame(width: 36, height: 36)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .padding(.horizontal, 8)
        .transition(.opacity)
        .accessibilityLabel(label)
    }
}
#endif

extension View {
    /// Paging arrows for a horizontal shelf on the Mac; nothing elsewhere.
    @ViewBuilder
    func shelfScrollButtons() -> some View {
        #if os(macOS)
        modifier(ShelfScrollButtons())
        #else
        self
        #endif
    }
}
