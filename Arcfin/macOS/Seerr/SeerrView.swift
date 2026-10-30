// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

struct SeerrView: View {
    @State private var model = SeerrDiscoverModel()

    private let discoverColumns = [GridItem(.adaptive(minimum: 160, maximum: 240), spacing: 12)]

    var body: some View {
        SeerrDiscoverPage(model: model, discoverColumns: discoverColumns, gridSpacing: 12)
    }
}
