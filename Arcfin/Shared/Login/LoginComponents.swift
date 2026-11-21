// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

// Pieces shared by the server-address and sign-in screens: system type sizes, full-height
// fields, grouped rows and one prominent glass button, so the two read like the rest of
// the app rather than a separate marketing page.

/// The app icon, a title and a sentence of explanation.
struct LoginHeader: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    var body: some View {
        VStack(spacing: 14) {
            Image("ArcfinLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 72 * 0.225, style: .continuous))
                .shadow(color: .black.opacity(0.45), radius: 14, y: 6)
                .accessibilityHidden(true)
            Text(title)
                .font(.title.bold())
                .foregroundStyle(DT.Color.textPrimary)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.callout)
                .foregroundStyle(DT.Color.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }
}

enum LoginFieldKind {
    case url, username, password
}

/// A labelled text field at body size with room to tap, an optional error underneath, and
/// the content type set so Passwords and AutoFill can help.
struct LoginTextField: View {
    let title: LocalizedStringKey
    let prompt: Text
    @Binding var text: String
    var kind: LoginFieldKind = .username
    var isValid = false
    var error: String?
    var onSubmit: () -> Void = {}
    /// For a form that moves focus here itself, as Next on the username does.
    var isFocused: FocusState<Bool>.Binding? = nil

    @State private var revealsPassword = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(DT.Color.textSecondary)
            HStack(spacing: 10) {
                focusableField
                    .font(.body)
                    .foregroundStyle(DT.Color.textPrimary)
                    .autocorrectionDisabled()
                    .loginFieldInput(kind)
                    .submitLabel(kind == .password || kind == .url ? .go : .next)
                    .onSubmit(onSubmit)
                if kind == .password {
                    Button { revealsPassword.toggle() } label: {
                        Image(systemName: revealsPassword ? "eye.slash" : "eye")
                            .foregroundStyle(DT.Color.textSecondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .arcfinPlainButton(cornerRadius: 22)
                    .accessibilityLabel(revealsPassword ? "Hide password" : "Show password")
                }
                if isValid {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityLabel("Connected")
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .background(DT.Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(error != nil ? Color.red.opacity(0.6) : DT.Color.textPrimary.opacity(0.08), lineWidth: 1)
            )
            .animation(DT.Animation.fast, value: isValid)

            if let error {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var focusableField: some View {
        if let isFocused { field.focused(isFocused) } else { field }
    }

    @ViewBuilder
    private var field: some View {
        if kind == .password && !revealsPassword {
            SecureField(text: $text, prompt: prompt) { Text(title) }
        } else {
            TextField(text: $text, prompt: prompt) { Text(title) }
        }
    }
}

/// Rows in one rounded group, divided like a grouped list.
struct LoginRowGroup<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(DT.Color.textSecondary)
            VStack(spacing: 0) {
                Group(subviews: content) { subviews in
                    ForEach(Array(subviews.enumerated()), id: \.offset) { index, subview in
                        if index > 0 {
                            Divider().overlay(DT.Color.textPrimary.opacity(0.06)).padding(.leading, 56)
                        }
                        subview
                    }
                }
            }
            .background(DT.Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

struct LoginRow: View {
    let systemImage: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.body)
                    .foregroundStyle(DT.Color.accent)
                    .frame(width: 32, height: 32)
                    .background(DT.Color.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(DT.Color.textPrimary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(DT.Color.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(DT.Color.textSecondary.opacity(0.6))
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 60)
            .contentShape(Rectangle())
        }
        .arcfinPlainButton(cornerRadius: 14, prominent: false)
    }
}

/// The screen's one main action, pinned above the keyboard.
struct LoginPrimaryButton: View {
    let title: Text
    var busyTitle: Text?
    var isBusy = false
    var isDisabled = false
    let action: () -> Void

    init(title: LocalizedStringKey, busyTitle: LocalizedStringKey? = nil, isBusy: Bool = false,
         isDisabled: Bool = false, action: @escaping () -> Void) {
        self.title = Text(title)
        self.busyTitle = busyTitle.map { Text($0) }
        self.isBusy = isBusy
        self.isDisabled = isDisabled
        self.action = action
    }

    /// Text that's already localized, shown as is.
    @_disfavoredOverload
    init(title: String, isBusy: Bool = false, isDisabled: Bool = false, action: @escaping () -> Void) {
        self.title = Text(verbatim: title)
        self.isBusy = isBusy
        self.isDisabled = isDisabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isBusy { ProgressView().tint(DT.Color.onAccent) }
                (isBusy ? (busyTitle ?? title) : title)
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 30)
        }
        .buttonStyle(.glassProminent)
        .tint(DT.Color.accent)
        .foregroundStyle(DT.Color.onAccent)
        .controlSize(.large)
        .disabled(isBusy || isDisabled)
    }
}

/// A plain leading Back button for screens shown outside a navigation stack.
struct LoginBackButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left").fontWeight(.semibold)
                Text(title).lineLimit(1)
            }
            .font(.body)
            .foregroundStyle(DT.Color.accent)
            .frame(minHeight: 44)
            .loginBackButtonPadding()
        }
        .arcfinPlainButton(cornerRadius: DT.Radius.pill, prominent: false)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    /// Scrolling content in a readable column, with `bottom` pinned above the keyboard.
    func loginLayout<Bottom: View>(@ViewBuilder bottom: () -> Bottom) -> some View {
        ScrollView {
            self
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 24)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .screenBackground()
        .safeAreaInset(edge: .bottom) {
            bottom()
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
        }
    }
}

/// Apple TV's sign-in pages: what to do on the left, and the code or fields to do it with on
/// the right, across the whole screen. The right column scrolls when it's long.
struct LoginSplitPage<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 96) {
            // Each column is its own focus area, so left and right on the remote move between
            // them from any height, rather than only where a button happens to line up.
            VStack(alignment: .leading, spacing: 36) { leading }
                .frame(maxWidth: .infinity, alignment: .leading)
                .loginFocusSection()
            ScrollView {
                VStack(spacing: 28) { trailing }
                    .padding(.vertical, 40)
                    .frame(maxWidth: .infinity)
            }
            .scrollClipDisabled()
            .frame(maxWidth: .infinity)
            .loginFocusSection()
        }
        .padding(.horizontal, 96)
        .padding(.vertical, 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
    }
}

/// The left column's heading: the logo, a title and what this page is for.
struct LoginSplitHeader: View {
    let title: LocalizedStringKey
    let message: Text

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image("ArcfinLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 72 * 0.225, style: .continuous))
                .accessibilityHidden(true)
            Text(title)
                .font(.title.bold())
                .foregroundStyle(DT.Color.textPrimary)
            message
                .font(.callout)
                .foregroundStyle(DT.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
