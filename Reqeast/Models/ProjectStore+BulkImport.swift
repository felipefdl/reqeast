//
//  ProjectStore+BulkImport.swift
//  Reqeast
//

import Foundation
import os

private let bulkImportLogger = Logger(subsystem: "app.reqeast", category: "ProjectStore.BulkImport")

enum BulkImportError: Error, Equatable {
    case encodingFailed(recordType: SyncRecordType, id: UUID)
    case recordTooLarge(recordType: SyncRecordType, id: UUID, byteCount: Int)
    case localPersistFailed
    case projectNotFound(id: UUID)
}

extension ProjectStore {

    /// Atomically imports a new project and its related items in four stages:
    /// stage in memory, validate CloudKit payload sizes, commit once, then `queueSaveBatch`.
    /// On validation failure the store is unchanged; on commit failure a pre-import snapshot is restored.
    @MainActor
    func performBulkImport(
        project: Project,
        folders: [RequestFolder],
        requests: [Request],
        environments: [ApiEnvironment],
        specDocument: SpecDocument? = nil
    ) throws {
        importInProgress = true
        defer { importInProgress = false }

        // Stage 1: stage in memory and touch typed models (not existential arrays).
        var stagedProject = project
        var stagedFolders = folders
        var stagedRequests = requests
        var stagedEnvironments = environments
        var stagedSpecDocument = specDocument

        stagedProject.touch()
        for index in stagedFolders.indices { stagedFolders[index].touch() }
        for index in stagedRequests.indices { stagedRequests[index].touch() }
        for index in stagedEnvironments.indices { stagedEnvironments[index].touch() }
        stagedSpecDocument?.touch()

        // Stage 2: validate CloudKit payloads before any store mutation.
        try validateBulkImportPayloads(
            project: stagedProject,
            folders: stagedFolders,
            requests: stagedRequests,
            environments: stagedEnvironments,
            specDocument: stagedSpecDocument
        )

        // Stage 3: commit once with rollback snapshot (AC12).
        let snapshot = BulkImportSnapshot(
            projects: projects,
            requestFolders: requestFolders,
            requests: self.requests,
            environments: self.environments,
            specDocuments: specDocuments
        )

        do {
            projects.append(stagedProject)
            requestFolders.append(contentsOf: stagedFolders)
            self.requests.append(contentsOf: stagedRequests)
            self.environments.append(contentsOf: stagedEnvironments)
            if let stagedSpecDocument {
                if let index = specDocuments.firstIndex(where: { $0.projectId == stagedSpecDocument.projectId }) {
                    specDocuments[index] = stagedSpecDocument
                } else {
                    specDocuments.append(stagedSpecDocument)
                }
            }
            try saveLocalOrThrow()
        } catch {
            restoreBulkImportSnapshot(snapshot)
            bulkImportLogger.fault("Bulk import commit failed, rolled back: \(error)")
            throw error
        }

        // Stage 4: single CloudKit batch sync (AC17).
        CloudSyncService.shared.queueSaveBatch(
            project: stagedProject,
            folders: stagedFolders,
            requests: stagedRequests,
            environments: stagedEnvironments,
            specDocument: stagedSpecDocument
        )

        if stagedProject.iconURL != nil {
            ProjectIconService.shared.queueDownload(for: stagedProject)
        }
    }

    /// Append-only merge into an existing project: updates the project in place, merges folders by
    /// name, and appends new requests/environments without removing or overwriting existing items.
    @MainActor
    func performBulkMerge(
        project: Project,
        folders: [RequestFolder],
        requests: [Request],
        environments: [ApiEnvironment],
        specDocument: SpecDocument? = nil
    ) throws {
        importInProgress = true
        defer { importInProgress = false }

        guard let projectIndex = projects.firstIndex(where: { $0.id == project.id }) else {
            throw BulkImportError.projectNotFound(id: project.id)
        }

        var stagedProject = project
        var stagedFolders = folders
        var stagedRequests = requests
        var stagedEnvironments = environments
        var stagedSpecDocument = specDocument

        stagedProject.touch()
        for index in stagedFolders.indices { stagedFolders[index].touch() }
        for index in stagedRequests.indices { stagedRequests[index].touch() }
        for index in stagedEnvironments.indices { stagedEnvironments[index].touch() }
        stagedSpecDocument?.touch()

        try validateBulkImportPayloads(
            project: stagedProject,
            folders: stagedFolders,
            requests: stagedRequests,
            environments: stagedEnvironments,
            specDocument: stagedSpecDocument
        )

        let snapshot = BulkImportSnapshot(
            projects: projects,
            requestFolders: requestFolders,
            requests: self.requests,
            environments: self.environments,
            specDocuments: specDocuments
        )

        do {
            projects[projectIndex] = stagedProject
            requestFolders.append(contentsOf: stagedFolders)
            self.requests.append(contentsOf: stagedRequests)
            self.environments.append(contentsOf: stagedEnvironments)
            if let stagedSpecDocument {
                if let index = specDocuments.firstIndex(where: { $0.projectId == stagedSpecDocument.projectId }) {
                    specDocuments[index] = stagedSpecDocument
                } else {
                    specDocuments.append(stagedSpecDocument)
                }
            }
            try saveLocalOrThrow()
        } catch {
            restoreBulkImportSnapshot(snapshot)
            bulkImportLogger.fault("Bulk merge commit failed, rolled back: \(error)")
            throw error
        }

        CloudSyncService.shared.queueSaveBatch(
            project: stagedProject,
            folders: stagedFolders,
            requests: stagedRequests,
            environments: stagedEnvironments,
            specDocument: stagedSpecDocument
        )

        if stagedProject.iconURL != nil {
            ProjectIconService.shared.queueDownload(for: stagedProject)
        }
    }

    private struct BulkImportSnapshot {
        let projects: [Project]
        let requestFolders: [RequestFolder]
        let requests: [Request]
        let environments: [ApiEnvironment]
        let specDocuments: [SpecDocument]
    }

    private func restoreBulkImportSnapshot(_ snapshot: BulkImportSnapshot) {
        projects = snapshot.projects
        requestFolders = snapshot.requestFolders
        requests = snapshot.requests
        environments = snapshot.environments
        specDocuments = snapshot.specDocuments
    }

    private func validateBulkImportPayloads(
        project: Project,
        folders: [RequestFolder],
        requests: [Request],
        environments: [ApiEnvironment],
        specDocument: SpecDocument?
    ) throws {
        try validateCloudKitPayload(project)
        for folder in folders {
            try validateCloudKitPayload(folder)
        }
        for request in requests {
            try validateCloudKitPayload(request)
        }
        for environment in environments {
            try validateCloudKitPayload(environment)
        }
        if let specDocument {
            let payload = specDocument.syncedRepresentation()
            try validateCloudKitPayload(payload)
        }
    }

    private func validateCloudKitPayload<T: CloudSyncable>(_ item: T) throws {
        let jsonData: Data
        do {
            jsonData = try JSONEncoder().encode(item)
        } catch {
            throw BulkImportError.encodingFailed(recordType: T.syncRecordType, id: item.id)
        }

        if jsonData.count > CloudSyncService.maxRecordPayloadBytes {
            throw BulkImportError.recordTooLarge(
                recordType: T.syncRecordType,
                id: item.id,
                byteCount: jsonData.count
            )
        }
    }
}