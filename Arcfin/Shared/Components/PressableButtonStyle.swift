// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

// Returns the label untouched otherwise — same chrome-stripping behavior as .plain — so it
// drops in wherever .buttonStyle(.plain) was load-bearing for layout, adding only the
// press-state feedback on top.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PressableLabel(configuration: configuration)
    }
}

private struct PressableLabel: View {
    let configuration: ButtonStyleConfiguration
    @State private var hovered = false

    var body: some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            // The pointer's hover feedback on the Mac.
            .brightness(hovered ? 0.05 : 0)
            .onPressableHover { hovered = $0 }
            .animation(DT.Animation.fast, value: configuration.isPressed)
            .animation(DT.Animation.fast, value: hovered)
    }
}
