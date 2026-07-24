//
//  CloudSyncService+Migration.swift
//  Reqeast
//

import CloudKit
import Foundation
import os

private let logger = Logger(subsystem: "app.reqeast", category: "CloudSync.Migration")

extension CloudSyncService {

    /// One-shot: re-queues every non-deleted local item into CKSyncEngine's pending-changes state.
    /// Required because pre-CKSyncEngine state did not track per-record sync status. Without this
    /// first run, existing local data would never be uploaded (CKSyncEngine only tracks changes
    /// made after its engine was started).
    ///
    /// The flag is cleared when: (1) user switches iCloud accounts, (2) server reports
    /// `encryptedDataReset`, (3) the Reqeast zone is deleted or purged remotely. In those cases
    /// this runs again so local data re-uploads into the fresh zone.
    func runMigrationIfNeeded() {
        guard !storage.bool(forKey: Self.migrationCompleteKey) else { return }
        guard let engine = syncEngine else { return }

        logger.info("Running one-time migration to CKSyncEngine")

        let store = ProjectStore.shared
        var changes: [CKSyncEngine.PendingRecordZoneChange] = []
        for item in store.projects where item.deletedAt == nil { changes.append(.saveRecord(recordID(for: item))) }
        for item in store.folders where item.deletedAt == nil { changes.append(.saveRecord(recordID(for: item))) }
        for item in store.requests where item.deletedAt == nil { changes.append(.saveRecord(recordID(for: item))) }
        for item in store.requestFolders where item.deletedAt == nil { changes.append(.saveRecord(recordID(for: item))) }
        for item in store.environments where item.deletedAt == nil { changes.append(.saveRecord(recordID(for: item))) }
        for item in store.specDocuments where item.deletedAt == nil { changes.append(.saveRecord(recordID(for: item))) }
        for item in store.protoBundles where item.deletedAt == nil { changes.append(.saveRecord(recordID(for: item))) }
        engine.state.add(pendingRecordZoneChanges: changes)

        storage.set(true, forKey: Self.migrationCompleteKey)
        logger.info("Migration complete: queued \(changes.count) records")
    }
}
