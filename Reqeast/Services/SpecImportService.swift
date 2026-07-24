//
//  SpecImportService.swift
//  Reqeast
//

import Foundation
import os

private let specImportLogger = Logger(subsystem: "app.reqeast", category: "SpecImport")

struct SpecImportRequest: Equatable, Hashable {
    var bytes: Data
    var sourceHint: SpecSourceHint
    var source: SpecSource
    var sourceURL: String? = nil
    var gitRef: GitSourceRef? = nil
    var format: SpecFormat = .openapi
    /// Absolute path to the bundle entry file when importing a multi-file OpenAPI bundle.
    var bundleEntryPath: String? = nil
    /// Source bundle directory to copy into Application Support on commit.
    var bundleSourceDirectory: URL? = nil
    /// macOS folder URL to persist as a security-scoped bookmark when linking to spec.
    var bookmarkSourceFolder: URL? = nil
}

/// Staged import payload produced by `preview`. Safe to show in UI; no store writes until `commit`.
struct SpecImportMergePlan: Equatable {
    var project: Project
    var foldersToAdd: [RequestFolder]
    var requestsToAdd: [Request]
    var environmentsToAdd: [ApiEnvironment]
    var duplicateWarnings: [SpecWarning]
    var importableOperationCount: Int
    var specsProjectId: UUID
}

struct SpecImportMergePreview: Equatable {
    var duplicateWarnings: [SpecWarning]
    var importableOperationCount: Int
}

struct SpecImportPreview: Equatable {
    var projectName: String
    var operationCount: Int
    var warnings: [SpecWarning]
    var mapped: SpecImportMappedResult

    var bytes: Data
    var sourceHint: SpecSourceHint
    var source: SpecSource
    var sourceURL: String?
    var format: SpecFormat
    var contentFingerprint: String
    var options: SpecImportOptions
    var projectId: UUID
    var specFileName: String
    var bundleEntryPath: String?
    var bundleSourceDirectory: URL?
    var gitRef: GitSourceRef?
    var bookmarkSourceFolder: URL?
}

enum SpecImportService {

    #if DEBUG
    /// Overrides the specs root for isolated unit tests.
    static var specsRootDirectoryOverride: URL? {
        get { _specsRootDirectoryOverride }
        set { _specsRootDirectoryOverride = newValue }
    }

    private static var _specsRootDirectoryOverride: URL?
    #endif

    @concurrent
    private static func parseSpecOnBackground(
        bytes: Data,
        sourceHint: SpecSourceHint,
        bundleEntryPath: String?,
        options: SpecParseOptions
    ) async throws -> SpecImportResult {
        try parseSpec(
            bytes: bytes,
            sourceHint: sourceHint,
            bundleEntryPath: bundleEntryPath,
            options: options
        )
    }

    static func preview(
        bytes: Data,
        sourceHint: SpecSourceHint,
        source: SpecSource,
        options: SpecImportOptions = .default,
        sourceURL: String? = nil,
        format: SpecFormat = .openapi
    ) async throws -> SpecImportPreview {
        try await preview(
            SpecImportRequest(
                bytes: bytes,
                sourceHint: sourceHint,
                source: source,
                sourceURL: sourceURL,
                format: format
            ),
            options: options
        )
    }

    static func preview(
        _ request: SpecImportRequest,
        options: SpecImportOptions = .default
    ) async throws -> SpecImportPreview {
        let resolvedHint: SpecSourceHint = if SpecImportHelpers.isPostmanCollection(request.bytes) {
            .postman
        } else if SpecImportHelpers.isHarLog(request.bytes) {
            .har
        } else {
            request.sourceHint
        }
        let format = SpecImportHelpers.detectedFormat(
            bytes: request.bytes,
            sourceHint: resolvedHint
        )

        let parseResult = try await parseSpecOnBackground(
            bytes: request.bytes,
            sourceHint: resolvedHint,
            bundleEntryPath: request.bundleEntryPath,
            options: options.parseOptions
        )

        let projectId = UUID()
        var mapped = SpecImportMapper.map(
            parseResult,
            projectId: projectId,
            options: options
        )

        let iconCandidates = await ProjectIconResolver.candidateURLs(
            specIconURL: parseResult.project.iconUrl,
            sourceURL: request.sourceURL
        )
        if let resolvedIconURL = await ProjectIconResolver.resolveFirstAvailable(from: iconCandidates) {
            mapped.project.iconURL = resolvedIconURL
        }

        guard !mapped.requests.isEmpty else {
            throw SpecImportError.InvalidSpec(
                String(localized: "No importable operations found in this spec.")
            )
        }

        return SpecImportPreview(
            projectName: mapped.project.name,
            operationCount: mapped.requests.count,
            warnings: parseResult.warnings + mapped.warnings,
            mapped: mapped,
            bytes: request.bytes,
            sourceHint: resolvedHint,
            source: request.source,
            sourceURL: request.sourceURL,
            format: format,
            contentFingerprint: parseResult.contentFingerprint,
            options: options,
            projectId: projectId,
            specFileName: specFileName(
                bytes: request.bytes,
                sourceHint: resolvedHint,
                bundleEntryPath: request.bundleEntryPath
            ),
            bundleEntryPath: request.bundleEntryPath,
            bundleSourceDirectory: request.bundleSourceDirectory,
            gitRef: request.gitRef,
            bookmarkSourceFolder: request.bookmarkSourceFolder
        )
    }

    @MainActor
    static func commitGroupedBatch(
        preview: SpecImportBatchPreview,
        projectName: String,
        environmentName: String,
        environmentBindings: [SpecImportEnvironmentBinding],
        to store: ProjectStore,
        options: SpecImportOptions
    ) throws -> Project {
        try validateGroupedEnvironment(environmentName: environmentName, bindings: environmentBindings)

        let projectId = UUID()
        let mapped = combineGroupedBatch(
            from: preview.items,
            projectId: projectId,
            projectName: projectName,
            environmentName: environmentName,
            environmentBindings: environmentBindings
        )

        try writeGroupedSpecsToDisk(items: preview.items, projectId: projectId)

        var project = mapped.project
        project.name = projectName

        var requests = mapped.requests
        try SpecSnapshotService.applySnapshots(to: &requests, projectId: projectId)

        try store.performBulkImport(
            project: project,
            folders: mapped.folders,
            requests: requests,
            environments: mapped.environments,
            specDocument: nil
        )

        guard let imported = store.projects.first(where: { $0.id == projectId }) else {
            throw SpecImportError.from(
                message: String(localized: "The imported project could not be found."),
                kind: .invalidSpec
            )
        }
        return imported
    }

    @MainActor
    static func commitBatch(
        preview: SpecImportBatchPreview,
        to store: ProjectStore,
        options: SpecImportOptions
    ) throws -> [Project] {
        var imported: [Project] = []
        for item in preview.items {
            var toCommit = item
            toCommit.options = options
            try commitNewProject(preview: toCommit, to: store)
            if let project = store.projects.first(where: { $0.id == toCommit.projectId }) {
                imported.append(project)
            }
        }
        return imported
    }

    @MainActor
    static func commit(
        preview: SpecImportPreview,
        to store: ProjectStore,
        importTarget: SpecImportTarget = .newProject,
        targetProjectId: UUID? = nil
    ) throws {
        switch importTarget {
        case .newProject:
            try commitNewProject(preview: preview, to: store)
        case .existingProject:
            guard let targetProjectId else {
                throw SpecImportError.from(
                    message: String(localized: "Choose a project to import into."),
                    kind: .invalidSpec
                )
            }
            let plan = try planMerge(preview: preview, into: store, targetProjectId: targetProjectId)
            try writeSpecToDisk(preview: preview, projectId: plan.specsProjectId)
            var requestsToAdd = plan.requestsToAdd
            try SpecSnapshotService.applySnapshots(to: &requestsToAdd, projectId: plan.specsProjectId)
            let specDocument = SpecSnapshotService.makeLinkedSpecDocument(
                project: plan.project,
                specFileName: preview.specFileName
            )
            try store.performBulkMerge(
                project: plan.project,
                folders: plan.foldersToAdd,
                requests: requestsToAdd,
                environments: plan.environmentsToAdd,
                specDocument: specDocument
            )
        }
    }

    @MainActor
    static func mergePreview(
        preview: SpecImportPreview,
        in store: ProjectStore,
        targetProjectId: UUID
    ) -> SpecImportMergePreview? {
        guard store.projects.contains(where: { $0.id == targetProjectId && $0.deletedAt == nil }) else {
            return nil
        }

        let duplicateWarnings = duplicateOperationWarnings(
            requests: preview.mapped.requests,
            existingRequests: store.requests(for: targetProjectId)
        )
        let skippedCount = duplicateWarnings.count
        return SpecImportMergePreview(
            duplicateWarnings: duplicateWarnings,
            importableOperationCount: max(0, preview.operationCount - skippedCount)
        )
    }

    @MainActor
    static func planMerge(
        preview: SpecImportPreview,
        into store: ProjectStore,
        targetProjectId: UUID
    ) throws -> SpecImportMergePlan {
        guard let projectIndex = store.projects.firstIndex(where: {
            $0.id == targetProjectId && $0.deletedAt == nil
        }) else {
            throw SpecImportError.from(
                message: String(localized: "The selected project could not be found."),
                kind: .invalidSpec
            )
        }

        var project = store.projects[projectIndex]
        project.specLink = makeSpecLink(from: preview)
        if project.iconURL == nil, let iconURL = preview.mapped.project.iconURL {
            project.iconURL = iconURL
        }

        let existingFolders = store.requestFolders(for: targetProjectId)
        var folderIdByName: [String: UUID] = [:]
        for folder in existingFolders {
            let key = normalizedFolderName(folder.name)
            if folderIdByName[key] == nil {
                folderIdByName[key] = folder.id
            }
        }

        var foldersToAdd: [RequestFolder] = []
        var folderIdRemap: [UUID: UUID] = [:]

        for folder in preview.mapped.folders {
            let key = normalizedFolderName(folder.name)
            if let existingId = folderIdByName[key] {
                folderIdRemap[folder.id] = existingId
            } else {
                var newFolder = folder
                newFolder.id = UUID()
                newFolder.projectId = targetProjectId
                folderIdRemap[folder.id] = newFolder.id
                folderIdByName[key] = newFolder.id
                foldersToAdd.append(newFolder)
            }
        }

        let existingRequests = store.requests(for: targetProjectId)
        let duplicateWarnings = duplicateOperationWarnings(
            requests: preview.mapped.requests,
            existingRequests: existingRequests
        )
        let duplicateKeys = Set(duplicateWarnings.compactMap(\.operationRef))

        var requestsToAdd: [Request] = []
        for request in preview.mapped.requests {
            if let primaryKey = request.specIdentity?.primaryKey, duplicateKeys.contains(primaryKey) {
                continue
            }

            var merged = request
            merged.id = UUID()
            merged.projectId = targetProjectId
            if let folderId = request.folderId {
                merged.folderId = folderIdRemap[folderId]
            }
            requestsToAdd.append(merged)
        }

        let existingEnvironmentNames = Set(
            store.environments(for: targetProjectId).map { normalizedFolderName($0.name) }
        )
        var environmentsToAdd: [ApiEnvironment] = []
        for environment in preview.mapped.environments {
            let key = normalizedFolderName(environment.name)
            guard !existingEnvironmentNames.contains(key) else { continue }
            var merged = environment
            merged.id = UUID()
            merged.projectId = targetProjectId
            environmentsToAdd.append(merged)
        }

        return SpecImportMergePlan(
            project: project,
            foldersToAdd: foldersToAdd,
            requestsToAdd: requestsToAdd,
            environmentsToAdd: environmentsToAdd,
            duplicateWarnings: duplicateWarnings,
            importableOperationCount: requestsToAdd.count,
            specsProjectId: targetProjectId
        )
    }

    @MainActor
    private static func commitNewProject(
        preview: SpecImportPreview,
        to store: ProjectStore
    ) throws {
        try writeSpecToDisk(preview: preview, projectId: preview.projectId)

        var project = preview.mapped.project
        project.name = preview.projectName
        project.specLink = makeSpecLink(from: preview)

        var requests = preview.mapped.requests
        try SpecSnapshotService.applySnapshots(to: &requests, projectId: preview.projectId)

        let specDocument = SpecSnapshotService.makeLinkedSpecDocument(
            project: project,
            specFileName: preview.specFileName
        )
        try store.performBulkImport(
            project: project,
            folders: preview.mapped.folders,
            requests: requests,
            environments: preview.mapped.environments,
            specDocument: specDocument
        )
    }

    private static func duplicateOperationWarnings(
        requests: [Request],
        existingRequests: [Request]
    ) -> [SpecWarning] {
        let existingKeys = Set(existingRequests.compactMap { $0.specIdentity?.primaryKey })
        var warnings: [SpecWarning] = []

        for request in requests {
            guard let primaryKey = request.specIdentity?.primaryKey else { continue }
            guard existingKeys.contains(primaryKey) else { continue }
            warnings.append(
                SpecWarning(
                    code: "DUPLICATE_OPERATION",
                    message: String(localized: "Skipped \(primaryKey): operation already exists in project."),
                    operationRef: primaryKey
                )
            )
        }

        return warnings
    }

    private static func normalizedFolderName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func prefixedFolderName(specName: String, folderName: String) -> String {
        let trimmedSpec = specName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedFolder = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFolder.isEmpty else { return trimmedSpec }
        if trimmedFolder.caseInsensitiveCompare(trimmedSpec) == .orderedSame {
            return trimmedSpec
        }
        return "\(trimmedSpec) / \(trimmedFolder)"
    }

    private static func writeGroupedSpecsToDisk(items: [SpecImportPreview], projectId: UUID) throws {
        let projectDir = specsDirectory(for: projectId)
        let sourcesDir = projectDir.appendingPathComponent("sources", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: sourcesDir, withIntermediateDirectories: true)
            for (index, item) in items.enumerated() {
                let fileName: String
                if let path = item.sourceURL, !path.isEmpty {
                    fileName = URL(fileURLWithPath: path).lastPathComponent
                } else {
                    let ext = item.sourceHint == .json ? "json" : "yaml"
                    fileName = "spec-\(index + 1).\(ext)"
                }
                try item.bytes.write(to: sourcesDir.appendingPathComponent(fileName), options: .atomic)
            }
        } catch {
            specImportLogger.error("Failed to write grouped spec files for \(projectId): \(error)")
            throw SpecImportError.from(
                message: String(localized: "Could not save spec file to disk."),
                kind: .parseError
            )
        }
    }

    private static func makeSpecLink(from preview: SpecImportPreview) -> SpecLink {
        SpecLink(
            format: preview.format,
            source: preview.source,
            contentFingerprint: preview.contentFingerprint,
            importedAt: Date(),
            sourceURL: preview.sourceURL,
            gitRef: preview.gitRef,
            specRevision: 0,
            isDetached: preview.options.linkToSpec == .detached
        )
    }

    // MARK: - Disk (AC5)

    static func specsRootDirectory() -> URL {
        #if DEBUG
        if let override = _specsRootDirectoryOverride {
            return override
        }
        #endif

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return appSupport
            .appendingPathComponent("reqeast", isDirectory: true)
            .appendingPathComponent(StorageEnvironment.specsDirName, isDirectory: true)
    }

    static func specsDirectory(for projectId: UUID) -> URL {
        specsRootDirectory().appendingPathComponent(projectId.uuidString, isDirectory: true)
    }

    private static func writeSpecToDisk(preview: SpecImportPreview, projectId: UUID) throws {
        let projectDir = specsDirectory(for: projectId)
        let fingerprintURL = projectDir.appendingPathComponent("fingerprint.txt")

        do {
            try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)

            if let bundleSource = preview.bundleSourceDirectory {
                let bundleDest = projectDir.appendingPathComponent("bundle", isDirectory: true)
                if FileManager.default.fileExists(atPath: bundleDest.path) {
                    try FileManager.default.removeItem(at: bundleDest)
                }
                try FileManager.default.copyItem(at: bundleSource, to: bundleDest)
            } else {
                let specURL = projectDir.appendingPathComponent(preview.specFileName)
                try preview.bytes.write(to: specURL, options: .atomic)
            }

            try preview.contentFingerprint.write(to: fingerprintURL, atomically: true, encoding: .utf8)

            if preview.options.linkToSpec == .linked,
               preview.source == .localBookmark,
               let folderURL = preview.bookmarkSourceFolder {
                try SpecBookmarkStore.saveBookmark(for: projectId, folderURL: folderURL)
            }
        } catch {
            specImportLogger.error("Failed to write spec files for \(projectId): \(error)")
            throw SpecImportError.from(
                message: String(localized: "Could not save spec file to disk."),
                kind: .parseError
            )
        }
    }

    private static func specFileName(
        bytes: Data,
        sourceHint: SpecSourceHint,
        bundleEntryPath: String? = nil
    ) -> String {
        if let bundleEntryPath {
            return "bundle/\(URL(fileURLWithPath: bundleEntryPath).lastPathComponent)"
        }
        switch sourceHint {
        case .json:
            return "spec.json"
        case .yaml:
            return "spec.yaml"
        case .har:
            return "capture.har"
        case .graphql:
            return "schema.graphql"
        case .unknown, .openApi, .postman, .insomnia, .bruno, .asyncApi:
            break
        }

        var index = bytes.startIndex
        while index < bytes.endIndex {
            let byte = bytes[index]
            if byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\n")
                || byte == UInt8(ascii: "\r") || byte == UInt8(ascii: "\t") {
                index = bytes.index(after: index)
                continue
            }
            return byte == UInt8(ascii: "{") ? "spec.json" : "spec.yaml"
        }

        return "spec.yaml"
    }
}