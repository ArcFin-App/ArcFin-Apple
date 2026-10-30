// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// The A–Z index along a library's trailing edge, like Contacts: tap a letter or drag along it.
/// Letters near the finger or pointer swell out to the leading side so the one under it is easy
/// to read; on iPhone and iPad that letter also shows large in the middle of the screen.
struct LetterIndexBar: View {
    var onSelect: (String) -> Void

    @State private var current: String?
    @State private var pointerY: CGFloat?
    @State private var height: CGFloat = 0
    @State private var accessibilityIndex = 0

    private let letters = LibraryLetterIndex.letters
    private let inset: CGFloat = 6

    var body: some View {
        bar
            .padding(.trailing, 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .overlay {
                if let pointed {
                    Text(verbatim: pointed)
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .foregroundStyle(DT.Color.textPrimary)
                        .frame(width: 120, height: 120)
                        .glassEffect(.regular, in: .rect(cornerRadius: DT.Radius.sheet))
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .animation(DT.Animation.motion(.spring(response: 0.2, dampingFraction: 0.85)), value: pointerY == nil)
    }

    private var bar: some View {
        VStack(spacing: 0) {
            ForEach(Array(letters.enumerated()), id: \.element) { index, letter in
                letterCell(letter, swell: magnification(at: index))
            }
        }
        .padding(.vertical, inset)
        .background(Capsule().fill(.regularMaterial).opacity(pointerY == nil ? 0 : 1))
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { drag(to: $0.location.y) }
                .onEnded { _ in
                    current = nil
                    pointerY = nil
                }
        )
        .onContinuousHover { phase in
            guard current == nil else { return }
            switch phase {
            case .active(let location): pointerY = location.y
            case .ended: pointerY = nil
            }
        }
        .sensoryFeedback(.selection, trigger: current) { _, new in new != nil }
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

    private func letterCell(_ letter: String, swell: CGFloat) -> some View {
        let isPointed = pointed == letter
        return Text(verbatim: letter)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .foregroundStyle(isPointed ? DT.Color.onAccent : DT.Color.accent)
            .frame(width: 18, height: 18)
            .background(Circle().fill(DT.Color.accent).opacity(isPointed ? 1 : 0))
            .scaleEffect(1 + swell * 1.2)
            .offset(x: -swell * 26)
            .frame(width: 22)
            .frame(maxHeight: .infinity)
    }

    private var slot: CGFloat { max(height - inset * 2, 1) / CGFloat(letters.count) }

    private var pointed: String? {
        guard let pointerY else { return nil }
        return letters[index(at: pointerY)]
    }

    private func index(at y: CGFloat) -> Int {
        min(max(Int((y - inset) / slot), 0), letters.count - 1)
    }

    /// 1 for the letter under the pointer, easing to 0 three letters away.
    private func magnification(at index: Int) -> CGFloat {
        guard let pointerY else { return 0 }
        let center = inset + slot * (CGFloat(index) + 0.5)
        return max(0, 1 - abs(pointerY - center) / (slot * 3))
    }

    private func drag(to y: CGFloat) {
        pointerY = min(max(y, 0), height)
        let letter = letters[index(at: y)]
        guard letter != current else { return }
        current = letter
        onSelect(letter)
    }
}
