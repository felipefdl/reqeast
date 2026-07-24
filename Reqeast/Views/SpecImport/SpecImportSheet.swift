//
//  SpecImportSheet.swift
//  Reqeast
//

import SwiftUI

struct SpecImportSheet: View {
    @Bindable var store: ProjectStore
    /// When merging into an existing project, prefer this ID if it is still importable.
    var preferredTargetProjectId: UUID?
    var onImported: (Project) -> Void

    @Environment(\.dismiss) var dismiss

    @State var phase: SpecImportPhase = .sourcePick
    @State var sourceTab: SpecImportSourceTab = .file
    @State var urlText = ""
    @State var pasteText = ""
    @State var projectName = ""
    @State var importOptions = SpecImportOptions.default
    @State var importTarget: SpecImportTarget = .newProject
    @State var targetProjectId: UUID?
    @State var showingFileImporter = false
    @State var showingFolderImporter = false
    @State var urlSnapshotDate: Date?
    @State var isRefreshingPreview = false
    @State var groupSpecsInOneProject = true
    @State var batchEnvironmentName = ""
    @State var batchEnvironmentBindings: [SpecImportEnvironmentBinding] = []
    @State var activeTask: Task<Void, Never>?

    var body: some View {
        #if os(macOS)
        macOSBody
        #else
        iOSBody
        #endif
    }

    var canCommitImport: Bool {
        guard !isRefreshingPreview else { return false }
        switch importTarget {
        case .newProject:
            return !projectName.trimmingCharacters(in: .whitespaces).isEmpty
        case .existingProject:
            return targetProjectId != nil
                && store.projects.contains(where: { $0.id == targetProjectId && $0.deletedAt == nil })
        }
    }

    var canCommitBatchImport: Bool {
        guard !isRefreshingPreview else { return false }
        guard groupSpecsInOneProject else { return true }

        let trimmedProjectName = projectName.trimmingCharacters(in: .whitespaces)
        let trimmedEnvironmentName = batchEnvironmentName.trimmingCharacters(in: .whitespaces)
        guard !trimmedProjectName.isEmpty, !trimmedEnvironmentName.isEmpty else { return false }
        guard batchEnvironmentBindings.count == batchItemCount else { return false }

        var seenNames: Set<String> = []
        for binding in batchEnvironmentBindings {
            let trimmedName = binding.variableName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard SpecImportHelpers.isValidEnvironmentVariableName(trimmedName) else { return false }
            let key = trimmedName.lowercased()
            guard !seenNames.contains(key) else { return false }
            seenNames.insert(key)
        }
        return true
    }

    var batchItemCount: Int {
        if case .batchPreview(let batch) = phase { return batch.specCount }
        if case .importingBatch(let batch) = phase { return batch.specCount }
        return batchEnvironmentBindings.count
    }
}