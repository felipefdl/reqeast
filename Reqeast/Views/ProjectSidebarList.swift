//
//  ProjectSidebarList.swift
//  Reqeast
//

import SwiftUI

struct ProjectSidebarList: View {
    @Bindable var store: ProjectStore
    @Binding var selectedProjectId: Project.ID?
    @Binding var editingProject: Project?
    var onExportProject: ((Project) -> Void)?
    var onExportSpec: ((Project, SpecExportKind) -> Void)?

    var body: some View {
        if isPhone {
            List {
                Section {
                    ForEach(store.unfolderedProjects) { project in
                        PhoneProjectRow(
                            project: project,
                            store: store,
                            selectedProjectId: $selectedProjectId,
                            editingProject: $editingProject,
                            onExportProject: onExportProject,
                            onExportSpec: onExportSpec
                        )
                    }
                }
                ForEach(store.sortedFolders) { folder in
                    Section {
                        ForEach(store.projects(in: folder)) { project in
                            PhoneProjectRow(
                                project: project,
                                store: store,
                                selectedProjectId: $selectedProjectId,
                                editingProject: $editingProject,
                                onExportProject: onExportProject,
                                onExportSpec: onExportSpec
                            )
                        }
                    } header: {
                        FolderSectionHeader(store: store, folder: folder)
                    }
                }
            }
            .refreshable { await CloudSyncService.shared.syncChanges() }
        } else {
            List(selection: $selectedProjectId) {
                Section {
                    ForEach(store.unfolderedProjects) { project in
                        ProjectListRow(
                            project: project,
                            store: store,
                            selectedProjectId: $selectedProjectId,
                            editingProject: $editingProject,
                            onExportProject: onExportProject,
                            onExportSpec: onExportSpec
                        )
                    }
                }
                ForEach(store.sortedFolders) { folder in
                    Section {
                        ForEach(store.projects(in: folder)) { project in
                            ProjectListRow(
                                project: project,
                                store: store,
                                selectedProjectId: $selectedProjectId,
                                editingProject: $editingProject,
                                onExportProject: onExportProject,
                                onExportSpec: onExportSpec
                            )
                        }
                    } header: {
                        FolderSectionHeader(store: store, folder: folder)
                    }
                }
            }
        }
    }
}
