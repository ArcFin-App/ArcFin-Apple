// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI

/// The steps to get a Jellyfin server running, and tips for its address, in each platform's
/// `SetupGuideSheet`.
struct SetupGuideContent: View {
    private struct Step: Identifiable {
        let id: Int
        let icon: String
        let title: LocalizedStringKey
        let detail: LocalizedStringKey
    }

    private let steps: [Step] = [
        Step(id: 1, icon: "server.rack",
             title: "Install Jellyfin Server",
             detail: "Download and install Jellyfin on a computer, NAS, or home server. Supported on Windows, macOS, Linux, and Docker."),
        Step(id: 2, icon: "network",
             title: "Note your server address",
             detail: "Open the Jellyfin Dashboard → Networking. Your local address is usually http://YOUR-IP:8096. For remote access you'll need to set up port forwarding or a reverse proxy."),
        Step(id: 3, icon: "lock.shield",
             title: "Recommended: enable HTTPS",
             detail: "Use a reverse proxy (Nginx, Caddy) with a free Let's Encrypt certificate so your connection is encrypted. Arcfin works with http:// but https:// is strongly recommended."),
        Step(id: 4, icon: "person.badge.plus",
             title: "Create a user account",
             detail: "In the Jellyfin Dashboard go to Administration → Users → Add User. Give it a username and password, then set library access permissions."),
        Step(id: 5, icon: "wifi",
             title: "Local discovery",
             detail: "When this device is on the same network as the server, Arcfin finds it by itself. Pick it under On Your Network."),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Jellyfin Setup Guide")
                        .scaledFont(size: 22, weight: .bold)
                        .foregroundStyle(DT.Color.textPrimary)

                    Text("Get your server running in a few steps")
                        .font(DT.Font.caption)
                        .foregroundStyle(DT.Color.textSecondary)
                }
                .padding(.horizontal, DT.Spacing.pagePad)
                .padding(.top, DT.Spacing.lg)
                .padding(.bottom, DT.Spacing.md)

                ForEach(steps) { step in
                    stepRow(step)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Quick tips")
                        .scaledFont(size: 11, weight: .bold)
                        .tracking(0.5)
                        .textCase(.uppercase)
                        .foregroundStyle(DT.Color.textSecondary)

                    tipRow(icon: "exclamationmark.triangle", text: "Include the port number — e.g. http://192.168.1.10:8096")
                    tipRow(icon: "checkmark.circle", text: "Arcfin auto-discovers servers on your local Wi-Fi network")
                    tipRow(icon: "checkmark.circle", text: "Quick Connect lets you sign in without typing a password on this device")
                }
                .padding(16)
                .background(DT.Color.accent.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: DT.Radius.md))
                .overlay(RoundedRectangle(cornerRadius: DT.Radius.md).stroke(DT.Color.accent.opacity(0.12), lineWidth: 1))
                .padding(.horizontal, DT.Spacing.pagePad)
                .padding(.top, DT.Spacing.md)
                .padding(.bottom, DT.Spacing.xxxl)
            }
        }
    }

    private func stepRow(_ step: Step) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(DT.Color.accent.opacity(0.12))
                        .overlay(Circle().stroke(DT.Color.accent.opacity(0.3), lineWidth: 1))
                        .frame(width: 36, height: 36)
                    Image(systemName: step.icon)
                        .font(.system(.subheadline))
                        .foregroundStyle(DT.Color.accent)
                }
                if step.id < steps.count {
                    Rectangle()
                        .fill(DT.Color.accent.opacity(0.15))
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                        .padding(.vertical, 4)
                }
            }
            .frame(width: 36)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("\(step.id).")
                        .scaledFont(size: 12, weight: .bold)
                        .foregroundStyle(DT.Color.accent)
                    Text(step.title)
                        .scaledFont(size: 13, weight: .semibold)
                        .foregroundStyle(DT.Color.textPrimary)
                }
                Text(step.detail)
                    .font(DT.Font.caption)
                    .foregroundStyle(DT.Color.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, step.id < steps.count ? DT.Spacing.lg : DT.Spacing.md)
        }
        .padding(.horizontal, DT.Spacing.pagePad)
    }

    private func tipRow(icon: String, text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(.caption2))
                .foregroundStyle(icon.contains("check") ? DT.Color.palette("10b981") : DT.Color.palette("F59E0B"))
                .frame(width: 16)
            Text(text)
                .font(DT.Font.caption2)
                .foregroundStyle(DT.Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
