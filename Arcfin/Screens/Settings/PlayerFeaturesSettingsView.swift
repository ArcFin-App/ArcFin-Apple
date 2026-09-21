import SwiftUI

/// Per-feature on/off switches for everything added to the player beyond the original
/// core playback controls — each reads back via plain UserDefaults from PlayerView itself
/// (a struct, not a View, so no @AppStorage there), same keys as declared here.
struct PlayerFeaturesSettingsView: View {
    @AppStorage("chapterListEnabled") private var chapterListEnabled = true
    @AppStorage("syncPlayEnabled") private var syncPlayEnabled = true
    @AppStorage("castEnabled") private var castEnabled = true
    @AppStorage("stillWatchingPromptEnabled") private var stillWatchingPromptEnabled = true
    @AppStorage("matchContentFrameRate") private var matchContentFrameRate = false

    var body: some View {
        List {
            Section {
                Toggle("Chapter List", isOn: $chapterListEnabled)
                    .tvListRow()
            } footer: {
                Text("Shows a jump-to-chapter list button in the player when the item has chapter markers.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }

            Section {
                Toggle("SyncPlay", isOn: $syncPlayEnabled)
                    .tvListRow()
            } footer: {
                Text("Lets you create or join a SyncPlay group to keep playback in sync with others watching the same title.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }

            Section {
                Toggle("Chromecast", isOn: $castEnabled)
                    .tvListRow()
            } footer: {
                Text("Shows the Cast button when a Chromecast device is available on your network.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }

            Section {
                Toggle("\"Are You Still Watching?\" Prompt", isOn: $stillWatchingPromptEnabled)
                    .tvListRow()
            } footer: {
                Text("Pauses and asks for confirmation after 3 episodes have auto-played in a row with no interaction.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }

            Section {
                Toggle("Match Content Frame Rate", isOn: $matchContentFrameRate)
                    .tvListRow()
            } footer: {
                Text("Switches the display's refresh rate to match the video's frame rate (e.g. 24fps film) so panning motion doesn't judder. Only applies to AVFoundation playback — off by default since some TVs/displays show a brief black flash when the refresh rate switches.")
                    .font(.caption)
                    .foregroundStyle(DT.Color.textSecondary)
            }
        }
        .arcfinListStyle()
        .background(DT.Color.backgroundPrimary)
        .arcfinNavTitleLarge("Player Features")
    }
}

#Preview {
    NavigationStack { PlayerFeaturesSettingsView() }
}
