// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// A letter in the Apple TV index row: fills with the accent and grows while focused.
struct TVLetterLabel: View {
    let letter: String
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        Text(verbatim: letter)
            .font(.headline)
            .foregroundStyle(isFocused ? DT.Color.onAccent : DT.Color.textPrimary)
            .frame(width: 64, height: 64)
            .background(Circle().fill(isFocused ? DT.Color.accent : DT.Color.textPrimary.opacity(0.06)))
            .scaleEffect(isFocused ? 1.35 : 1.0)
            .animation(DT.Animation.motion(.spring(response: 0.18, dampingFraction: 0.8)), value: isFocused)
    }
}
