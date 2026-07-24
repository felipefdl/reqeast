//
//  SpecExportService.swift
//  Reqeast
//

import Foundation

enum SpecExportDestination: Hashable {
    case file(URL)
    case clipboard
}

enum SpecExportService {

    static func isLinkedProject(_ project: Project) -> Bool {
        guard let specLink = project.specLink else { return false }
        return !specLink.isDetached
    }

    static func exportData(
        project: Project,
        store: ProjectStore,
        kind: SpecExportKind,
        options: SpecExportOptions
    ) async throws -> Data {
        let input = SpecExportMapper.buildInput(project: project, store: store, options: options)
        guard !input.operations.isEmpty else {
            throw SpecExportServiceError.noOperations
        }

        return try await exportOnBackground(input: input, kind: kind, options: options)
    }

    /// Exports after applying inverted Rule A selections from the review sheet.
    static func exportData(
        project: Project,
        store: ProjectStore,
        review: SpecExportReviewContext,
        selections: SpecExportSelections
    ) async throws -> Data {
        let input = buildExportInput(
            project: project,
            store: store,
            diff: review.diff,
            selections: selections,
            specProject: review.specProject,
            options: review.options
        )
        guard !input.operations.isEmpty else {
            throw SpecExportServiceError.noOperations
        }
        return try await exportOnBackground(input: input, kind: review.kind, options: review.options)
    }

    /// Builds a review diff for linked projects, or `nil` when export can proceed without review.
    @MainActor
    static func buildExportReviewContext(
        project: Project,
        store: ProjectStore,
        kind: SpecExportKind,
        options: SpecExportOptions
    ) async throws -> SpecExportReviewContext? {
        guard isLinkedProject(project), let specLink = project.specLink else {
            return nil
        }

        let (specBytes, bundleEntryPath) = try SpecSyncService.loadSpecBytes(projectId: project.id)
        let specProject = try await parseNormalizedProject(
            bytes: specBytes,
            specLink: specLink,
            bundleEntryPath: bundleEntryPath
        )
        let localProject = try await parseLocalExportProject(
            project: project,
            store: store,
            kind: kind,
            options: options
        )

        let bindings = SpecSyncService.buildBindings(projectId: project.id, store: store)
        var diff = try diffSpec(
            old: specProject,
            new: localProject,
            bindings: bindings,
            options: DiffOptions()
        )
        diff = SpecSyncService.enrichDiffWithConflicts(diff, store: store)

        guard hasReviewableDiff(diff) else {
            return nil
        }

        return SpecExportReviewContext(
            diff: diff,
            specProject: specProject,
            kind: kind,
            options: options
        )
    }

    static func defaultSelections(from diff: SpecSyncDiff) -> SpecExportSelections {
        SpecExportSelections(
            includeProjectOnlyPrimaryKeys: Set(diff.added.map(\.primaryKey)),
            includeSpecOnlyPrimaryKeys: [],
            useLocalVersionRequestIDs: Set(
                diff.modified.map(\.requestId) + diff.identityChanged.map(\.requestId)
            )
        )
    }

    static func hasReviewableDiff(_ diff: SpecSyncDiff) -> Bool {
        !diff.added.isEmpty
            || !diff.removed.isEmpty
            || !diff.modified.isEmpty
            || !diff.identityChanged.isEmpty
    }

    static func buildExportInput(
        project: Project,
        store: ProjectStore,
        diff: SpecSyncDiff,
        selections: SpecExportSelections,
        specProject: NormalizedProject,
        options: SpecExportOptions
    ) -> ExportProjectInput {
        var input = SpecExportMapper.buildInput(project: project, store: store, options: options)

        let projectOnlyKeys = Set(diff.added.map(\.primaryKey))
        let excludedProjectOnly = projectOnlyKeys.subtracting(selections.includeProjectOnlyPrimaryKeys)
        if !excludedProjectOnly.isEmpty {
            input.operations.removeAll { operation in
                guard let primaryKey = operation.specPrimaryKey else { return false }
                return excludedProjectOnly.contains(primaryKey)
            }
        }

        var operationIndexByPrimaryKey: [String: Int] = [:]
        for (index, operation) in input.operations.enumerated() {
            if let primaryKey = operation.specPrimaryKey {
                operationIndexByPrimaryKey[primaryKey] = index
            }
        }

        let alignToSpecRequestIDs = Set(
            diff.modified.map(\.requestId) + diff.identityChanged.map(\.requestId)
        ).subtracting(selections.useLocalVersionRequestIDs)

        for operationDiff in diff.modified where alignToSpecRequestIDs.contains(operationDiff.requestId) {
            guard let index = operationIndexByPrimaryKey[operationDiff.primaryKey] else { continue }
            let sortOrder = input.operations[index].sortOrder
            if let replacement = SpecExportMapper.mapNormalizedOperation(
                operationDiff.oldOperation,
                sortOrder: sortOrder
            ) {
                input.operations[index] = replacement
            }
        }

        for identityDiff in diff.identityChanged where alignToSpecRequestIDs.contains(identityDiff.requestId) {
            guard
                let requestId = UUID(uuidString: identityDiff.requestId),
                let request = store.requests.first(where: { $0.id == requestId && $0.projectId == project.id }),
                let primaryKey = request.specIdentity?.primaryKey,
                let index = operationIndexByPrimaryKey[primaryKey]
            else {
                continue
            }
            let sortOrder = input.operations[index].sortOrder
            if let replacement = SpecExportMapper.mapNormalizedOperation(
                identityDiff.oldOperation,
                sortOrder: sortOrder
            ) {
                input.operations[index] = replacement
            }
        }

        let includedSpecOnly = Set(diff.removed.map(\.primaryKey))
            .intersection(selections.includeSpecOnlyPrimaryKeys)
        if !includedSpecOnly.isEmpty {
            var nextSortOrder = (input.operations.map(\.sortOrder).max() ?? 0) + 1
            let specOperationsByKey = Dictionary(
                specProject.operations.map { ($0.primaryKey, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            for removed in diff.removed where includedSpecOnly.contains(removed.primaryKey) {
                let specOperation = specOperationsByKey[removed.primaryKey] ?? removed.operation
                if let exportOperation = SpecExportMapper.mapNormalizedOperation(
                    specOperation,
                    sortOrder: nextSortOrder
                ) {
                    input.operations.append(exportOperation)
                    nextSortOrder += 1
                }
            }
        }

        return input
    }

    static func canExport(
        project: Project,
        store: ProjectStore,
        diff: SpecSyncDiff,
        selections: SpecExportSelections,
        specProject: NormalizedProject,
        options: SpecExportOptions
    ) -> Bool {
        let input = buildExportInput(
            project: project,
            store: store,
            diff: diff,
            selections: selections,
            specProject: specProject,
            options: options
        )
        return !input.operations.isEmpty
    }

    /// Writes previously exported bytes to a user-selected file or the system clipboard.
    static func writeExport(_ data: Data, to destination: SpecExportDestination) throws {
        switch destination {
        case .file(let url):
            try data.write(to: url, options: .atomic)
        case .clipboard:
            guard let text = String(data: data, encoding: .utf8) else {
                throw SpecExportServiceError.clipboardEncodingFailed
            }
            PlatformClipboard.copy(text)
        }
    }

    /// End-to-end export: gather project slice, serialize on a background executor, then deliver.
    static func export(
        project: Project,
        store: ProjectStore,
        kind: SpecExportKind,
        options: SpecExportOptions,
        to destination: SpecExportDestination
    ) async throws {
        let data = try await exportData(project: project, store: store, kind: kind, options: options)
        try writeExport(data, to: destination)
    }

    @concurrent
    private static func exportOnBackground(
        input: ExportProjectInput,
        kind: SpecExportKind,
        options: SpecExportOptions
    ) async throws -> Data {
        do {
            switch kind {
            case .openapi:
                let exportOptions = ExportOpenApiOptions(
                    includeEnvironments: options.includeEnvironments,
                    includeDeprecated: options.includeDeprecatedAndStale
                )
                return try exportOpenapi(
                    input: input,
                    format: options.openApiFormat.exportFormat,
                    options: exportOptions
                )
            case .postman:
                let exportOptions = ExportPostmanOptions(
                    includeEnvironments: options.includeEnvironments,
                    includeDeprecated: options.includeDeprecatedAndStale
                )
                return try exportPostman(input: input, options: exportOptions)
            }
        } catch {
            throw SpecExportServiceError.exportFailed(error.localizedDescription)
        }
    }

    static func defaultFilename(
        for project: Project,
        kind: SpecExportKind,
        options: SpecExportOptions
    ) -> String {
        let base = sanitizedFilename(project.name)
        switch kind {
        case .openapi:
            switch options.openApiFormat {
            case .yaml: return "\(base)-openapi.yaml"
            case .json: return "\(base)-openapi.json"
            }
        case .postman:
            return "\(base)-postman.json"
        }
    }

    private static func sanitizedFilename(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "project" }
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        return trimmed
            .components(separatedBy: invalid)
            .joined(separator: "-")
            .replacingOccurrences(of: " ", with: "-")
    }

    @concurrent
    private static func parseNormalizedProject(
        bytes: Data,
        specLink: SpecLink,
        bundleEntryPath: String?
    ) async throws -> NormalizedProject {
        let sourceHint = sourceHint(for: specLink, bytes: bytes)
        let result = try parseSpec(
            bytes: bytes,
            sourceHint: sourceHint,
            bundleEntryPath: bundleEntryPath,
            options: SpecParseOptions()
        )
        return result.project
    }

    @concurrent
    private static func parseLocalExportProject(
        project: Project,
        store: ProjectStore,
        kind: SpecExportKind,
        options: SpecExportOptions
    ) async throws -> NormalizedProject {
        let input = SpecExportMapper.buildInput(project: project, store: store, options: options)
        guard !input.operations.isEmpty else {
            throw SpecExportServiceError.noOperations
        }

        let bytes = try await exportOnBackground(input: input, kind: kind, options: options)
        let sourceHint = exportSourceHint(for: kind, options: options)
        let result = try parseSpec(
            bytes: bytes,
            sourceHint: sourceHint,
            bundleEntryPath: nil,
            options: SpecParseOptions(enableSchemaSynthesis: false)
        )
        return result.project
    }

    private static func sourceHint(for specLink: SpecLink, bytes: Data) -> SpecSourceHint {
        switch specLink.format {
        case .postman:
            return .postman
        default:
            return SpecImportHelpers.sourceHint(for: bytes)
        }
    }

    private static func exportSourceHint(
        for kind: SpecExportKind,
        options: SpecExportOptions
    ) -> SpecSourceHint {
        switch kind {
        case .openapi:
            switch options.openApiFormat {
            case .yaml: .yaml
            case .json: .json
            }
        case .postman:
            .postman
        }
    }
}