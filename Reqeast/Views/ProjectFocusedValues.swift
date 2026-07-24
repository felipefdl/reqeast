//
//  ProjectFocusedValues.swift
//  Reqeast
//

import SwiftUI

#if os(macOS)
struct ProjectFocusedValues: ViewModifier {
    var store: ProjectStore
    var selectedProject: Project?
    var selectedRequest: Request?
    @Binding var selectedProjectId: Project.ID?
    @Binding var selectedRequestId: Request.ID?
    @Binding var editingProject: Project?
    @Binding var projectToExport: Project?
    @Binding var showingFilePicker: Bool
    @Binding var showingSpecImport: Bool
    @Binding var showingResetSheet: Bool
    @Binding var showingExportAll: Bool
    @Binding var specExportTarget: SpecExportTarget?
    var addProject: () -> Void
    var onExportSpec: (Project, SpecExportKind) -> Void

    func body(content: Content) -> some View {
        content
            .focusedSceneValue(\.newProject, { addProject() })
            .focusedSceneValue(\.editProject, {
                if let project = selectedProject {
                    editingProject = project
                }
            })
            .focusedSceneValue(\.deleteProject, { project in
                if selectedProjectId == project.id {
                    selectedProjectId = nil
                }
                store.deleteProject(project)
            })
            .focusedSceneValue(\.duplicateProject, { project in
                let duplicate = store.duplicateProject(project)
                selectedProjectId = duplicate.id
            })
            .focusedSceneValue(\.exportProject, { project in
                projectToExport = project
            })
            .focusedSceneValue(\.importProject, { showingFilePicker = true })
            .focusedSceneValue(\.importSpec, { showingSpecImport = true })
            .focusedSceneValue(\.exportSpecOpenAPI, {
                if let project = selectedProject {
                    onExportSpec(project, .openapi)
                }
            })
            .focusedSceneValue(\.exportSpecPostman, {
                if let project = selectedProject {
                    onExportSpec(project, .postman)
                }
            })
            .focusedSceneValue(\.exportAllProjects, { showingExportAll = true })
            .focusedSceneValue(\.duplicateRequest, {
                guard let request = selectedRequest else { return }
                let duplicate = store.duplicateRequest(request)
                selectedRequestId = duplicate.id
            })
            .focusedSceneValue(\.deleteRequest, {
                guard let request = selectedRequest else { return }
                if selectedRequestId == request.id {
                    selectedRequestId = nil
                }
                store.deleteRequest(request)
            })
            .focusedSceneValue(\.resetAllData, {
                showingResetSheet = true
            })
            #if DEBUG
            .focusedSceneValue(\.debugLoadDemoData, {
                _ = DemoDataService.load(into: store)
                selectedProjectId = nil
                selectedRequestId = nil
            })
            #endif
    }
}
#endif
