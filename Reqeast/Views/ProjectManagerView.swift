//
//  ProjectManagerView.swift
//  Reqeast
//

import SwiftUI

struct ProjectManagerView: View {
    private var store: ProjectStore { .shared }
    @State private var selectedProjectId: Project.ID?
    @State private var selectedRequestId: Request.ID?
    @State private var showingSettings = false
    @State private var projectToExport: Project?
    @State private var pendingImport: ImportResult?
    @State private var showingFilePicker = false
    @State private var showingSpecImport = false
    @State private var editingProject: Project?
    @State private var showingProtocolPicker = false
    @State private var showingCreateProject = false
    @State private var showingResetSheet = false
    @State private var showingExportAll = false
    @State private var pendingBundleImport: ImportBundleResult?
    @State private var specExportTarget: SpecExportTarget?

    private var selectedProject: Project? {
        guard let selectedProjectId else { return nil }
        return store.projects.first { $0.id == selectedProjectId && $0.deletedAt == nil }
    }

    private var selectedRequest: Request? {
        guard let selectedRequestId, let selectedProjectId else { return nil }
        return store.requests.first { $0.id == selectedRequestId && $0.projectId == selectedProjectId && $0.deletedAt == nil }
    }

    var body: some View {
        mainContent
            #if DEBUG
            .onAppear {
                presentSpecImportIfRequested()
                presentSpecExportIfRequested()
            }
            .onChange(of: SpecImportPresentationState.shared.shouldPresentImportSheet) { _, _ in
                presentSpecImportIfRequested()
            }
            .onChange(of: SpecExportPresentationState.shared.shouldPresentExportSheet) { _, _ in
                presentSpecExportIfRequested()
            }
            #endif
            .modifier(ProjectManagerSheets(
                store: store,
                projectToExport: $projectToExport,
                editingProject: $editingProject,
                showingCreateProject: $showingCreateProject,
                showingProtocolPicker: $showingProtocolPicker,
                pendingImport: $pendingImport,
                showingExportAll: $showingExportAll,
                pendingBundleImport: $pendingBundleImport,
                showingResetSheet: $showingResetSheet,
                showingFilePicker: $showingFilePicker,
                showingSpecImport: $showingSpecImport,
                showingSettings: $showingSettings,
                selectedProjectId: $selectedProjectId,
                selectedRequestId: $selectedRequestId,
                specExportTarget: $specExportTarget,
                addRequest: addRequest
            ))
    }

    @ViewBuilder
    private var mainContent: some View {
        #if !os(macOS)
        if isPhone {
            NavigationStack {
                ProjectSidebarView(
                    store: store,
                    selectedProjectId: $selectedProjectId,
                    onNewProject: addProject,
                    onShowSettings: { showingSettings = true },
                    onImportSpec: { showingSpecImport = true },
                    onImportProject: { showingFilePicker = true },
                    onExportProject: { project in projectToExport = project },
                    onExportSpec: presentSpecExport
                )
                .navigationDestination(item: $selectedProjectId) { projectId in
                    if let project = store.projects.first(where: { $0.id == projectId && $0.deletedAt == nil }) {
                        RequestListView(
                            store: store,
                            project: project,
                            selectedRequestId: $selectedRequestId
                        )
                    } else {
                        Color.clear
                    }
                }
            }
            .onChange(of: selectedProjectId) { _, _ in
                selectedRequestId = nil
            }
        } else {
            splitContent
        }
        #else
        splitContent
        #endif
    }

    private var splitContent: some View {
        NavigationSplitView {
            ProjectManagerSidebarContent(
                store: store,
                selectedProject: selectedProject,
                selectedProjectId: $selectedProjectId,
                selectedRequestId: $selectedRequestId,
                showingSettings: $showingSettings,
                showingFilePicker: $showingFilePicker,
                showingSpecImport: $showingSpecImport,
                projectToExport: $projectToExport,
                specExportTarget: $specExportTarget,
                onNewProject: addProject,
                onExportSpec: presentSpecExport
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 290, max: 400)
        } detail: {
            // NavigationStack is required for detail `.navigationTitle` to appear in the
            // macOS title bar after the toolbar chips (references/mac-1: lights → chips → "Reqeast").
            // Without it the menu bar has chips only and looks wrong in screenshots.
            NavigationStack {
                ProjectManagerDetailView(
                    store: store,
                    selectedProject: selectedProject,
                    selectedRequest: selectedRequest,
                    selectedRequestId: $selectedRequestId,
                    showingProtocolPicker: $showingProtocolPicker,
                    editingProject: $editingProject,
                    projectToExport: $projectToExport,
                    showingFilePicker: $showingFilePicker,
                    showingSpecImport: $showingSpecImport,
                    onNewProject: addProject
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: selectedProjectId) { _, _ in
            selectedRequestId = nil
        }
        #if os(macOS)
        .focusedSceneValue(\.selectedProject, selectedProject)
        .focusedSceneValue(\.selectedRequest, selectedRequest)
        .modifier(ProjectFocusedValues(
            store: store,
            selectedProject: selectedProject,
            selectedRequest: selectedRequest,
            selectedProjectId: $selectedProjectId,
            selectedRequestId: $selectedRequestId,
            editingProject: $editingProject,
            projectToExport: $projectToExport,
            showingFilePicker: $showingFilePicker,
            showingSpecImport: $showingSpecImport,
            showingResetSheet: $showingResetSheet,
            showingExportAll: $showingExportAll,
            specExportTarget: $specExportTarget,
            addProject: addProject,
            onExportSpec: presentSpecExport
        ))
        #endif
    }

    private func presentSpecExport(project: Project, kind: SpecExportKind) {
        specExportTarget = SpecExportTarget(project: project, kind: kind)
    }

    private func addProject() {
        showingCreateProject = true
    }

    #if DEBUG
    private func presentSpecImportIfRequested() {
        guard SpecImportPresentationState.shared.shouldPresentImportSheet else { return }
        showingSpecImport = true
        SpecImportPresentationState.shared.shouldPresentImportSheet = false
    }

    private func presentSpecExportIfRequested() {
        guard SpecExportPresentationState.shared.shouldPresentExportSheet,
              let target = SpecExportPresentationState.shared.pendingTarget else { return }
        specExportTarget = target
        SpecExportPresentationState.shared.pendingTarget = nil
        SpecExportPresentationState.shared.shouldPresentExportSheet = false
    }
    #endif

    private func addRequest(type: RequestType) {
        guard let projectId = selectedProjectId else { return }
        let requestCount = store.requests(for: projectId).count
        let request = Request(
            projectId: projectId,
            name: "New \(type.localizedName) Request",
            type: type,
            sortOrder: requestCount
        )
        store.addRequest(request)
        selectedRequestId = request.id
    }
}
