//
//  CloudSyncService+SendHandling.swift
//  Reqeast
//

import CloudKit
import Foundation
import os

private let logger = Logger(subsystem: "app.reqeast", category: "CloudSync.Send")

/// Oracle sets for CloudSyncSendHandlingTests to assert the switch in `handleFailedRecordSave`
/// stays in sync with our classification policy. The switch below is the source of truth.
/// Do not reference these from production code.
enum CloudSyncSendHandling {
    /// `.batchRequestFailed` is collateral: the record failed only because another record in the
    /// same batch did, so it is safe to re-queue; the offending record's own error drives recovery.
    static let retryableSaveErrorCodes: Set<CKError.Code> = [
        .zoneBusy, .serviceUnavailable, .requestRateLimited,
        .networkFailure, .networkUnavailable, .serverResponseLost,
        .batchRequestFailed,
    ]
    static let nonRetryableSaveErrorCodes: Set<CKError.Code> = [
        .notAuthenticated, .quotaExceeded, .managedAccountRestricted, .accountTemporarilyUnavailable,
        .permissionFailure, .invalidArguments, .limitExceeded, .badContainer, .badDatabase,
        .missingEntitlement, .incompatibleVersion, .internalError, .serverRejectedRequest,
        .assetFileNotFound, .assetFileModified, .constraintViolation, .referenceViolation,
    ]

    /// Save failures recoverable by user action (e.g. freeing iCloud space) rather than by time.
    /// Listed in `nonRetryableSaveErrorCodes` because neither the engine nor the handler
    /// auto-retries them: the record stays dirty, so `requeueUnconfirmedItems` re-tries it on
    /// the next foreground, after the user has had a chance to free space. Re-queuing inside the
    /// handler would make the engine retry on its own schedule, a hot loop while quota stays
    /// exhausted. Must be disjoint from `retryableSaveErrorCodes`.
    static let quotaRecoveryCodes: Set<CKError.Code> = [.quotaExceeded]

    /// `CKSyncEngine.sendChanges()` / `fetchChanges()` rethrow `CKError.partialFailure` whenever
    /// any record in the batch fails. Per-record errors are already classified and reported via
    /// `event.failedRecordSaves`, `event.failedRecordDeletes`, and the `cloudDecodeError` branch
    /// of `handleFetchedRecordZoneChanges` (CloudSyncService+FetchHandling.swift), so the outer
    /// wrapper is redundant noise. We additionally require `partialErrorsByItemID` to be
    /// non-empty: a zone- or operation-scoped failure (auth flip, account-change race) leaves
    /// the dict empty and the delegate never sees per-record errors, so that case must surface.
    static func isHandledPartialFailure(_ error: Error) -> Bool {
        guard let ckError = error as? CKError, ckError.code == .partialFailure else { return false }
        return !(ckError.partialErrorsByItemID ?? [:]).isEmpty
    }

    /// Picks the error worth surfacing to `syncState` after a `syncChanges()` cycle. Returns
    /// the send error when it is not a handled partial failure; else the fetch error when it
    /// is not a handled partial failure; else nil. Prevents a `partialFailure` from
    /// `sendChanges()` from masking a real error from `fetchChanges()` (e.g. `.networkFailure`).
    static func reportableError(send: Error?, fetch: Error?) -> Error? {
        for error in [send, fetch].compactMap({ $0 }) where !isHandledPartialFailure(error) {
            return error
        }
        return nil
    }
}

extension CloudSyncService {

    func handleSentChanges(_ event: CKSyncEngine.Event.SentRecordZoneChanges) {
        let store = ProjectStore.shared
        var dirtyChanged = false
        var oversizedChanged = false
        store.withRemoteBatch {
            for saved in event.savedRecords {
                cacheSystemFields(of: saved)
                noteConfirmedSpecDocumentUpload(saved, store: store)
                noteConfirmedProtoBundleUpload(saved, store: store)
                // Server confirmed this version, so no edit is pending. A new edit after this
                // point will re-mark the record dirty in `queueSave`.
                if dirtyRecordIDs.remove(saved.recordID.recordName) != nil {
                    dirtyChanged = true
                }
            }

            for failure in event.failedRecordSaves {
                handleFailedRecordSave(record: failure.record, error: failure.error, store: store)
            }

            for recordID in event.deletedRecordIDs {
                guard let parsed = parseRecordName(recordID.recordName) else { continue }
                logger.info("Record deleted from CloudKit: \(parsed.type.rawValue)/\(parsed.id.uuidString.prefix(8))")
                dropCachedRecord(recordName: recordID.recordName)
                if dirtyRecordIDs.remove(recordID.recordName) != nil {
                    dirtyChanged = true
                }
                // A blocked (oversized/permanently rejected) item that gets deleted would
                // otherwise leave its entry in the blocked set forever.
                if oversizedRecordIDs.remove(recordID.recordName) != nil {
                    oversizedChanged = true
                }
                store.purgeDeletedItem(recordType: parsed.type, id: parsed.id)
            }

            for (recordID, error) in event.failedRecordDeletes {
                handleFailedRecordDelete(recordID: recordID, error: error, store: store)
            }

            persistLastKnownRecords()
            if dirtyChanged {
                persistDirtyRecordIDs()
            }
            if oversizedChanged {
                persistOversizedRecordIDs()
            }
        }
        // A batch where every record succeeded is positive evidence the transport recovered.
        // Clears a stale error from an earlier cycle (sticky per-item kinds excepted).
        if event.failedRecordSaves.isEmpty, event.failedRecordDeletes.isEmpty,
           !(event.savedRecords.isEmpty && event.deletedRecordIDs.isEmpty) {
            syncState.recordCleanSendBatch()
        }
    }

    private func noteConfirmedSpecDocumentUpload(_ record: CKRecord, store: ProjectStore) {
        guard let parsed = parseRecordName(record.recordID.recordName),
              parsed.type == .specDocument,
              let index = store.specDocuments.firstIndex(where: { $0.id == parsed.id }) else {
            return
        }
        var document = store.specDocuments[index]
        document.lastUploadedFingerprint = document.contentFingerprint
        store.specDocuments[index] = document
    }

    private func noteConfirmedProtoBundleUpload(_ record: CKRecord, store: ProjectStore) {
        guard let parsed = parseRecordName(record.recordID.recordName),
              parsed.type == .protoBundle,
              let index = store.protoBundles.firstIndex(where: { $0.id == parsed.id }) else {
            return
        }
        var bundle = store.protoBundles[index]
        bundle.lastUploadedFingerprint = bundle.contentFingerprint
        store.protoBundles[index] = bundle
    }

    // MARK: - Private Helpers

    private func handleFailedRecordSave(record: CKRecord, error: CKError, store: ProjectStore) {
        let recordID = record.recordID

        switch error.code {
        case .unknownItem:
            logger.info("Record not found on server: \(recordID.recordName)")
            dropCachedRecord(recordName: recordID.recordName)
            syncEngine?.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])

        case .zoneNotFound, .userDeletedZone:
            logger.info("Zone not found for \(recordID.recordName) (\(String(describing: error.code))), recreating and retrying")
            syncEngine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
            syncEngine?.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])

        case .serverRecordChanged:
            logger.info("Conflict on \(recordID.recordName), resolving by updatedAt")

            guard let serverRecord = error.serverRecord else {
                logger.error("Conflict but no serverRecord for \(recordID.recordName), re-queuing local")
                syncEngine?.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
                return
            }
            cacheSystemFields(of: serverRecord)

            switch resolveConflict(localRecord: record, serverRecord: serverRecord) {
            case .localNewer:
                // Bump local updatedAt so a racing remote change doesn't win the rebound
                // with a newer timestamp than our re-queued save.
                if let parsed = parseRecordName(recordID.recordName) {
                    store.touchLocalItem(type: parsed.type, id: parsed.id)
                }
                syncEngine?.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
            case .serverNewer:
                guard let parsed = parseRecordName(recordID.recordName) else { return }
                if !decodeAndApplyUpsert(record: serverRecord, type: parsed.type, store: store) {
                    handleConflictDecodeFailure(serverRecord)
                }
            case .undecidable(let reason):
                logger.fault("Conflict undecidable for \(recordID.recordName): \(reason). Defaulting to server.")
                syncState.report(RequestError(
                    kind: .cloudConflictUnresolvable,
                    message: "\(recordID.recordName): \(reason)"
                ))
                if let parsed = parseRecordName(recordID.recordName),
                   !decodeAndApplyUpsert(record: serverRecord, type: parsed.type, store: store) {
                    handleConflictDecodeFailure(serverRecord)
                }
            }

        case .quotaExceeded:
            // No immediate re-queue: the record stays dirty, so `requeueUnconfirmedItems`
            // re-tries it on the next foreground. Re-adding here would make the engine retry
            // on its own schedule, a hot loop while quota stays exhausted.
            logger.fault("iCloud storage full, cannot sync \(recordID.recordName). User must free space; will re-try on next foreground.")
            syncState.report(.fromCloudKit(error))

        case .notAuthenticated, .managedAccountRestricted, .accountTemporarilyUnavailable:
            logger.fault("iCloud account not available for \(recordID.recordName): \(String(describing: error.code))")
            syncState.report(.fromCloudKit(error))

        case .zoneBusy, .serviceUnavailable, .requestRateLimited, .networkFailure, .networkUnavailable,
             .serverResponseLost, .batchRequestFailed:
            logger.info("Transient error saving \(recordID.recordName), will retry: \(error.localizedDescription)")
            syncEngine?.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])

        case .permissionFailure, .invalidArguments, .limitExceeded, .badContainer, .badDatabase,
             .missingEntitlement, .incompatibleVersion, .internalError, .serverRejectedRequest,
             .assetFileNotFound, .assetFileModified, .constraintViolation, .referenceViolation:
            logger.fault("Permanent save failure for \(recordID.recordName) (\(String(describing: error.code))), giving up: \(error)")
            dropCachedRecord(recordName: recordID.recordName)
            // Block the record from the foreground requeue (same mechanism as oversized
            // records). Without this, the cleared cache entry makes `shouldRequeueUnconfirmed`
            // re-add the record every foreground, an endless rebuild-reject-report loop.
            // The next user edit (`queueSave`) clears the block and re-tries.
            oversizedRecordIDs.insert(recordID.recordName)
            persistOversizedRecordIDs()
            syncState.report(.fromCloudKit(error))

        case .operationCancelled:
            logger.info("Save cancelled for \(recordID.recordName)")

        @unknown default:
            logger.fault("Unknown save error for \(recordID.recordName), not retrying: \(error)")
            syncState.report(.fromCloudKit(error))
        }
    }

    /// The server won the conflict but its payload cannot be decoded (likely written by a newer
    /// app version). Mirrors the fetch path: back up the payload and surface the error. Also
    /// clears the dirty flag so the foreground requeue does not re-upload the older local copy
    /// over the server record this device could not read; the local copy stays visible locally
    /// and wins again the next time the user edits it (fresh `updatedAt`).
    private func handleConflictDecodeFailure(_ serverRecord: CKRecord) {
        let name = serverRecord.recordID.recordName
        logger.fault("Conflict: server record \(name) won but could not be decoded; backing up payload")
        backupCorruptRemoteRecord(serverRecord)
        if dirtyRecordIDs.remove(name) != nil {
            persistDirtyRecordIDs()
        }
        syncState.report(RequestError(
            kind: .cloudDecodeError,
            message: String(localized: "A record from iCloud could not be read on this device. It may have been written by a newer app version. See corrupt-records folder.")
        ))
    }

    private func handleFailedRecordDelete(recordID: CKRecord.ID, error: CKError, store: ProjectStore) {
        switch error.code {
        case .unknownItem, .zoneNotFound, .userDeletedZone:
            guard let parsed = parseRecordName(recordID.recordName) else { return }
            logger.info("Delete target already gone (\(String(describing: error.code))): \(parsed.type.rawValue)/\(parsed.id.uuidString.prefix(8))")
            dropCachedRecord(recordName: recordID.recordName)
            if oversizedRecordIDs.remove(recordID.recordName) != nil {
                persistOversizedRecordIDs()
            }
            store.purgeDeletedItem(recordType: parsed.type, id: parsed.id)

        case .zoneBusy, .serviceUnavailable, .requestRateLimited, .networkFailure, .networkUnavailable,
             .serverResponseLost, .batchRequestFailed:
            logger.info("Transient error deleting \(recordID.recordName), will retry: \(error.localizedDescription)")
            syncEngine?.state.add(pendingRecordZoneChanges: [.deleteRecord(recordID)])

        case .quotaExceeded, .notAuthenticated, .managedAccountRestricted, .accountTemporarilyUnavailable:
            logger.fault("Account/quota issue deleting \(recordID.recordName): \(String(describing: error.code))")
            syncState.report(.fromCloudKit(error))

        case .permissionFailure, .invalidArguments, .limitExceeded, .badContainer, .badDatabase,
             .missingEntitlement, .incompatibleVersion, .internalError, .serverRejectedRequest:
            logger.fault("Permanent delete failure for \(recordID.recordName) (\(String(describing: error.code))), giving up")
            syncState.report(.fromCloudKit(error))

        case .operationCancelled:
            logger.info("Delete cancelled for \(recordID.recordName)")

        @unknown default:
            logger.fault("Unknown delete error for \(recordID.recordName), not retrying: \(error)")
            syncState.report(.fromCloudKit(error))
        }
    }
}
