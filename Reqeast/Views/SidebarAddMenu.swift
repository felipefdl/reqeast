//
//  SidebarAddMenu.swift
//  Reqeast
//

import SwiftUI

struct SidebarAddMenu: View {
    var onNewProject: () -> Void
    var onImportSpec: () -> Void
    var onImportProject: () -> Void
    @Binding var showingFolderManager: Bool

    var body: some View {
        Menu {
            Button(action: onNewProject) {
                Label("New Project", systemImage: "plus")
            }
            Button(action: onImportSpec) {
                Label(String(localized: "Import Spec..."), systemImage: "doc.text")
            }
            .accessibilityIdentifier("spec-import-menu")
            Button(action: onImportProject) {
                Label("Import Project...", systemImage: "square.and.arrow.down")
            }

            Divider()

            Button {
                showingFolderManager = true
            } label: {
                Label("Folders", systemImage: "folder")
            }
        } label: {
            Label("Add", systemImage: "plus")
        }
    }
}
