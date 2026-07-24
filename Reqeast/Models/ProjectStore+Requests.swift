//
//  ProjectStore+Requests.swift
//  Reqeast
//

import Foundation

extension ProjectStore {

    // MARK: - Request Folder Operations

    func requestFolders(for projectId: UUID) -> [RequestFolder] {
        requestFolders
            .filter { $0.deletedAt == nil && $0.projectId == projectId }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func addRequestFolder(_ folder: RequestFolder) {
        requestFolders.append(folder)
        saveAll()
        CloudSyncService.shared.queueSave(folder)
    }

    func updateRequestFolder(_ folder: RequestFolder) {
        guard let index = requestFolders.firstIndex(where: { $0.id == folder.id }) else { return }
        var updated = folder
        updated.touch()
        requestFolders[index] = updated
        saveAll()
        CloudSyncService.shared.queueSave(requestFolders[index])
    }

    func deleteRequestFolder(_ folder: RequestFolder, tombstones: DeletionTombstoneStore = .shared) {
        tombstones.add(ids: [folder.id])
        let affectedRequests = requests.enumerated().filter { $0.element.folderId == folder.id }
        isLoading = true
        for i in requests.indices where requests[i].folderId == folder.id {
            requests[i].folderId = nil
            requests[i].updatedAt = Date()
        }
        requestFolders.removeAll { $0.id == folder.id }
        isLoading = false
        saveAll()
        CloudSyncService.shared.queueDelete(recordType: .requestFolder, id: folder.id)
        for (i, _) in affectedRequests {
            CloudSyncService.shared.queueSave(requests[i])
        }
    }

    func moveRequest(_ request: Request, toFolder folder: RequestFolder?) {
        guard let index = requests.firstIndex(where: { $0.id == request.id }) else { return }
        requests[index].folderId = folder?.id
        requests[index].touch()
        saveAll()
        CloudSyncService.shared.queueSave(requests[index])
    }

    // MARK: - Request Operations

    func requests(for projectId: UUID) -> [Request] {
        requests
            .filter { $0.deletedAt == nil && $0.projectId == projectId }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    func requests(for projectId: UUID, inFolder folderId: UUID?) -> [Request] {
        requests
            .filter { $0.deletedAt == nil && $0.projectId == projectId && $0.folderId == folderId }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    func unfolderedRequests(for projectId: UUID) -> [Request] {
        requests(for: projectId, inFolder: nil)
    }

    func addRequest(_ request: Request) {
        requests.append(request)
        saveAll()
        CloudSyncService.shared.queueSave(request)
    }

    /// In-memory update only: no local save, no CloudSync enqueue. Called per-keystroke from
    /// bindings, so persistence MUST be deferred to send, rename, or background lifecycle.
    /// Do not queueSave from here or iCloud will be flooded with writes on every keypress.
    func updateRequest(_ request: Request) {
        if let index = requests.firstIndex(where: { $0.id == request.id }) {
            requests[index] = request
        }
    }

    func renameRequest(_ request: Request, to name: String) {
        guard let index = requests.firstIndex(where: { $0.id == request.id }) else { return }
        requests[index].name = name
        requests[index].isRenamed = true
        requests[index].touch()
        saveAll()
        CloudSyncService.shared.queueSave(requests[index])
    }

    func deleteRequest(_ request: Request, tombstones: DeletionTombstoneStore = .shared) {
        tombstones.add(ids: [request.id])
        requests.removeAll { $0.id == request.id }
        SessionRegistry.shared.removeSession(for: request.id)
        SessionPersistenceService.shared.deleteSession(for: request.id)
        UIStateStore.shared.removeState(for: request.id)
        saveAll()
        CloudSyncService.shared.queueDelete(recordType: .request, id: request.id)
    }

    @discardableResult
    func duplicateRequest(_ request: Request) -> Request {
        var newRequest = request
        newRequest.id = UUID()
        newRequest.name = "\(request.name) (copy)"
        newRequest.createdAt = Date()
        newRequest.updatedAt = Date()
        requests.append(newRequest)
        saveAll()
        CloudSyncService.shared.queueSave(newRequest)
        return newRequest
    }
}
