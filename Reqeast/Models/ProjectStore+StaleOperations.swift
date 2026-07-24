//
//  ProjectStore+StaleOperations.swift
//  Reqeast
//

import Foundation

extension ProjectStore {

    /// Clears `isSpecStale` on a single request removed from a linked spec.
    func dismissSpecStale(for request: Request) {
        dismissSpecStale(for: [request])
    }

    /// Clears `isSpecStale` on multiple requests. User-initiated only — sync never auto-dismisses.
    func dismissSpecStale(for targets: [Request]) {
        var updated: [Request] = []
        for target in targets {
            guard let index = requests.firstIndex(where: { $0.id == target.id }) else { continue }
            guard requests[index].isSpecStale else { continue }
            requests[index].isSpecStale = false
            requests[index].touch()
            updated.append(requests[index])
        }
        guard !updated.isEmpty else { return }
        saveAll()
        CloudSyncService.shared.queueSaveBatch(requests: updated)
    }

    /// Deletes multiple requests. Used for user-initiated bulk removal of stale operations.
    func deleteRequests(_ targets: [Request], tombstones: DeletionTombstoneStore = .shared) {
        guard !targets.isEmpty else { return }
        let ids = Set(targets.map(\.id))
        tombstones.add(ids: Array(ids))

        for id in ids {
            SessionRegistry.shared.removeSession(for: id)
            SessionPersistenceService.shared.deleteSession(for: id)
            UIStateStore.shared.removeState(for: id)
            CloudSyncService.shared.queueDelete(recordType: .request, id: id)
        }

        requests.removeAll { ids.contains($0.id) }
        saveAll()
    }

    func staleRequests(for projectId: UUID) -> [Request] {
        requests(for: projectId).filter(\.isSpecStale)
    }
}