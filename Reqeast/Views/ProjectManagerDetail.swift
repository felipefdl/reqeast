//
//  ProjectManagerDetail.swift
//  Reqeast
//

import SwiftUI

struct ProjectManagerDetailView: View {
    var store: ProjectStore
    var selectedProject: Project?
    var selectedRequest: Request?
    @Binding var selectedRequestId: Request.ID?
    @Binding var showingProtocolPicker: Bool
    @Binding var editingProject: Project?
    @Binding var projectToExport: Project?
    @Binding var showingFilePicker: Bool
    @Binding var showingSpecImport: Bool
    var onNewProject: () -> Void

    var body: some View {
        if let selectedRequestId, selectedRequest != nil {
            RequestEditorView(store: store, requestId: selectedRequestId)
                .id(selectedRequestId)
                .navigationTitle(selectedRequest?.name ?? "")
                #if os(macOS)
                .navigationSubtitle(selectedProject?.name ?? "")
                #else
                .toolbarTitleDisplayMode(.inline)
                #endif
                .transaction { $0.animation = nil }
        } else if let project = selectedProject {
            if isPhone {
                Color.clear
            } else {
                ProjectWelcomeView(
                    project: project,
                    store: store,
                    onNewRequest: { showingProtocolPicker = true },
                    onEditProject: { editingProject = project },
                    onExportProject: { projectToExport = project }
                )
                .id(project.id)
                .navigationTitle(project.name)
            }
        } else {
            WelcomeView(
                onNewProject: onNewProject,
                onImportSpec: { showingSpecImport = true }
            )
            .navigationTitle("Reqeast")
        }
    }
}

// MARK: - Sidebar Content

struct ProjectManagerSidebarContent: View {
    var store: ProjectStore
    var selectedProject: Project?
    @Binding var selectedProjectId: Project.ID?
    @Binding var selectedRequestId: Request.ID?
    @Binding var showingSettings: Bool
    @Binding var showingFilePicker: Bool
    @Binding var showingSpecImport: Bool
    @Binding var projectToExport: Project?
    @Binding var specExportTarget: SpecExportTarget?
    var onNewProject: () -> Void
    var onExportSpec: (Project, SpecExportKind) -> Void

    var body: some View {
        if let project = selectedProject {
            RequestListView(
                store: store,
                project: project,
                selectedRequestId: $selectedRequestId
            )
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    Button {
                        selectedProjectId = nil
                        selectedRequestId = nil
                    } label: {
                        Label("Projects", systemImage: "chevron.backward")
                    }
                }
            }
        } else {
            ProjectSidebarView(
                store: store,
                selectedProjectId: $selectedProjectId,
                onNewProject: onNewProject,
                onShowSettings: { showingSettings = true },
                onImportSpec: { showingSpecImport = true },
                onImportProject: { showingFilePicker = true },
                onExportProject: { project in projectToExport = project },
                onExportSpec: onExportSpec
            )
        }
    }
}

// MARK: - Settings Content

#if !os(macOS)
struct ProjectManagerSettingsContent: View {
    var store: ProjectStore
    @Binding var showingSettings: Bool
    @Binding var showingExportAll: Bool
    @Binding var showingFilePicker: Bool
    @Binding var selectedProjectId: Project.ID?
    @Binding var selectedRequestId: Request.ID?

    var body: some View {
        #if DEBUG
        SettingsView(
            onExportAll: !store.hasActiveProjects ? nil : {
                showingSettings = false
                showingExportAll = true
            },
            onImportProject: {
                showingSettings = false
                showingFilePicker = true
            },
            onLoadDemoData: {
                showingSettings = false
                _ = DemoDataService.load(into: store)
                selectedProjectId = nil
                selectedRequestId = nil
            }
        )
        #else
        SettingsView(
            onExportAll: !store.hasActiveProjects ? nil : {
                showingSettings = false
                showingExportAll = true
            },
            onImportProject: {
                showingSettings = false
                showingFilePicker = true
            }
        )
        #endif
    }
}
#endif
