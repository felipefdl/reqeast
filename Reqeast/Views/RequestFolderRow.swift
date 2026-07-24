//
//  RequestFolderRow.swift
//  Reqeast
//

import SwiftUI

struct RequestFolderRow: View {
    let folder: RequestFolder
    @Bindable var store: ProjectStore
    let projectId: UUID
    @Binding var expandedFolderIds: Set<UUID>
    @Binding var selectedRequestId: Request.ID?
    let folders: [RequestFolder]
    var searchText: String = ""
    var showStaleOnly: Bool = false
    var onEdit: (RequestFolder) -> Void
    var onRenameRequest: (Request) -> Void
    var onAutoRenameRequest: (Request) -> Void

    private var isExpanded: Binding<Bool> {
        Binding(
            get: { expandedFolderIds.contains(folder.id) },
            set: { if $0 { expandedFolderIds.insert(folder.id) } else { expandedFolderIds.remove(folder.id) } }
        )
    }

    private var folderRequests: [Request] {
        var requests = store.requests(for: projectId, inFolder: folder.id)
        if showStaleOnly {
            requests = requests.filter(\.isSpecStale)
        }
        guard !searchText.isEmpty else { return requests }
        return requests.filter { request in
            request.name.localizedCaseInsensitiveContains(searchText)
            || (request.httpData?.url ?? "").localizedCaseInsensitiveContains(searchText)
            || request.type.localizedName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        if showStaleOnly && folderRequests.isEmpty {
            EmptyView()
        } else {
            folderContent
        }
    }

    private var folderContent: some View {
        DisclosureGroup(isExpanded: isExpanded) {
            ForEach(folderRequests) { request in
                if isPhone {
                    NavigationLink {
                        RequestEditorView(store: store, requestId: request.id)
                            .navigationTitle(request.name)
                            #if !os(macOS)
                            .toolbarTitleDisplayMode(.inline)
                            #endif
                    } label: {
                        RequestRowView(request: request)
                    }
                    .contextMenu {
                        RequestContextMenu(
                            store: store,
                            request: request,
                            selectedRequestId: $selectedRequestId,
                            folders: folders,
                            onRename: { onRenameRequest(request) },
                            onAutoRename: { onAutoRenameRequest(request) }
                        )
                    }
                } else {
                    RequestRowView(request: request)
                        .tag(request.id)
                        .contextMenu {
                            RequestContextMenu(
                                store: store,
                                request: request,
                                selectedRequestId: $selectedRequestId,
                                folders: folders,
                                onRename: { onRenameRequest(request) },
                                onAutoRename: { onAutoRenameRequest(request) }
                            )
                        }
                }
            }
        } label: {
            folderLabel
        }
    }

    // MARK: - Folder Label

    private var folderLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .foregroundStyle(folder.color.color)
                .font(.system(size: 12))
            Text(folder.name)
                .lineLimit(1)
            Spacer()
            let count = folderRequests.count
            if count > 0 {
                Text("\(count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.secondary.opacity(0.15), in: Capsule())
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            folderContextMenu
        }
    }

    // MARK: - Folder Context Menu

    @ViewBuilder
    private var folderContextMenu: some View {
        Button {
            onEdit(folder)
        } label: {
            Label("Rename", systemImage: "pencil")
        }

        Menu("Color") {
            ForEach(FolderColor.allCases, id: \.self) { color in
                Button {
                    var updated = folder
                    updated.color = color
                    store.updateRequestFolder(updated)
                } label: {
                    HStack {
                        Image(systemName: folder.color == color ? "checkmark.circle.fill" : "circle.fill")
                        Text(color.localizedName)
                    }
                }
            }
        }

        Divider()

        Button(role: .destructive) {
            store.deleteRequestFolder(folder)
        } label: {
            Label("Delete Folder", systemImage: "trash")
        }
    }
}
