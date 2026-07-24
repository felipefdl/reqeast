//
//  ProjectSidebarToolbar.swift
//  Reqeast
//

import SwiftUI

struct ProjectSidebarToolbar: ToolbarContent {
    @Bindable var store: ProjectStore
    var onNewProject: () -> Void
    var onShowSettings: () -> Void
    var onImportSpec: () -> Void
    var onImportProject: () -> Void
    @Binding var showingFolderManager: Bool

    var body: some ToolbarContent {
        #if !os(macOS)
        ToolbarItem(placement: .topBarLeading) {
            Button(action: onShowSettings) {
                Label("Settings", systemImage: "gear")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            CloudSyncStatusButton()
        }
        #endif
        #if os(macOS)
        ToolbarItem(placement: .primaryAction) {
            CloudSyncStatusButton()
        }
        ToolbarItem(placement: .primaryAction) {
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
                Image(systemName: "plus")
            }
        }
        #else
        ToolbarItemGroup(placement: .primaryAction) {
            if isPhone {
                if store.hasActiveProjects {
                    SidebarAddMenu(
                        onNewProject: onNewProject,
                        onImportSpec: onImportSpec,
                        onImportProject: onImportProject,
                        showingFolderManager: $showingFolderManager
                    )
                }
            } else {
                SidebarAddMenu(
                    onNewProject: onNewProject,
                    onImportSpec: onImportSpec,
                    onImportProject: onImportProject,
                    showingFolderManager: $showingFolderManager
                )
            }
        }
        #endif
    }
}
