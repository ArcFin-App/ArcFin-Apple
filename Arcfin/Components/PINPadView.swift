// SPDX-License-Identifier: AGPL-3.0-or-later

#if !os(tvOS)
import SwiftUI

struct PINPadView: View {
    let title: String
    var subtitle: String? = nil
    var errorMessage: String? = nil
    // Increment to trigger a shake + digit reset
    var resetToken: Int = 0
    var onCancel: (() -> Void)? = nil
    var onComplete: (String) -> Void

    @State private var digits: [Int] = []
    @State private var shakeOffset: CGFloat = 0

    private let pinLength = 4

    var body: some View {
        ZStack {
            DT.Color.backgroundPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                // Cancel row
                if let onCancel {
                    HStack {
                        Button("Cancel", action: onCancel)
                            .font(.system(.callout, design: .default))
                            .foregroundStyle(DT.Color.accent)
                        Spacer()
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
                        ForEach(0..<pinLength, id: \.self) { i in
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
                                .animation(.spring(response: 0.15, dampingFraction: 0.7), value: digits.count)
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
                        Color.clear.frame(width: 76, height: 76)
                        padButton(label: "0") { append(0) }
                        Button { removeLast() } label: {
                            Image(systemName: "delete.left")
                                .font(.system(size: 20, weight: .light))
                                .foregroundStyle(digits.isEmpty ? DT.Color.textSecondary.opacity(0.3) : DT.Color.textPrimary)
                                .frame(width: 76, height: 76)
                        }
                        .accessibilityLabel("Delete")
                        .buttonStyle(.plain)
                        .disabled(digits.isEmpty)
                    }
                }
                .padding(.bottom, 52)
            }
        }
        .onChange(of: resetToken) { _, _ in triggerShake() }
        .animation(DT.Animation.fast, value: errorMessage)
    }

    // MARK: - Pad button

    private func padButton(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(.title, design: .rounded, weight: .light))
                .foregroundStyle(DT.Color.textPrimary)
                .frame(width: 76, height: 76)
                .background(Circle().fill(DT.Color.backgroundSecondary))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private func append(_ digit: Int) {
        guard digits.count < pinLength else { return }
        digits.append(digit)
        if digits.count == pinLength {
            let pin = digits.map { "\($0)" }.joined()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(120))
                onComplete(pin)
            }
        }
    }

    private func removeLast() {
        guard !digits.isEmpty else { return }
        digits.removeLast()
    }

    private func triggerShake() {
        digits = []
        let duration = 0.07
        withAnimation(.easeInOut(duration: duration)) { shakeOffset = -10 }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            withAnimation(.easeInOut(duration: duration)) { shakeOffset = 10 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration * 2) {
            withAnimation(.easeInOut(duration: duration)) { shakeOffset = -8 }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration * 3) {
            withAnimation(.spring(response: 0.2)) { shakeOffset = 0 }
        }
    }
}
#endif
