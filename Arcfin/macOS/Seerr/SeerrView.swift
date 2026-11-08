// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

struct SeerrView: View {
    @State private var model = SeerrDiscoverModel()

    var body: some View {
        SeerrDiscoverPage(model: model, gridSpacing: 12)
    }
}
