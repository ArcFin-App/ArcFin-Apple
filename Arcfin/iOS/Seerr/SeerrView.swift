// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

struct SeerrView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var model = SeerrDiscoverModel()

    /// Two across fits a phone; on a wider iPad two stretched each poster to half the
    /// screen, so it fills the width with posters of a phone-like size instead.
    private var discoverColumns: [GridItem] {
        if horizontalSizeClass == .regular {
            return [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 8)]
        }
        return [.init(.flexible()), .init(.flexible())]
    }

    var body: some View {
        SeerrDiscoverPage(model: model, discoverColumns: discoverColumns, gridSpacing: 8)
    }
}
