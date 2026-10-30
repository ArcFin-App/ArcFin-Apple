// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// No trailer button on Apple TV: the YouTube player isn't built for it.
struct SeerrTrailerButton: View {
    let videoID: String
    let title: String

    var body: some View {
        EmptyView()
    }
}
