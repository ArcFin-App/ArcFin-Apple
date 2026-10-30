// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

extension View {
    /// Asks to confirm with a confirmation dialog here; Apple TV uses an alert, which keeps focus on the prompt.
    func confirmationPrompt<T, A: View, M: View>(_ title: Text, isPresented: Binding<Bool>, presenting data: T?,
                                                 @ViewBuilder actions: @escaping (T) -> A,
                                                 @ViewBuilder message: @escaping (T) -> M) -> some View {
        confirmationDialog(title, isPresented: isPresented, titleVisibility: .visible,
                           presenting: data, actions: actions, message: message)
    }
}
