// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

enum LibraryLetterIndex {
    /// "#" covers titles that start with a number or symbol, which sort before A.
    static let letters = ["#"] + (UInt8(ascii: "A")...UInt8(ascii: "Z")).map { String(UnicodeScalar($0)) }
}

#if !os(tvOS)
/// The A–Z index along a library's trailing edge, like Contacts: tap a letter or drag along it.
struct LetterIndexBar: View {
    var onSelect: (String) -> Void

    @State private var current: String?
    @State private var height: CGFloat = 0
    @State private var accessibilityIndex = 0

    private let letters = LibraryLetterIndex.letters

    var body: some View {
        VStack(spacing: 0) {
            ForEach(letters, id: \.self) { letter in
                Text(verbatim: letter)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(current == letter ? DT.Color.textPrimary : DT.Color.accent)
                    .frame(width: 22)
                    .frame(maxHeight: 16)
            }
        }
        .padding(.vertical, 6)
        .background(Capsule().fill(.regularMaterial).opacity(current == nil ? 0 : 1))
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { select(at: $0.location.y) }
                .onEnded { _ in current = nil }
        )
        .sensoryFeedback(.selection, trigger: current) { _, new in new != nil }
        .animation(.easeOut(duration: 0.15), value: current == nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Jump to Letter")
        .accessibilityValue(Text(verbatim: letters[accessibilityIndex]))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: accessibilityIndex = min(accessibilityIndex + 1, letters.count - 1)
            case .decrement: accessibilityIndex = max(accessibilityIndex - 1, 0)
            @unknown default: return
            }
            onSelect(letters[accessibilityIndex])
        }
    }

    private func select(at y: CGFloat) {
        let usable = max(height - 12, 1)
        let index = min(max(Int((y - 6) / usable * CGFloat(letters.count)), 0), letters.count - 1)
        let letter = letters[index]
        guard letter != current else { return }
        current = letter
        onSelect(letter)
    }
}
#endif
