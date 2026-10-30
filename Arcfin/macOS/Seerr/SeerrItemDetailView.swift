// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import SeerrAPI

struct SeerrItemDetailView: View {
    @State private var model: SeerrItemDetailModel

    init(item: SeerrItem) {
        _model = State(initialValue: SeerrItemDetailModel(item: item))
    }

    var body: some View {
        SeerrItemDetailContent(model: model)
    }
}
