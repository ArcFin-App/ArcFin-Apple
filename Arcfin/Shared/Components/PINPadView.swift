// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

struct PINPadView: View {
    let title: String
    var subtitle: String? = nil
    /// The PIN's digits: entry completes once this many are typed.
    var pinLength: Int = 4
    /// For a new PIN of any length in this range: a Done key finishes it once it's long enough.
    var lengths: ClosedRange<Int>? = nil
    var errorMessage: String? = nil
    // Increment to trigger a shake + digit reset
    var resetToken: Int = 0
    var onCancel: (() -> Void)? = nil
    var onSignOut: (() -> Void)? = nil
    var onComplete: (String) -> Void

    @State private var digits: [Int] = []
    @State private var shakeOffset: CGFloat = 0

    private let keySize = PINPadView.keySize

    private var maxLength: Int { lengths?.upperBound ?? pinLength }
    private var choosesLength: Bool { (lengths?.count ?? 1) > 1 }
    private var dotCount: Int { choosesLength ? max(lengths?.lowerBound ?? pinLength, digits.count) : maxLength }

    var body: some View {
        ZStack {
            DT.Color.backgroundPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                // Cancel row
                if onCancel != nil || onSignOut != nil {
                    HStack {
                        if let onCancel {
                            Button("Cancel", action: onCancel)
                                .font(.system(.callout, design: .default))
                                .foregroundStyle(DT.Color.accent)
                                .pinPadCancelStyle()
                        }
                        Spacer()
                        if let onSignOut {
                            Button("Sign Out", role: .destructive, action: onSignOut)
                                .font(.system(.callout, design: .default))
                                .foregroundStyle(DT.Color.accent)
                                .pinPadCancelStyle()
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                }

                Spacer()

                // Title + dots
                VStack(spacing: 20) {
                    Text(title)
                        .font(.system(.title, design: .default, weight: .bold))
                        .foregroundStyle(DT.Color.textPrimary)
                        .multilineTextAlignment(.center)

                    if let sub = subtitle {
                        Text(sub)
                            .font(.system(.footnote, design: .default))
                            .foregroundStyle(DT.Color.textSecondary)
                    }

                    HStack(spacing: 22) {
                        ForEach(0..<dotCount, id: \.self) { i in
                            Circle()
                                .fill(i < digits.count ? DT.Color.accent : Color.clear)
                                .overlay(
                                    Circle()
                                        .stroke(
                                            i < digits.count
                                                ? DT.Color.accent
                                                : DT.Color.textSecondary.opacity(0.35),
                                            lineWidth: 1.5
                                        )
                                )
                                .frame(width: 14, height: 14)
                                .animation(DT.Animation.motion(.spring(response: 0.15, dampingFraction: 0.7)), value: digits.count)
                        }
                    }
                    .offset(x: shakeOffset)

                    if let err = errorMessage {
                        Text(err)
                            .font(.system(.footnote, design: .default))
                            .foregroundStyle(.red)
                            .transition(.opacity.combined(with: .scale))
                    }
                }
                .padding(.horizontal, 32)

                Spacer()

                // Number pad
                VStack(spacing: 14) {
                    ForEach([[1,2,3],[4,5,6],[7,8,9]], id: \.self) { row in
                        HStack(spacing: 20) {
                            ForEach(row, id: \.self) { num in
                                padButton(label: "\(num)") { append(num) }
                            }
                        }
                    }
                    HStack(spacing: 20) {
                        if choosesLength {
                            Button { finish() } label: {
                                PadKey(size: keySize, filled: false) {
                                    Image(systemName: "checkmark")
                                        .font(.system(.title3, weight: .medium))
                                        .foregroundStyle(canFinish ? DT.Color.accent : DT.Color.textSecondary.opacity(0.3))
                                }
                            }
                            .accessibilityLabel("Done")
                            .modifier(PadButtonStyle())
                            .disabled(!canFinish)
                        } else {
                            Color.clear.frame(width: keySize, height: keySize)
                        }
                        padButton(label: "0") { append(0) }
                        Button { removeLast() } label: {
                            PadKey(size: keySize, filled: false) {
                                Image(systemName: "delete.left")
                                    .font(.system(.title3, weight: .light))
                                    .foregroundStyle(digits.isEmpty ? DT.Color.textSecondary.opacity(0.3) : DT.Color.textPrimary)
                            }
                        }
                        .accessibilityLabel("Delete")
                        .modifier(PadButtonStyle())
                        .disabled(digits.isEmpty)
                    }
                }
                // Cancel sits at the top left, so the remote finds nothing straight below it
                // without a section around the keys.
                .tvFocusSection()
                .padding(.bottom, 52)
            }
        }
        .onChange(of: resetToken) { _, _ in triggerShake() }
        .tvExitCommand { onCancel?() }
        .animation(DT.Animation.fast, value: errorMessage)
    }

    // MARK: - Pad button

    private func padButton(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            PadKey(size: keySize) {
                Text(label)
                    .font(.system(.title, design: .rounded, weight: .light))
                    .foregroundStyle(DT.Color.textPrimary)
            }
        }
        .modifier(PadButtonStyle())
    }

    // MARK: - Actions

    private var canFinish: Bool { lengths.map { $0.contains(digits.count) } ?? false }

    private func append(_ digit: Int) {
        guard digits.count < maxLength else { return }
        HapticManager.impact(.light)
        digits.append(digit)
        if digits.count == maxLength { finish() }
    }

    private func finish() {
        let pin = digits.map { "\($0)" }.joined()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            onComplete(pin)
        }
    }

    private func removeLast() {
        guard !digits.isEmpty else { return }
        HapticManager.impact(.light)
        digits.removeLast()
    }

    private func triggerShake() {
        HapticManager.error()
        digits = []
        let duration = 0.07
        withAnimation(DT.Animation.motion(.easeInOut(duration: duration))) { shakeOffset = -10 }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            withAnimation(DT.Animation.motion(.easeInOut(duration: duration))) { shakeOffset = 10 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration * 2) {
            withAnimation(DT.Animation.motion(.easeInOut(duration: duration))) { shakeOffset = -8 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration * 3) {
            withAnimation(DT.Animation.motion(.spring(response: 0.2))) { shakeOffset = 0 }
        }
    }
}

/// A key of the pad; lights up under the tvOS focus.
private struct PadKey<Content: View>: View {
    let size: CGFloat
    var filled = true
    @ViewBuilder let content: () -> Content
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        content()
            .frame(width: size, height: size)
            .background(Circle().fill(isFocused ? DT.Color.accent : (filled ? DT.Color.backgroundSecondary : .clear)))
            .scaleEffect(isFocused ? 1.08 : 1)
            .animation(DT.Animation.motion(.spring(response: 0.18, dampingFraction: 0.8)), value: isFocused)
    }
}

private struct PadButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.pinPadKeyStyle()
    }
}
