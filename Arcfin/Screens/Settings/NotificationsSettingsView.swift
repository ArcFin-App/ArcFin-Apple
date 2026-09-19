import SwiftUI

struct NotificationsSettingsView: View {
    @AppStorage("notifyNewContent") private var notifyNewContent = true
    @AppStorage("notifyDownload")   private var notifyDownload   = true

    var body: some View {
        List {
            Section {
                Toggle("New Content Added", isOn: $notifyNewContent)
                Toggle("Download Complete", isOn: $notifyDownload)
            }
        }
        .arcfinListStyle()
        .background(DT.Color.backgroundPrimary)
        .arcfinNavTitleLarge("Notifications")
    }
}

#Preview {
    NavigationStack { NotificationsSettingsView() }
}
