//
//  ProjectStore+RemoteSync.swift
//  Reqeast
//

import CloudKit
import Foundation
import os

private let logger = Logger(subsystem: "app.reqeast", category: "ProjectStore")

extension ProjectStore {

    // MARK: - Remote Batch

    /// Suppresses didSet observers and saveAll guards while applying a batch of remote changes.
    /// Uses defer to guarantee isLoading is reset even on early returns.
    /// Does not touch `importInProgress` — bulk import owns that flag independently.
    func withRemoteBatch(_ body: () -> Void) {
        isLoading = true
        defer {
            isLoading = false
            saveLocal()
        }
        body()
    }

    // MARK: - Remote Sync

    /// Applies an incoming remote record to the local store using last-writer-wins. Uses
    /// `remote.updatedAt >= local.updatedAt` (tie goes to server). `CloudSyncService+Records.localIsNewer`
    /// uses strict `>` from the opposite direction (local newer) — both rules reduce to
    /// "server wins a tie". Soft-deleted locals and tombstoned IDs block all upserts.
    func applyRemoteUpsert(_ item: some CloudSyncable, tombstones: DeletionTombstoneStore = .shared) {
        if importInProgress || syncApplyInProgress { return }
        if tombstones.contains(item.id) { return }

        switch item {
        case let project as Project:
            if let index = projects.firstIndex(where: { $0.id == project.id }) {
                guard projects[index].deletedAt == nil else { return }
                guard project.updatedAt >= projects[index].updatedAt else { return }
                projects[index] = project
            } else {
                projects.append(project)
            }
            ProjectIconService.shared.queueDownload(for: project)

        case let folder as ProjectFolder:
            if let index = folders.firstIndex(where: { $0.id == folder.id }) {
                guard folders[index].deletedAt == nil else { return }
                guard folder.updatedAt >= folders[index].updatedAt else { return }
                folders[index] = folder
            } else {
                folders.append(folder)
            }

        case let request as Request:
            if tombstones.contains(request.projectId) { return }
            if let index = requests.firstIndex(where: { $0.id == request.id }) {
                guard requests[index].deletedAt == nil else { return }
                guard request.updatedAt >= requests[index].updatedAt else { return }
                requests[index] = request
            } else {
                requests.append(request)
            }

        case let folder as RequestFolder:
            if tombstones.contains(folder.projectId) { return }
            if let index = requestFolders.firstIndex(where: { $0.id == folder.id }) {
                guard requestFolders[index].deletedAt == nil else { return }
                guard folder.updatedAt >= requestFolders[index].updatedAt else { return }
                requestFolders[index] = folder
            } else {
                requestFolders.append(folder)
            }

        case let env as ApiEnvironment:
            if tombstones.contains(env.projectId) { return }
            if let index = environments.firstIndex(where: { $0.id == env.id }) {
                guard environments[index].deletedAt == nil else { return }
                guard env.updatedAt >= environments[index].updatedAt else { return }
                environments[index] = env
            } else {
                environments.append(env)
            }

        case let document as SpecDocument:
            if tombstones.contains(document.projectId) { return }
            if let index = specDocuments.firstIndex(where: { $0.id == document.id }) {
                guard specDocuments[index].deletedAt == nil else { return }
                guard document.updatedAt >= specDocuments[index].updatedAt else { return }
                specDocuments[index] = document
            } else {
                specDocuments.append(document)
            }

        case let bundle as ProtoBundle:
            if tombstones.contains(bundle.projectId) { return }
            if let index = protoBundles.firstIndex(where: { $0.id == bundle.id }) {
                guard protoBundles[index].deletedAt == nil else { return }
                guard bundle.updatedAt >= protoBundles[index].updatedAt else { return }
                protoBundles[index] = bundle
            } else {
                protoBundles.append(bundle)
            }

        default:
            logger.fault("applyRemoteUpsert: unknown type \(type(of: item)). SyncRecordType switches are out of sync.")
            assertionFailure("applyRemoteUpsert missing case for \(type(of: item))")
        }
    }

    /// Marks all items as soft-deleted. Returns all affected UUIDs for tombstone tracking.
    @discardableResult
    func softDeleteAll() -> [UUID] {
        let now = Date()
        var ids: [UUID] = []

        isLoading = true
        for i in projects.indices {
            projects[i].deletedAt = now
            projects[i].updatedAt = now
            ids.append(projects[i].id)
        }
        for i in folders.indices {
            folders[i].deletedAt = now
            folders[i].updatedAt = now
            ids.append(folders[i].id)
        }
        for i in requests.indices {
            requests[i].deletedAt = now
            requests[i].updatedAt = now
            ids.append(requests[i].id)
        }
        for i in requestFolders.indices {
            requestFolders[i].deletedAt = now
            requestFolders[i].updatedAt = now
            ids.append(requestFolders[i].id)
        }
        for i in environments.indices {
            environments[i].deletedAt = now
            environments[i].updatedAt = now
            ids.append(environments[i].id)
        }
        for i in specDocuments.indices {
            specDocuments[i].deletedAt = now
            specDocuments[i].updatedAt = now
            ids.append(specDocuments[i].id)
        }
        for i in protoBundles.indices {
            protoBundles[i].deletedAt = now
            protoBundles[i].updatedAt = now
            ids.append(protoBundles[i].id)
        }
        isLoading = false

        UIStateStore.shared.resetAll()
        saveLocal()
        return ids
    }

    /// Removes a project and all its children (requests, request folders, environments).
    /// When queueCloudDeletes is true, queues CKSyncEngine deletions for each removed item.
    /// Records tombstones for the project and all children to prevent ghost records.
    func cascadeDeleteProject(id: UUID, queueCloudDeletes: Bool, tombstones: DeletionTombstoneStore = .shared) {
        let childRequests = requests.filter { $0.projectId == id }
        let childRequestFolders = requestFolders.filter { $0.projectId == id }
        let childEnvironments = environments.filter { $0.projectId == id }
        let childSpecDocuments = specDocuments.filter { $0.projectId == id }
        let childProtoBundles = protoBundles.filter { $0.projectId == id }

        // Record tombstones for the project and all its children
        var ids = [id]
        ids.append(contentsOf: childRequests.map(\.id))
        ids.append(contentsOf: childRequestFolders.map(\.id))
        ids.append(contentsOf: childEnvironments.map(\.id))
        ids.append(contentsOf: childSpecDocuments.map(\.id))
        ids.append(contentsOf: childProtoBundles.map(\.id))
        tombstones.add(ids: ids)

        for request in childRequests {
            SessionRegistry.shared.removeSession(for: request.id)
            UIStateStore.shared.removeState(for: request.id)
            if queueCloudDeletes {
                CloudSyncService.shared.queueDelete(recordType: .request, id: request.id)
            }
        }
        requests.removeAll { $0.projectId == id }

        for folder in childRequestFolders {
            if queueCloudDeletes {
                CloudSyncService.shared.queueDelete(recordType: .requestFolder, id: folder.id)
            }
        }
        requestFolders.removeAll { $0.projectId == id }

        for env in childEnvironments {
            if queueCloudDeletes {
                CloudSyncService.shared.queueDelete(recordType: .apiEnvironment, id: env.id)
            }
        }
        environments.removeAll { $0.projectId == id }

        for document in childSpecDocuments where queueCloudDeletes {
            CloudSyncService.shared.queueDelete(recordType: .specDocument, id: document.id)
        }
        specDocuments.removeAll { $0.projectId == id }

        for bundle in childProtoBundles {
            ProtoBundleService.deleteBundleDirectory(projectId: bundle.projectId, bundleId: bundle.id)
            if queueCloudDeletes {
                CloudSyncService.shared.queueDelete(recordType: .protoBundle, id: bundle.id)
            }
        }
        protoBundles.removeAll { $0.projectId == id }

        projects.removeAll { $0.id == id }
    }

    /// Removes a soft-deleted item from local arrays after CloudKit confirms the deletion.
    func purgeDeletedItem(recordType: SyncRecordType, id: UUID) {
        if importInProgress || syncApplyInProgress { return }
        switch recordType {
        case .project:
            projects.removeAll { $0.id == id && $0.deletedAt != nil }
        case .projectFolder:
            folders.removeAll { $0.id == id && $0.deletedAt != nil }
        case .request:
            requests.removeAll { $0.id == id && $0.deletedAt != nil }
        case .requestFolder:
            requestFolders.removeAll { $0.id == id && $0.deletedAt != nil }
        case .apiEnvironment:
            environments.removeAll { $0.id == id && $0.deletedAt != nil }
        case .specDocument:
            specDocuments.removeAll { $0.id == id && $0.deletedAt != nil }
        case .protoBundle:
            protoBundles.removeAll { $0.id == id && $0.deletedAt != nil }
        }
    }

    /// Bumps `updatedAt` on a specific item without triggering a cascade or save. Used by the
    /// sync engine's conflict-resolution rebound path so the re-queued save has a fresh
    /// timestamp that beats any concurrent remote change.
    func touchLocalItem(type: SyncRecordType, id: UUID) {
        switch type {
        case .project:
            if let i = projects.firstIndex(where: { $0.id == id }) { projects[i].touch() }
        case .projectFolder:
            if let i = folders.firstIndex(where: { $0.id == id }) { folders[i].touch() }
        case .request:
            if let i = requests.firstIndex(where: { $0.id == id }) { requests[i].touch() }
        case .requestFolder:
            if let i = requestFolders.firstIndex(where: { $0.id == id }) { requestFolders[i].touch() }
        case .apiEnvironment:
            if let i = environments.firstIndex(where: { $0.id == id }) { environments[i].touch() }
        case .specDocument:
            if let i = specDocuments.firstIndex(where: { $0.id == id }) { specDocuments[i].touch() }
        case .protoBundle:
            if let i = protoBundles.firstIndex(where: { $0.id == id }) { protoBundles[i].touch() }
        }
    }

    func applyRemoteDeletion(recordType: SyncRecordType, id: UUID) {
        if importInProgress || syncApplyInProgress { return }
        switch recordType {
        case .project:
            cascadeDeleteProject(id: id, queueCloudDeletes: false)

        case .projectFolder:
            for i in projects.indices where projects[i].folderId == id {
                projects[i].folderId = nil
            }
            folders.removeAll { $0.id == id }

        case .request:
            SessionRegistry.shared.removeSession(for: id)
            UIStateStore.shared.removeState(for: id)
            requests.removeAll { $0.id == id }

        case .requestFolder:
            for i in requests.indices where requests[i].folderId == id {
                requests[i].folderId = nil
            }
            requestFolders.removeAll { $0.id == id }

        case .apiEnvironment:
            environments.removeAll { $0.id == id }

        case .specDocument:
            specDocuments.removeAll { $0.id == id }

        case .protoBundle:
            if let bundle = protoBundles.first(where: { $0.id == id }) {
                ProtoBundleService.deleteBundleDirectory(projectId: bundle.projectId, bundleId: bundle.id)
            }
            protoBundles.removeAll { $0.id == id }
        }
    }
}
