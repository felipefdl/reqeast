//
//  FolderRowEditor.swift
//  Reqeast
//

import SwiftUI

struct FolderRowEditor: View {
    let folderName: String
    let folderColor: FolderColor
    let isRenaming: Bool
    @Binding var renamingName: String
    var onCommitRename: () -> Void
    var onCancelRename: () -> Void
    var onStartRename: () -> Void
    var onColorChange: (FolderColor) -> Void
    var onDelete: () -> Void

    var body: some View {
        if isRenaming {
            renamingRow
        } else {
            displayRow
        }
    }

    private var renamingRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(folderColor.color)
                .frame(width: 12, height: 12)

            TextField("Folder name", text: $renamingName)
                .onSubmit { onCommitRename() }
                .devTextInput()

            Button {
                onCommitRename()
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            .buttonStyle(.plain)

            Button {
                onCancelRename()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private var displayRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(folderColor.color)
                .frame(width: 12, height: 12)

            Text(folderName)

            Spacer()

            Menu {
                Button {
                    onStartRename()
                } label: {
                    Label("Rename", systemImage: "pencil")
                }

                Menu("Color") {
                    ForEach(FolderColor.allCases, id: \.self) { color in
                        Button {
                            onColorChange(color)
                        } label: {
                            HStack {
                                Image(systemName: folderColor == color ? "checkmark.circle.fill" : "circle.fill")
                                Text(color.localizedName)
                            }
                        }
                    }
                }

                Divider()

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete Folder", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
        }
    }
}
