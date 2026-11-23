// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// A letter in the Apple TV A–Z column: fills with the accent and grows while focused.
struct TVLetterLabel: View {
    let letter: String
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Text(verbatim: letter)
            .font(.caption.weight(.semibold))
            .foregroundStyle(isFocused ? DT.Color.onAccent : DT.Color.accent)
            .frame(width: 32, height: 32)
            .background(Circle().fill(DT.Color.accent).opacity(isFocused ? 1 : 0))
            .scaleEffect(isFocused ? 1.5 : 1.0)
            .frame(width: 48)
            .animation(DT.Animation.motion(.spring(response: 0.18, dampingFraction: 0.8)), value: isFocused)
    }
}
