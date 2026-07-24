//
//  ProjectSidebarView.swift
//  Reqeast
//

import SwiftUI

struct ProjectSidebarView: View {
    @Bindable var store: ProjectStore
    @Binding var selectedProjectId: Project.ID?
    var onNewProject: () -> Void
    var onShowSettings: () -> Void = {}
    var onImportSpec: () -> Void = {}
    var onImportProject: () -> Void = {}
    var onExportProject: ((Project) -> Void)?
    var onExportSpec: ((Project, SpecExportKind) -> Void)?

    @State private var showingFolderManager = false
    @State private var editingProject: Project?

    var body: some View {
        ProjectSidebarList(
            store: store,
            selectedProjectId: $selectedProjectId,
            editingProject: $editingProject,
            onExportProject: onExportProject,
            onExportSpec: onExportSpec
        )
        .listStyle(.sidebar)
        .overlay {
            SidebarEmptyStateOverlay(
                store: store,
                onNewProject: onNewProject,
                onImportSpec: onImportSpec
            )
        }
        .navigationTitle(isPhone && !store.hasActiveProjects ? "" : "Projects")
        .toolbar {
            ProjectSidebarToolbar(
                store: store,
                onNewProject: onNewProject,
                onShowSettings: onShowSettings,
                onImportSpec: onImportSpec,
                onImportProject: onImportProject,
                showingFolderManager: $showingFolderManager
            )
        }
        .sheet(isPresented: $showingFolderManager) {
            FolderManagerSheet(store: store)
        }
        .sheet(item: $editingProject) { project in
            ProjectEditSheet(store: store, project: project)
        }
    }
}
