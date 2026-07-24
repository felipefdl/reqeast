//
//  CloudSyncService+Delegate.swift
//  Reqeast
//

import CloudKit
import Foundation
import os

private let logger = Logger(subsystem: "app.reqeast", category: "CloudSync.Delegate")

extension CloudSyncService: CKSyncEngineDelegate {

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let stateUpdate):
            do {
                let data = try JSONEncoder().encode(stateUpdate.stateSerialization)
                storage.set(data, forKey: Self.stateKey)
            } catch {
                logger.fault("Failed to persist sync engine state: \(error)")
            }

        case .accountChange(let accountChange):
            handleAccountChange(accountChange)

        case .fetchedRecordZoneChanges(let changes):
            handleFetchedChanges(changes)

        case .sentRecordZoneChanges(let sentChanges):
            handleSentChanges(sentChanges)

        case .fetchedDatabaseChanges(let dbChanges):
            handleFetchedDatabaseChanges(dbChanges)

        case .willFetchChanges, .willSendChanges:
            // Engine-automatic cycles never pass through `syncChanges()`, so reset the
            // per-cycle error tracking here; `recordCleanSendBatch` relies on it.
            syncState.noteCycleWillStart()

        case .willFetchRecordZoneChanges, .didFetchRecordZoneChanges, .didFetchChanges,
             .didSendChanges, .sentDatabaseChanges:
            break

        @unknown default:
            logger.fault("Unhandled CKSyncEngine event, ignoring")
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }

        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { recordID in
            // `provideRecord` is @MainActor-isolated (via the type), so the closure must hop
            // back to the main actor. Removing this `await` produces an actor-isolation error.
            await self.provideRecord(for: recordID)
        }
    }

    // MARK: - Record Provider

    private func provideRecord(for recordID: CKRecord.ID) -> CKRecord? {
        guard let parsed = parseRecordName(recordID.recordName) else {
            cancelPendingSave(recordID)
            return nil
        }

        let store = ProjectStore.shared
        switch parsed.type {
        case .project:
            guard let item = store.projects.first(where: { $0.id == parsed.id }),
                  item.deletedAt == nil else {
                cancelPendingSave(recordID); return nil
            }
            return buildRecord(for: item)
        case .projectFolder:
            guard let item = store.folders.first(where: { $0.id == parsed.id }),
                  item.deletedAt == nil else {
                cancelPendingSave(recordID); return nil
            }
            return buildRecord(for: item)
        case .request:
            guard let item = store.requests.first(where: { $0.id == parsed.id }),
                  item.deletedAt == nil else {
                cancelPendingSave(recordID); return nil
            }
            return buildRecord(for: item)
        case .requestFolder:
            guard let item = store.requestFolders.first(where: { $0.id == parsed.id }),
                  item.deletedAt == nil else {
                cancelPendingSave(recordID); return nil
            }
            return buildRecord(for: item)
        case .apiEnvironment:
            guard let item = store.environments.first(where: { $0.id == parsed.id }),
                  item.deletedAt == nil else {
                cancelPendingSave(recordID); return nil
            }
            return buildRecord(for: item)
        case .specDocument:
            guard let item = store.specDocuments.first(where: { $0.id == parsed.id }),
                  item.deletedAt == nil else {
                cancelPendingSave(recordID); return nil
            }
            return buildRecord(for: item)
        case .protoBundle:
            guard let item = store.protoBundles.first(where: { $0.id == parsed.id }),
                  item.deletedAt == nil else {
                cancelPendingSave(recordID); return nil
            }
            return buildRecord(for: item)
        }
    }

    /// Removes a save pending state for a record that will never be provided (not found,
    /// soft-deleted, or unparseable name). Prevents the provider loop where CKSyncEngine
    /// retries every send cycle and our provider keeps returning nil.
    private func cancelPendingSave(_ recordID: CKRecord.ID) {
        syncEngine?.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
    }

    // MARK: - Account Change

    private func handleAccountChange(_ event: CKSyncEngine.Event.AccountChange) {
        switch event.changeType {
        case .signIn:
            logger.info("iCloud account signed in, running migration")
            runMigrationIfNeeded()
        case .switchAccounts:
            logger.info("iCloud account switched, clearing sync state and re-migrating")
            storage.removeObject(forKey: Self.stateKey)
            storage.removeObject(forKey: Self.migrationCompleteKey)
            clearAllCachedRecords()
            resetOversizedRecordIDs()
            resetDirtyRecordIDs()
            // Tombstones are scoped to the previous account; carrying them to the new account
            // could block UUIDs the new user legitimately holds and starve incoming records.
            DeletionTombstoneStore.shared.clear()
            // Errors and the success timestamp belong to the previous account.
            syncState.reset()
            syncEngine = nil
            start()
        case .signOut:
            logger.info("iCloud account signed out, stopping sync engine")
            syncState.reset()
            syncEngine = nil
        @unknown default:
            logger.fault("Unknown iCloud account change type, ignoring")
            syncState.report(RequestError(
                kind: .cloudSync,
                message: String(localized: "Unknown iCloud account change type. Please update the app.")
            ))
        }
    }
}
