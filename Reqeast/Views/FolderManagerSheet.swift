//
//  FolderManagerSheet.swift
//  Reqeast
//

import SwiftUI

struct FolderManagerSheet: View {
    @Bindable var store: ProjectStore
    @Environment(\.dismiss) private var dismiss

    @State private var newFolderName = ""
    @State private var newFolderColor: FolderColor = .blue
    @State private var renamingFolderId: UUID?
    @State private var renamingFolderName: String = ""

    var body: some View {
        #if os(macOS)
        macOSBody
        #else
        iOSBody
        #endif
    }

    // MARK: - macOS Body

    #if os(macOS)
    private var macOSBody: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Folders").font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    folderList
                    newFolderSection
                }
                .padding(16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(.glassProminent).keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(width: 400, height: 450)
    }
    #endif

    // MARK: - iOS Body

    #if !os(macOS)
    private var iOSBody: some View {
        NavigationStack {
            List {
                Section { folderList }
                Section("New Folder") { newFolderSection }
            }
            .navigationTitle("Folders")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
    #endif

    // MARK: - Shared Content

    private var folderList: some View {
        ForEach(store.sortedFolders) { folder in
            FolderRowEditor(
                folderName: folder.name,
                folderColor: folder.color,
                isRenaming: renamingFolderId == folder.id,
                renamingName: $renamingFolderName,
                onCommitRename: { commitRename(folder) },
                onCancelRename: { renamingFolderId = nil },
                onStartRename: {
                    renamingFolderName = folder.name
                    renamingFolderId = folder.id
                },
                onColorChange: { color in
                    var updated = folder
                    updated.color = color
                    store.updateFolder(updated)
                },
                onDelete: { store.deleteFolder(folder) }
            )
        }
    }

    private var newFolderSection: some View {
        Group {
            TextField("Folder name", text: $newFolderName)
                .devTextInput()
            FolderColorPicker(selection: $newFolderColor)
            Button("Add Folder") { addFolder() }
                .disabled(newFolderName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    // MARK: - Helpers

    private func addFolder() {
        let folder = ProjectFolder(name: newFolderName, color: newFolderColor)
        store.addFolder(folder)
        newFolderName = ""
        newFolderColor = .blue
    }

    private func commitRename(_ folder: ProjectFolder) {
        let trimmed = renamingFolderName.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            var updated = folder
            updated.name = trimmed
            store.updateFolder(updated)
        }
        renamingFolderId = nil
    }
}
