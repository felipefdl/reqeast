//
//  SidebarEmptyStateOverlay.swift
//  Reqeast
//

import SwiftUI

struct SidebarEmptyStateOverlay: View {
    @Bindable var store: ProjectStore
    var onNewProject: () -> Void
    var onImportSpec: () -> Void

    var body: some View {
        if !store.hasActiveProjects {
            if isPhone {
                SidebarEmptyState(
                    onNewProject: onNewProject,
                    onImportSpec: onImportSpec
                )
            } else if !StorageEnvironment.isScreenshotMode {
                ContentUnavailableView {
                    Label("No Projects", systemImage: "folder")
                        .foregroundStyle(.secondary)
                } description: {
                    Text("Add a project to get started")
                } actions: {
                    Button(action: onNewProject) {
                        Label("New Project", systemImage: "plus.circle")
                    }
                    .buttonStyle(.borderedProminent)

                    Button(action: onImportSpec) {
                        Label(String(localized: "Import Spec"), systemImage: "doc.text")
                    }
                }
            }
        }
    }
}
