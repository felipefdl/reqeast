//
//  ProjectStore+Environments.swift
//  Reqeast
//

import Foundation
import SwiftUI

extension ProjectStore {

    // MARK: - Environment Operations

    func environments(for projectId: UUID) -> [ApiEnvironment] {
        environments.filter { $0.deletedAt == nil && $0.projectId == projectId }
    }

    /// Read/write binding for environments scoped to a project. Kept on the store (not in
    /// view body) so callers never construct `Binding(get:set:)` inline.
    func environmentsBinding(for projectId: UUID) -> Binding<[ApiEnvironment]> {
        Binding(
            get: { [weak self] in self?.environments(for: projectId) ?? [] },
            set: { [weak self] newValue in self?.updateEnvironments(newValue, for: projectId) }
        )
    }

    func activeEnvironment(for projectId: UUID) -> ApiEnvironment? {
        environments.first { $0.deletedAt == nil && $0.projectId == projectId && $0.isActive }
    }

    func updateEnvironments(_ envs: [ApiEnvironment], for projectId: UUID, tombstones: DeletionTombstoneStore = .shared) {
        let now = Date()
        let updated = envs.map { env -> ApiEnvironment in
            var e = env
            e.updatedAt = now
            return e
        }
        let removedIds = environments.filter { $0.projectId == projectId }.map(\.id)
        let newIds = Set(updated.map(\.id))
        let deletedIds = removedIds.filter { !newIds.contains($0) }
        if !deletedIds.isEmpty {
            tombstones.add(ids: deletedIds)
        }
        environments.removeAll { $0.projectId == projectId }
        environments.append(contentsOf: updated)
        saveAll()
        for env in updated {
            CloudSyncService.shared.queueSave(env)
        }
        for id in deletedIds {
            CloudSyncService.shared.queueDelete(recordType: .apiEnvironment, id: id)
        }
    }
}
