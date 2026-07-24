//
//  FolderSectionHeader.swift
//  Reqeast
//

import SwiftUI

struct FolderSectionHeader: View {
    @Bindable var store: ProjectStore
    let folder: ProjectFolder

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(folder.color.color)
                .frame(width: 8, height: 8)
            Text(folder.name)
        }
        .contextMenu {
            Menu("Color") {
                ForEach(FolderColor.allCases, id: \.self) { color in
                    Button {
                        var updated = folder
                        updated.color = color
                        store.updateFolder(updated)
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
                store.deleteFolder(folder)
            } label: {
                Label("Delete Folder", systemImage: "trash")
            }
        }
    }
}
