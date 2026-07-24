//
//  CloudSyncService.swift
//  Reqeast
//

import CloudKit
import Foundation
import os

private let logger = Logger(subsystem: "app.reqeast", category: "CloudSync")

@MainActor
final class CloudSyncService {
    static let shared = CloudSyncService()

    private let containerID = "iCloud.app.reqeast"
    private let zoneName = "Reqeast"
    let storage = UserDefaults.standard

    // Prefixed so debug builds and unit tests do not read or clobber the release app's
    // sync metadata on the same machine (the prefix is empty in release builds).
    static let stateKey = StorageEnvironment.keyPrefix + "cloudSyncState"
    static let lastKnownRecordsKey = StorageEnvironment.keyPrefix + "cloudSyncLastKnownRecords"
    static let migrationCompleteKey = StorageEnvironment.keyPrefix + "cloudSyncMigrationComplete"
    static let oversizedRecordsKey = StorageEnvironment.keyPrefix + "cloudSyncOversizedRecords"
    static let dirtyRecordsKey = StorageEnvironment.keyPrefix + "cloudSyncDirtyRecords"

    private static let partialFailureSuppressedLog =
        "partialFailure suppressed; per-record errors handled by delegate"

    var syncEngine: CKSyncEngine?
    var lastKnownRecordData: [String: Data] = [:]
    /// Record names with a confirmed on-disk system-field cache. Replaces scanning the full
    /// in-memory map for `shouldRequeueUnconfirmed` so init does not load every archive.
    var confirmedRecordNames: Set<String> = []
    /// Record names blocked from automatic requeue: rejected by `buildRecord` as too large for
    /// a CKRecord, or permanently rejected by the server (`handleFailedRecordSave`). Persisted
    /// across launches so `requeueUnconfirmedItems` does not re-add them on every foreground,
    /// which would otherwise produce an infinite reject/report loop. The block clears per
    /// record on the next `queueSave` (user edit) and wholesale on the reset paths.
    var oversizedRecordIDs: Set<String> = []
    /// Record names with local edits that have not yet been confirmed by `event.savedRecords`.
    /// Written in `queueSave` and cleared in `handleSentChanges`. Persisted so a crash between
    /// `queueSave` and CKSyncEngine's async `stateUpdate` persistence does not lose the edit:
    /// `requeueUnconfirmedItems` re-adds the save on next launch even when cached system fields
    /// exist (the record was previously synced and edited again).
    var dirtyRecordIDs: Set<String> = []
    /// In-flight reentrancy guard for `syncChanges()`. Concurrent calls (pull-to-refresh,
    /// Cmd+R, foreground, status-button tap) collapse to a single send+fetch cycle so the
    /// engine does not interleave duplicate work or mask errors across overlapping attempts.
    private var isSyncing = false

    let syncState = CloudSyncState()

    #if DEBUG
    /// Incremented by `queueSaveBatch` during unit tests (AC17).
    var queueSaveBatchCallCount = 0
    /// Record names queued by the most recent `queueSaveBatch` call (test-only ordering spy).
    var lastQueueSaveBatchRecordOrder: [String] = []
    #endif

    var zoneID: CKRecordZone.ID { CKRecordZone.ID(zoneName: zoneName) }

    private init() {
        confirmedRecordNames = CloudSyncLastKnownRecordStore.allRecordNames()
        if storage.data(forKey: Self.lastKnownRecordsKey) != nil {
            let migrated = CloudSyncLastKnownRecordStore.migrateFromUserDefaults(
                storage: storage,
                key: Self.lastKnownRecordsKey
            )
            if migrated > 0 {
                confirmedRecordNames.formUnion(CloudSyncLastKnownRecordStore.allRecordNames())
            }
        }
        if let data = storage.data(forKey: Self.oversizedRecordsKey) {
            do {
                oversizedRecordIDs = try JSONDecoder().decode(Set<String>.self, from: data)
            } catch {
                logger.fault("Failed to decode oversized record IDs: \(error). Backing up corrupt data.")
                backupCorruptUserDefaults(data: data, key: Self.oversizedRecordsKey)
            }
        }
        if let data = storage.data(forKey: Self.dirtyRecordsKey) {
            do {
                dirtyRecordIDs = try JSONDecoder().decode(Set<String>.self, from: data)
            } catch {
                logger.fault("Failed to decode dirty record IDs: \(error). Backing up corrupt data.")
                backupCorruptUserDefaults(data: data, key: Self.dirtyRecordsKey)
            }
        }
    }

    /// Whether a not-yet-deleted item should be re-queued for save. Oversized records are blocked
    /// to prevent the reject/report loop. Dirty records (edited locally since last server
    /// confirmation) are always re-queued even when cached system fields exist, so an edit
    /// between `queueSave` and a crash before CKSyncEngine persists pending state is not lost.
    /// Otherwise, items with cached system fields are already confirmed.
    static func shouldRequeueUnconfirmed(
        recordName: String,
        confirmedRecordNames: Set<String>,
        oversizedRecordIDs: Set<String>,
        dirtyRecordIDs: Set<String>
    ) -> Bool {
        if oversizedRecordIDs.contains(recordName) { return false }
        if dirtyRecordIDs.contains(recordName) { return true }
        return !confirmedRecordNames.contains(recordName)
    }

    func persistOversizedRecordIDs() {
        do {
            let data = try JSONEncoder().encode(oversizedRecordIDs)
            storage.set(data, forKey: Self.oversizedRecordsKey)
        } catch {
            logger.fault("Failed to persist oversized record IDs: \(error)")
        }
    }

    /// Wipes the oversized tombstone from memory and disk. Used from reset paths (account
    /// switch, encrypted data reset, zone purge/delete) so a fresh zone starts with no blocked
    /// records. `removeObject` avoids the fallible encode round-trip.
    func resetOversizedRecordIDs() {
        oversizedRecordIDs = []
        storage.removeObject(forKey: Self.oversizedRecordsKey)
    }

    func persistDirtyRecordIDs() {
        do {
            let data = try JSONEncoder().encode(dirtyRecordIDs)
            storage.set(data, forKey: Self.dirtyRecordsKey)
        } catch {
            logger.fault("Failed to persist dirty record IDs: \(error)")
        }
    }

    /// Wipes the dirty record set from memory and disk. Used from the same reset paths as
    /// `resetOversizedRecordIDs` so a fresh zone does not requeue stale edits.
    func resetDirtyRecordIDs() {
        dirtyRecordIDs = []
        storage.removeObject(forKey: Self.dirtyRecordsKey)
    }

    func start() {
        guard syncEngine == nil else { return }

        let container = CKContainer(identifier: containerID)
        let database = container.privateCloudDatabase

        var stateSerialization: CKSyncEngine.State.Serialization?
        if let data = storage.data(forKey: Self.stateKey) {
            do {
                stateSerialization = try JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
            } catch {
                logger.fault("Failed to decode sync engine state, starting fresh: \(error). Backing up corrupt data.")
                backupCorruptUserDefaults(data: data, key: Self.stateKey)
            }
        }

        let configuration = CKSyncEngine.Configuration(
            database: database,
            stateSerialization: stateSerialization,
            delegate: self
        )

        let engine = CKSyncEngine(configuration)
        self.syncEngine = engine

        engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])

        runMigrationIfNeeded()

        // 90 days: conservative upper bound on how long a device may be offline before
        // resurfacing with a stale server view. After this window, ghost-record prevention
        // yields to storage hygiene. Lengthen this if users report offline-resurrection bugs.
        DeletionTombstoneStore.shared.pruneOlderThan(days: 90)
        logger.info("CKSyncEngine started")
    }

    func queueSave(_ item: some CloudSyncable) {
        let recordID = recordID(for: item)
        // Clear the oversized tombstone so a shrunk record gets re-tried on this save.
        if oversizedRecordIDs.remove(recordID.recordName) != nil {
            persistOversizedRecordIDs()
        }
        // Persist the dirty flag synchronously so an edit survives a crash between this call
        // and CKSyncEngine's async state persistence (`event.stateUpdate`).
        if dirtyRecordIDs.insert(recordID.recordName).inserted {
            persistDirtyRecordIDs()
        }
        guard let engine = syncEngine else {
            logger.debug("queueSave skipped: sync engine not running")
            return
        }
        engine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
    }

    /// Queues CKSyncEngine saves for a bulk import or other multi-item write. Mirrors per-item
    /// `queueSave` tombstone/dirty-flag behavior, then issues a single `add(pendingRecordZoneChanges:)`.
    /// Child records are queued before `Project` so dependents sync ahead of parent metadata.
    func queueSaveBatch(
        project: Project? = nil,
        projectFolders: [ProjectFolder]? = nil,
        folders: [RequestFolder]? = nil,
        requests: [Request]? = nil,
        environments: [ApiEnvironment]? = nil,
        specDocument: SpecDocument? = nil,
        protoBundles: [ProtoBundle]? = nil
    ) {
        #if DEBUG
        if StorageEnvironment.isRunningTests {
            queueSaveBatchCallCount += 1
            lastQueueSaveBatchRecordOrder = []
        }
        #endif

        var oversizedCleared = false
        var dirtyAdded = false

        func appendSave(_ item: some CloudSyncable, to changes: inout [CKSyncEngine.PendingRecordZoneChange]) {
            let recordID = recordID(for: item)
            if oversizedRecordIDs.remove(recordID.recordName) != nil {
                oversizedCleared = true
            }
            if dirtyRecordIDs.insert(recordID.recordName).inserted {
                dirtyAdded = true
            }
            #if DEBUG
            if StorageEnvironment.isRunningTests {
                lastQueueSaveBatchRecordOrder.append(recordID.recordName)
            }
            #endif
            changes.append(.saveRecord(recordID))
        }

        var changes: [CKSyncEngine.PendingRecordZoneChange] = []
        if let projectFolders {
            for folder in projectFolders {
                appendSave(folder, to: &changes)
            }
        }
        if let folders {
            for folder in folders {
                appendSave(folder, to: &changes)
            }
        }
        if let requests {
            for request in requests {
                appendSave(request, to: &changes)
            }
        }
        if let environments {
            for environment in environments {
                appendSave(environment, to: &changes)
            }
        }
        if let protoBundles {
            for bundle in protoBundles {
                appendSave(bundle, to: &changes)
            }
        }
        if let specDocument {
            appendSave(specDocument, to: &changes)
        }
        if let project {
            appendSave(project, to: &changes)
        }

        if oversizedCleared {
            persistOversizedRecordIDs()
        }
        if dirtyAdded {
            persistDirtyRecordIDs()
        }

        guard let engine = syncEngine else {
            logger.debug("queueSaveBatch skipped: sync engine not running")
            return
        }
        guard !changes.isEmpty else { return }
        engine.state.add(pendingRecordZoneChanges: changes)
    }

    func queueDelete(recordType: SyncRecordType, id: UUID) {
        guard let engine = syncEngine else {
            logger.debug("queueDelete skipped: sync engine not running")
            return
        }
        let recordID = CKRecord.ID(recordName: "\(recordType.rawValue)/\(id.uuidString)", zoneID: zoneID)
        engine.state.add(pendingRecordZoneChanges: [.deleteRecord(recordID)])
    }

    /// Queues CKSyncEngine record-level deletes for all items in the store.
    /// Called during "Reset All Data" after soft-deleting items.
    func queueDeleteAll() {
        guard let engine = syncEngine else {
            logger.debug("queueDeleteAll skipped: sync engine not running")
            return
        }
        let store = ProjectStore.shared
        var changes: [CKSyncEngine.PendingRecordZoneChange] = []
        for item in store.projects { changes.append(.deleteRecord(recordID(for: item))) }
        for item in store.folders { changes.append(.deleteRecord(recordID(for: item))) }
        for item in store.requests { changes.append(.deleteRecord(recordID(for: item))) }
        for item in store.requestFolders { changes.append(.deleteRecord(recordID(for: item))) }
        for item in store.environments { changes.append(.deleteRecord(recordID(for: item))) }
        for item in store.specDocuments { changes.append(.deleteRecord(recordID(for: item))) }
        for item in store.protoBundles { changes.append(.deleteRecord(recordID(for: item))) }
        engine.state.add(pendingRecordZoneChanges: changes)
        logger.info("Queued \(changes.count) record deletions")
    }

    /// Sends pending changes (from CRUD operations), then fetches remote changes.
    /// Called on app foreground, pull-to-refresh, and Cmd+R. Failures are surfaced via `syncState`.
    func syncChanges() async {
        logger.info("syncChanges: starting")
        guard let engine = syncEngine else {
            logger.warning("syncChanges: sync engine is nil, skipping")
            return
        }
        if isSyncing {
            logger.info("syncChanges: already in progress, coalescing")
            return
        }
        isSyncing = true
        defer { isSyncing = false }
        syncState.beginSync()
        var sendError: Error?
        var fetchError: Error?
        do {
            try await engine.sendChanges()
            logger.info("syncChanges: sendChanges completed")
        } catch {
            logger.error("syncChanges: sendChanges failed: \(error)")
            sendError = error
        }
        do {
            try await engine.fetchChanges()
            logger.info("syncChanges: fetchChanges completed")
        } catch {
            logger.error("syncChanges: fetchChanges failed: \(error)")
            fetchError = error
        }
        let cycleWasClean = sendError == nil && fetchError == nil
        if let error = CloudSyncSendHandling.reportableError(send: sendError, fetch: fetchError) {
            syncState.report(.fromCloudKit(error))
        } else if cycleWasClean {
            syncState.finishSync()
        } else {
            logger.debug("syncChanges: \(Self.partialFailureSuppressedLog)")
            syncState.endSyncAttempt()
        }
    }

    /// Re-queues items that were queued for save but never confirmed by the server.
    /// Items are considered unconfirmed if we have no cached CKRecord system fields for them.
    /// Runs on app foreground to recover from interrupted sends (crash mid-migration, sign-out
    /// mid-send, force quit). Items already soft-deleted are skipped.
    func requeueUnconfirmedItems() {
        guard let engine = syncEngine else { return }
        let store = ProjectStore.shared
        var changes: [CKSyncEngine.PendingRecordZoneChange] = []

        func check(_ item: some CloudSyncable) {
            guard item.deletedAt == nil else { return }
            let id = recordID(for: item)
            if Self.shouldRequeueUnconfirmed(
                recordName: id.recordName,
                confirmedRecordNames: confirmedRecordNames,
                oversizedRecordIDs: oversizedRecordIDs,
                dirtyRecordIDs: dirtyRecordIDs
            ) {
                changes.append(.saveRecord(id))
            }
        }

        store.projects.forEach { check($0) }
        store.folders.forEach { check($0) }
        store.requests.forEach { check($0) }
        store.requestFolders.forEach { check($0) }
        store.environments.forEach { check($0) }
        store.protoBundles.forEach { check($0) }

        if !changes.isEmpty {
            engine.state.add(pendingRecordZoneChanges: changes)
            logger.info("Re-queued \(changes.count) unconfirmed items")
        }
    }

    /// Per-record archives are written in `cacheSystemFields(of:)`. Bulk UserDefaults persistence
    /// was removed because large libraries exceed the 4 MB per-key limit.
    func persistLastKnownRecords() {}

    func dropCachedRecord(recordName: String) {
        lastKnownRecordData.removeValue(forKey: recordName)
        confirmedRecordNames.remove(recordName)
        CloudSyncLastKnownRecordStore.remove(recordName: recordName)
    }

    func clearAllCachedRecords() {
        lastKnownRecordData = [:]
        confirmedRecordNames = []
        CloudSyncLastKnownRecordStore.removeAll()
        storage.removeObject(forKey: Self.lastKnownRecordsKey)
    }

    /// Backs up a corrupt UserDefaults blob to a timestamped key before it would be overwritten,
    /// so a future session can recover or forensically inspect the data.
    func backupCorruptUserDefaults(data: Data, key: String) {
        let timestamp = Int(Date().timeIntervalSince1970)
        storage.set(data, forKey: "\(key)_corrupt_backup_\(timestamp)")
    }

    /// Writes a remote CKRecord's data payload to `Application Support/reqeast/corrupt-records/`
    /// for forensic recovery when decoding fails (likely schema drift between app versions).
    func backupCorruptRemoteRecord(_ record: CKRecord) {
        guard let payload = record["data"] as? Data else { return }
        let fm = FileManager.default
        guard let supportDir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let dir = supportDir.appendingPathComponent("reqeast/corrupt-records", isDirectory: true)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let timestamp = Int(Date().timeIntervalSince1970)
            let safeName = record.recordID.recordName.replacingOccurrences(of: "/", with: "_")
            let file = dir.appendingPathComponent("\(safeName)-\(timestamp).json")
            try payload.write(to: file)
            logger.info("Backed up corrupt record to \(file.path)")
        } catch {
            logger.fault("Failed to back up corrupt record \(record.recordID.recordName): \(error)")
        }
    }
}
