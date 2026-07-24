//
//  CloudSyncService+FetchHandling.swift
//  Reqeast
//

import CloudKit
import Foundation
import os

private let logger = Logger(subsystem: "app.reqeast", category: "CloudSync.Fetch")

extension CloudSyncService {

    func handleFetchedChanges(_ event: CKSyncEngine.Event.FetchedRecordZoneChanges) {
        if !event.modifications.isEmpty || !event.deletions.isEmpty {
            logger.info("Received remote changes: \(event.modifications.count) upserts, \(event.deletions.count) deletes")
        }

        let store = ProjectStore.shared
        store.withRemoteBatch {
            for modification in event.modifications {
                let record = modification.record
                guard let parsed = parseRecordName(record.recordID.recordName) else { continue }

                // Reject records that were soft-deleted locally; re-queue the CK delete
                if DeletionTombstoneStore.shared.contains(parsed.id) {
                    logger.info("Rejecting tombstoned record: \(parsed.type.rawValue)/\(parsed.id.uuidString.prefix(8))")
                    syncEngine?.state.add(pendingRecordZoneChanges: [.deleteRecord(record.recordID)])
                    continue
                }

                logger.info("Remote upsert: \(parsed.type.rawValue)/\(parsed.id.uuidString.prefix(8))")

                if decodeAndApplyUpsert(record: record, type: parsed.type, store: store) {
                    cacheSystemFields(of: record)
                    if parsed.type == .specDocument {
                        scheduleSpecBytesHydrationFallbackIfNeeded(recordId: parsed.id, store: store)
                    }
                } else {
                    logger.fault("Remote decode failed for \(record.recordID.recordName); backing up payload")
                    backupCorruptRemoteRecord(record)
                    syncState.report(RequestError(
                        kind: .cloudDecodeError,
                        message: String(localized: "A record from iCloud could not be read on this device. It may have been written by a newer app version. See corrupt-records folder.")
                    ))
                }
            }

            for deletion in event.deletions {
                guard let parsed = parseRecordName(deletion.recordID.recordName) else { continue }
                logger.info("Remote delete: \(parsed.type.rawValue)/\(parsed.id.uuidString.prefix(8))")
                dropCachedRecord(recordName: deletion.recordID.recordName)
                store.applyRemoteDeletion(recordType: parsed.type, id: parsed.id)
            }

            persistLastKnownRecords()
        }
    }

    /// Attempts SafeFetch re-hydration when a linked `SpecDocument` arrived without a CKAsset.
    @discardableResult
    func scheduleSpecBytesHydrationFallbackIfNeeded(recordId: UUID, store: ProjectStore) -> Task<Void, Never>? {
        guard let document = store.specDocuments.first(where: { $0.id == recordId }),
              document.isReadOnlyDueToMissingAsset else {
            return nil
        }

        let projectId = document.projectId
        return Task { @MainActor in
            guard let currentDocument = store.specDocuments.first(where: { $0.id == recordId }) else {
                return
            }
            let specLink = store.projects.first(where: { $0.id == projectId })?.specLink
            _ = await SpecSnapshotService.hydrateSpecBytesFromSourceIfNeeded(
                document: currentDocument,
                specLink: specLink,
                store: store
            )
        }
    }

    func handleFetchedDatabaseChanges(_ event: CKSyncEngine.Event.FetchedDatabaseChanges) {
        for deletion in event.deletions where deletion.zoneID == zoneID {
            switch deletion.reason {
            case .purged:
                logger.info("Zone purged by user, clearing local data and recording tombstones")
                clearLocalDataWithTombstones()

            case .encryptedDataReset:
                logger.info("Encrypted data reset, re-uploading all local data")
                clearAllCachedRecords()
                resetOversizedRecordIDs()
                resetDirtyRecordIDs()
                storage.removeObject(forKey: Self.stateKey)
                storage.removeObject(forKey: Self.migrationCompleteKey)
                syncState.reset()
                syncEngine = nil
                start()

            case .deleted:
                logger.info("Zone deleted remotely, clearing local data and recording tombstones")
                clearLocalDataWithTombstones()

            @unknown default:
                logger.fault("Unknown zone deletion reason, taking no action (local data preserved)")
                syncState.report(RequestError(
                    kind: .cloudSync,
                    message: String(localized: "Unknown iCloud zone deletion reason received. Local data preserved. Please update the app.")
                ))
            }
        }
    }

    private func clearLocalDataWithTombstones() {
        let store = ProjectStore.shared

        var ids: [UUID] = []
        ids.append(contentsOf: store.projects.map(\.id))
        ids.append(contentsOf: store.folders.map(\.id))
        ids.append(contentsOf: store.requests.map(\.id))
        ids.append(contentsOf: store.requestFolders.map(\.id))
        ids.append(contentsOf: store.environments.map(\.id))
        ids.append(contentsOf: store.specDocuments.map(\.id))
        ids.append(contentsOf: store.protoBundles.map(\.id))
        DeletionTombstoneStore.shared.add(ids: ids)

        store.resetAllData()
        clearAllCachedRecords()
        resetOversizedRecordIDs()
        resetDirtyRecordIDs()
        storage.removeObject(forKey: Self.stateKey)
        storage.removeObject(forKey: Self.migrationCompleteKey)
        syncState.reset()
        syncEngine = nil
        start()
    }
}
