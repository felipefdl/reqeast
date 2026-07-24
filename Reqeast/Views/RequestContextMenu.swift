//
//  RequestContextMenu.swift
//  Reqeast
//

import SwiftUI

struct RequestContextMenu: View {
    @Bindable var store: ProjectStore
    let request: Request
    @Binding var selectedRequestId: Request.ID?
    let folders: [RequestFolder]
    var onRename: () -> Void
    var onAutoRename: () -> Void

    var body: some View {
        Button {
            onRename()
        } label: {
            Label("Rename", systemImage: "pencil")
        }

        if RequestNamingService.isAvailable {
            Button {
                onAutoRename()
            } label: {
                Label("Auto Rename", systemImage: "sparkles")
            }
        }

        Button {
            let duplicate = store.duplicateRequest(request)
            selectedRequestId = duplicate.id
        } label: {
            Label("Duplicate", systemImage: "plus.square.on.square")
        }

        Menu("Move to Folder") {
            Button {
                store.moveRequest(request, toFolder: nil)
            } label: {
                HStack {
                    if request.folderId == nil {
                        Image(systemName: "checkmark")
                    }
                    Text("None")
                }
            }

            if !folders.isEmpty {
                Divider()

                ForEach(folders) { folder in
                    Button {
                        store.moveRequest(request, toFolder: folder)
                    } label: {
                        HStack {
                            if request.folderId == folder.id {
                                Image(systemName: "checkmark")
                            }
                            Image(systemName: "circle.fill")
                                .foregroundStyle(folder.color.color)
                            Text(folder.name)
                        }
                    }
                }
            }
        }

        if request.isSpecStale {
            Button {
                store.dismissSpecStale(for: request)
            } label: {
                Label("Dismiss Stale", systemImage: "checkmark.circle")
            }
            .accessibilityIdentifier(SpecSyncAccessibility.dismissStaleContextMenu)

            Divider()
        }

        Button(role: .destructive) {
            if selectedRequestId == request.id {
                selectedRequestId = nil
            }
            store.deleteRequest(request)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}
