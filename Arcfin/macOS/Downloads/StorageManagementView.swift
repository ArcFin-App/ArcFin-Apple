// SPDX-License-Identifier: AGPL-3.0-or-later

import SwiftUI
import SwiftData
import Persistence

struct StorageManagementView: View {
    @Environment(DownloadManager.self) private var downloadManager
    @Query(sort: [SortDescriptor(\DownloadedItem.downloadedAt, order: .reverse)]) private var items: [DownloadedItem]

    @State private var model = StorageManagementModel()
    @State private var isSelectingMac = false

    private var entries: [StorageManagementModel.StorageEntry] { StorageManagementModel.entries(of: items) }

    var body: some View {
        Group {
            if entries.isEmpty {
                ContentUnavailableView(
                    "No Downloads",
                    systemImage: "internaldrive",
                    description: Text("Downloaded movies and shows will appear here once you have some.")
                )
            } else {
                List {
                    Section {
                        Text("\(ByteCountFormatter.string(fromByteCount: StorageManagementModel.totalSizeBytes(of: items), countStyle: .file)) used by \(items.count) download\(items.count == 1 ? "" : "s")")
                            .font(.system(.caption))
                            .foregroundStyle(DT.Color.textSecondary)
                    }

                    Section("Largest First") {
                        ForEach(entries) { entry in
                            entryRow(entry)
                        }
                    }
                }
            }
        }
        .screenBackground()
        .navigationTitle("Manage Storage")
        .toolbar {
            if !entries.isEmpty {
                if isSelectingMac && !model.selection.isEmpty {
                    ToolbarItem {
                        Button("Free Up Space (\(model.selection.count))", role: .destructive) {
                            model.showBulkDeleteConfirm = true
                        }
                    }
                }
                ToolbarItem {
                    Button(isSelectingMac ? "Done" : "Select") {
                        isSelectingMac.toggle()
                        model.selection.removeAll()
                    }
                }
            }
        }
        .modifier(StorageManagementAlerts(items: items, model: model) {
            model.deleteSelection(of: entries, downloadManager: downloadManager)
            isSelectingMac = false
        })
    }

    @ViewBuilder
    private func entryRow(_ entry: StorageManagementModel.StorageEntry) -> some View {
        if isSelectingMac {
            Button { model.toggleSelection(entry.id) } label: {
                HStack(spacing: 12) {
                    StorageEntrySelectionIndicator(isSelected: model.selection.contains(entry.id))
                    StorageEntryRowContent(entry: entry)
                }
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(model.selection.contains(entry.id) ? .isSelected : [])
        } else {
            StorageEntryRowContent(entry: entry)
                .contextMenu {
                    Button(role: .destructive) {
                        model.askToDelete(entry)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        model.askToDelete(entry)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
        }
    }
}

#Preview {
    NavigationStack { StorageManagementView() }
}
