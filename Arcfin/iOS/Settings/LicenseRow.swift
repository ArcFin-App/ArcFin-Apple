// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

struct LicenseRow: View {
    let name: String
    let license: String
    let note: String?

    private var secondary: Color {
        DT.Color.textSecondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name)
                    .font(.system(.footnote, design: .default, weight: .semibold))
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
