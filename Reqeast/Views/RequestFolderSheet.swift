//
//  RequestFolderSheet.swift
//  Reqeast
//

import SwiftUI

struct RequestFolderSheet: View {
    @Bindable var store: ProjectStore
    let projectId: UUID
    var editingFolder: RequestFolder? = nil
    @Environment(\.dismiss) private var dismiss

    @State private var newFolderName = ""
    @State private var newFolderColor: FolderColor = .blue
    @State private var renamingFolderId: UUID?
    @State private var renamingFolderName: String = ""

    private var sortedFolders: [RequestFolder] {
        store.requestFolders(for: projectId)
    }

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
                Text("Request Folders").font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    folderList
                    if !sortedFolders.isEmpty { Divider() }
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
        .onAppear { autoEditIfNeeded() }
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
            .navigationTitle("Request Folders")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear { autoEditIfNeeded() }
    }
    #endif

    // MARK: - Shared Content

    private var folderList: some View {
        ForEach(sortedFolders) { folder in
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
                    store.updateRequestFolder(updated)
                },
                onDelete: { store.deleteRequestFolder(folder) }
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
        let folder = RequestFolder(projectId: projectId, name: newFolderName, color: newFolderColor)
        store.addRequestFolder(folder)
        newFolderName = ""
        newFolderColor = .blue
    }

    private func commitRename(_ folder: RequestFolder) {
        let trimmed = renamingFolderName.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            var updated = folder
            updated.name = trimmed
            store.updateRequestFolder(updated)
        }
        renamingFolderId = nil
    }

    private func autoEditIfNeeded() {
        if let editingFolder {
            renamingFolderName = editingFolder.name
            renamingFolderId = editingFolder.id
        }
    }
}
