// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import JellyfinAPI

/// A programme from the guide or a channel: what it is, when it's on, and watch or record it.
struct LiveTVProgramSheet: View {
    let model: LiveTVModel
    let program: LiveTVProgram

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LiveTVProgramDetails(model: model, program: program) { dismiss() }
                    .padding(DT.Spacing.pagePad)
            }
            .screenBackground()
            .navigationTitle(LiveTVProgramDetails.title(for: program, in: model))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
