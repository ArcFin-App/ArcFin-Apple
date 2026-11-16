// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// On Apple TV the text turns dark on the focused row's light platter, like the other
/// Settings rows.
struct LicenseRow: View {
    let name: String
    let license: String
    let note: String?
    @Environment(\.isFocused) private var isFocused

    private var secondary: Color {
        isFocused ? Color.black.opacity(0.65) : DT.Color.textSecondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name)
                    .font(.system(.footnote, design: .default, weight: .semibold))
                    .foregroundStyle(isFocused ? Color.black : DT.Color.textPrimary)
                Spacer()
                Text(license)
                    .font(.system(.caption, design: .default, weight: .medium))
                    .foregroundStyle(secondary)
            }
            if let note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(secondary)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Where to get the exact version's source. Apple TV has no browser, so the address is shown
/// to type in elsewhere.
struct LicenseSourceRow: View {
    let title: LocalizedStringKey
    let url: URL

    var body: some View {
        LabeledContent(title) {
            Text(verbatim: url.absoluteString)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        }
        .tvReadOnlyRow()
    }
}
