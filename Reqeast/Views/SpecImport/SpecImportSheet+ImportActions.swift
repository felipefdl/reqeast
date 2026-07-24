//
//  SpecImportSheet+ImportActions.swift
//  Reqeast
//

import SwiftUI

extension SpecImportSheet {

    func repreview(with options: SpecImportOptions, from preview: SpecImportPreview) {
        isRefreshingPreview = true
        startTask {
            defer { isRefreshingPreview = false }
            do {
                let updated = try await SpecImportService.preview(
                    bytes: preview.bytes,
                    sourceHint: preview.sourceHint,
                    source: preview.source,
                    options: options,
                    sourceURL: preview.sourceURL,
                    format: preview.format
                )
                var next = updated
                let trimmedName = projectName.trimmingCharacters(in: .whitespaces)
                if !trimmedName.isEmpty {
                    next.projectName = trimmedName
                }
                phase = .preview(next)
            } catch {
                phase = .error(SpecImportError.from(error))
            }
        }
    }

    func repreviewBatch(with options: SpecImportOptions, from batch: SpecImportBatchPreview) {
        isRefreshingPreview = true
        startTask {
            defer { isRefreshingPreview = false }
            do {
                var updatedItems: [SpecImportPreview] = []
                updatedItems.reserveCapacity(batch.items.count)
                for preview in batch.items {
                    let updated = try await SpecImportService.preview(
                        bytes: preview.bytes,
                        sourceHint: preview.sourceHint,
                        source: preview.source,
                        options: options,
                        sourceURL: preview.sourceURL,
                        format: preview.format
                    )
                    updatedItems.append(updated)
                }
                let bindings = SpecImportService.makeEnvironmentBindings(
                    for: updatedItems,
                    preserving: batchEnvironmentBindings
                )
                batchEnvironmentBindings = bindings
                phase = .batchPreview(
                    SpecImportBatchPreview(
                        items: updatedItems,
                        sourceFolderName: batch.sourceFolderName
                    )
                )
            } catch {
                phase = .error(SpecImportError.from(error))
            }
        }
    }

    func commitBatchImport(batch: SpecImportBatchPreview) {
        guard canCommitBatchImport else { return }

        phase = .importingBatch(batch)
        startTask {
            do {
                if groupSpecsInOneProject {
                    let project = try SpecImportService.commitGroupedBatch(
                        preview: batch,
                        projectName: projectName.trimmingCharacters(in: .whitespaces),
                        environmentName: batchEnvironmentName,
                        environmentBindings: batchEnvironmentBindings,
                        to: store,
                        options: importOptions
                    )
                    onImported(project)
                } else {
                    let imported = try SpecImportService.commitBatch(
                        preview: batch,
                        to: store,
                        options: importOptions
                    )
                    if let project = imported.sorted(by: {
                        $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                    }).first {
                        onImported(project)
                    }
                }
                dismiss()
            } catch {
                phase = .error(SpecImportError.from(error))
            }
        }
    }

    func commitImport(preview: SpecImportPreview) {
        guard canCommitImport else { return }

        phase = .importing(preview)
        startTask {
            do {
                var toCommit = preview
                toCommit.options = importOptions
                if importTarget == .newProject {
                    toCommit.projectName = projectName.trimmingCharacters(in: .whitespaces)
                }
                try SpecImportService.commit(
                    preview: toCommit,
                    to: store,
                    importTarget: importTarget,
                    targetProjectId: targetProjectId
                )
                let importedProjectId = importTarget == .existingProject
                    ? targetProjectId
                    : preview.projectId
                if let importedProjectId,
                   let project = store.projects.first(where: { $0.id == importedProjectId }) {
                    onImported(project)
                }
                dismiss()
            } catch {
                phase = .error(SpecImportError.from(error))
            }
        }
    }

    func applyPreview(_ preview: SpecImportPreview) {
        var next = preview
        projectName = next.projectName
        importOptions = next.options
        #if DEBUG
        if SpecImportUITestSupport.shouldDefaultLinkToSpec {
            importOptions.linkToSpec = .linked
            next.options.linkToSpec = .linked
        }
        #endif
        importTarget = .newProject
        targetProjectId = nil
        phase = .preview(next)
    }

    func applyBatchPreview(_ batch: SpecImportBatchPreview) {
        importOptions = batch.items.first?.options ?? importOptions
        importTarget = .newProject
        targetProjectId = nil
        groupSpecsInOneProject = true
        projectName = batch.sourceFolderName
        batchEnvironmentName = batch.sourceFolderName
        batchEnvironmentBindings = SpecImportService.makeEnvironmentBindings(for: batch.items)
        phase = .batchPreview(batch)
    }

    func validateByteCount(_ count: Int) throws {
        guard count <= SpecImportHelpers.maxBytes else {
            throw SpecImportError.from(
                message: String(localized: "Content exceeds the 5 MiB size limit."),
                kind: .invalidSpec
            )
        }
    }
}