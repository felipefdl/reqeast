//
//  ProjectManagerSheets.swift
//  Reqeast
//

import SwiftUI
import UniformTypeIdentifiers

struct ProjectManagerSheets: ViewModifier {
    var store: ProjectStore
    @Binding var projectToExport: Project?
    @Binding var editingProject: Project?
    @Binding var showingCreateProject: Bool
    @Binding var showingProtocolPicker: Bool
    @Binding var pendingImport: ImportResult?
    @Binding var showingExportAll: Bool
    @Binding var pendingBundleImport: ImportBundleResult?
    @Binding var showingResetSheet: Bool
    @Binding var showingFilePicker: Bool
    @Binding var showingSpecImport: Bool
    @Binding var showingSettings: Bool
    @Binding var selectedProjectId: Project.ID?
    @Binding var selectedRequestId: Request.ID?
    @Binding var specExportTarget: SpecExportTarget?
    var addRequest: (RequestType) -> Void

    func body(content: Content) -> some View {
        content
            .sheet(item: $projectToExport) { project in
                ExportSheet(store: store, project: project)
            }
            .sheet(item: $editingProject) { project in
                ProjectEditSheet(store: store, project: project)
            }
            .sheet(isPresented: $showingCreateProject) {
                ProjectEditSheet(
                    store: store,
                    project: Project(name: ""),
                    mode: .create(onCreate: { project in
                        selectedProjectId = project.id
                    })
                )
            }
            .sheet(isPresented: $showingProtocolPicker) {
                ProtocolPickerSheet { type in addRequest(type) }
            }
            .sheet(item: $pendingImport) { result in
                ImportSheet(store: store, result: result) { _ in
                    selectedProjectId = nil
                }
            }
            .sheet(isPresented: $showingExportAll) {
                ExportAllSheet(store: store)
            }
            .sheet(item: $pendingBundleImport) { result in
                ImportBundleSheet(store: store, result: result) { _ in
                    selectedProjectId = nil
                }
            }
            .sheet(isPresented: $showingResetSheet) {
                ResetDataSheet {
                    try DataResetService.resetAllData(store: store)
                    selectedProjectId = nil
                    selectedRequestId = nil
                }
            }
            .sheet(isPresented: $showingSpecImport) {
                SpecImportSheet(store: store, preferredTargetProjectId: selectedProjectId) { project in
                    selectProjectAfterSpecImport(project)
                }
            }
            .sheet(item: $specExportTarget) { target in
                ExportSpecSheet(store: store, project: target.project, kind: target.kind)
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.reqeastExport],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    handleParsedImport(at: url)
                }
            }
            .onOpenURL { url in
                guard url.pathExtension == "reqeast" else { return }
                handleParsedImport(at: url)
            }
            #if !os(macOS)
            .sheet(isPresented: $showingSettings) {
                NavigationStack {
                    ProjectManagerSettingsContent(
                        store: store,
                        showingSettings: $showingSettings,
                        showingExportAll: $showingExportAll,
                        showingFilePicker: $showingFilePicker,
                        selectedProjectId: $selectedProjectId,
                        selectedRequestId: $selectedRequestId
                    )
                    .navigationTitle("Settings")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingSettings = false }
                        }
                    }
                }
            }
            #endif
            #if os(macOS)
            .onChange(of: selectedProjectId) { _, newValue in
                MCPExportService.shared.exportContext(projectId: newValue, requestId: selectedRequestId)
            }
            .onChange(of: selectedRequestId) { _, newValue in
                MCPExportService.shared.exportContext(projectId: selectedProjectId, requestId: newValue)
            }
            #endif
    }

    private func handleParsedImport(at url: URL) {
        guard let parsed = ImportExportService.parseImportFile(at: url) else { return }
        switch parsed {
        case .single(let result):
            pendingImport = result
        case .bundle(let result):
            pendingBundleImport = result
        }
    }

    private func selectProjectAfterSpecImport(_ project: Project) {
        let firstHttpId = store.requests(for: project.id).first(where: { $0.type == .http })?.id
        selectedProjectId = project.id
        guard let firstHttpId else { return }
        Task { @MainActor in
            selectedRequestId = firstHttpId
        }
    }
}
