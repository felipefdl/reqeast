//
//  ProjectStore+Persistence.swift
//  Reqeast
//

import CloudKit
import Foundation
import os

private let logger = Logger(subsystem: "app.reqeast", category: "ProjectStore")

extension ProjectStore {

    // MARK: - App Lifecycle

    @objc nonisolated func appDidBecomeActive(_ notification: Notification) {
        Task { @MainActor in
            // Keep requeue as a crash-recovery safety net; CKSyncEngine handles scheduled sync
            // automatically. See Apple sample-cloudkit-sync-engine and WWDC23 session 10188.
            CloudSyncService.shared.requeueUnconfirmedItems()
        }
    }

    @objc nonisolated func appWillEnterBackground(_ notification: Notification) {
        Task { @MainActor in
            logger.info("appWillEnterBackground: saving locally")
            saveLocal()
        }
    }

    // MARK: - Load

    func load() {
        isLoading = true
        projects = decodeLocal(key: Self.projectsKey) ?? []
        folders = decodeLocal(key: Self.foldersKey) ?? []
        requests = loadRequests()
        requestFolders = decodeLocal(key: Self.requestFoldersKey) ?? []
        environments = decodeLocal(key: Self.environmentsKey) ?? []
        specDocuments = decodeLocal(key: Self.specDocumentsKey) ?? []
        protoBundles = decodeLocal(key: Self.protoBundlesKey) ?? []
        deduplicate()
        isLoading = false
        ProjectIconService.shared.downloadMissingIcons(for: projects)
    }

    // MARK: - Deduplication

    func deduplicate() {
        projects = deduplicateByID(projects)
        folders = deduplicateByID(folders)
        requests = deduplicateByID(requests)
        requestFolders = deduplicateByID(requestFolders)
        environments = deduplicateByID(environments)
        specDocuments = deduplicateByID(specDocuments)
        protoBundles = deduplicateByID(protoBundles)
    }

    private func deduplicateByID<T: CloudSyncable>(_ items: [T]) -> [T] {
        var seen: [UUID: Int] = [:]
        var result: [T] = []
        for item in items {
            if let existingIndex = seen[item.id] {
                if item.updatedAt > result[existingIndex].updatedAt {
                    result[existingIndex] = item
                }
            } else {
                seen[item.id] = result.count
                result.append(item)
            }
        }
        return result
    }

    // MARK: - Save

    func saveAll() {
        guard !isLoading else {
            logger.warning("saveAll skipped: isLoading=true")
            return
        }
        saveLocal()
    }

    func saveLocal() {
        guard !isLoading else { return }
        do {
            try saveLocalOrThrow()
        } catch {
            logger.fault("Failed to save locally, data may be lost on restart: \(error)")
        }
    }

    /// Throws on encode/persist failure. Used by `performBulkImport` so commit can roll back (AC12).
    func saveLocalOrThrow() throws {
        guard !isLoading else { return }
        #if DEBUG
        if StorageEnvironment.isRunningTests {
            if importInProgress {
                bulkImportSaveLocalCallCount += 1
                if bulkImportSaveLocalShouldFail {
                    throw BulkImportError.localPersistFailed
                }
            }
            if syncApplyInProgress {
                syncApplySaveLocalCallCount += 1
                if syncApplySaveLocalShouldFail {
                    throw BulkImportError.localPersistFailed
                }
            }
        }
        #endif
        logger.info("saveLocal: \(self.projects.count) projects, \(self.requests.count) requests")
        try RequestLibraryPersistence.save(requests)
        let encoded = try encodeAll()
        for (key, data) in encoded {
            storage.set(data, forKey: key)
        }
    }

    // MARK: - Helpers

    private func encodeAll() throws -> [(String, Data)] {
        let encoder = JSONEncoder()
        return [
            (Self.projectsKey, try encoder.encode(projects)),
            (Self.foldersKey, try encoder.encode(folders)),
            (Self.requestFoldersKey, try encoder.encode(requestFolders)),
            (Self.environmentsKey, try encoder.encode(environments)),
            (Self.specDocumentsKey, try encoder.encode(specDocuments)),
            (Self.protoBundlesKey, try encoder.encode(protoBundles)),
        ]
    }

    private func loadRequests() -> [Request] {
        if let fileRequests = RequestLibraryPersistence.load() {
            purgeLegacyRequestsUserDefaults()
            return fileRequests
        }

        guard let legacyRequests: [Request] = decodeLocal(key: Self.requestsKey) else {
            return []
        }

        logger.info("Migrating \(legacyRequests.count) requests from UserDefaults to library file")
        do {
            try RequestLibraryPersistence.save(legacyRequests)
            storage.removeObject(forKey: Self.requestsKey)
        } catch {
            logger.fault("Failed to migrate requests to library file: \(error)")
        }
        return legacyRequests
    }

    /// Removes the pre-file-storage requests blob and corrupt backups that can still trip the 4 MB limit.
    private func purgeLegacyRequestsUserDefaults() {
        storage.removeObject(forKey: Self.requestsKey)
        for key in storage.dictionaryRepresentation().keys where key.hasPrefix("\(Self.requestsKey)_corrupt") {
            storage.removeObject(forKey: key)
        }
    }

    private static let userDefaultsMaxValueBytes = 4_000_000

    private func decodeLocal<T: Decodable>(key: String) -> [T]? {
        guard let data = storage.data(forKey: key) else { return nil }
        do {
            return try JSONDecoder().decode([T].self, from: data)
        } catch {
            logger.fault("Failed to decode \(key) from UserDefaults: \(error). Backing up corrupt data.")
            backupCorruptUserDefaultsPayload(data, key: key)
            storage.removeObject(forKey: key)
            return nil
        }
    }

    private func backupCorruptUserDefaultsPayload(_ data: Data, key: String) {
        guard data.count < Self.userDefaultsMaxValueBytes else {
            logger.fault("Skipping UserDefaults corrupt backup for \(key): \(data.count) bytes exceeds limit")
            writeCorruptPayloadToDisk(data, key: key)
            return
        }
        storage.set(data, forKey: "\(key)_corrupt_backup")
    }

    private func writeCorruptPayloadToDisk(_ data: Data, key: String) {
        let fm = FileManager.default
        guard let supportDir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return
        }
        let directory = supportDir
            .appendingPathComponent("reqeast", isDirectory: true)
            .appendingPathComponent(StorageEnvironment.libraryDirName, isDirectory: true)
            .appendingPathComponent("corrupt-userdefaults", isDirectory: true)
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            let timestamp = Int(Date().timeIntervalSince1970)
            let safeKey = key.replacingOccurrences(of: ".", with: "_")
            let file = directory.appendingPathComponent("\(safeKey)-\(timestamp).bin")
            try data.write(to: file, options: .atomic)
            logger.info("Backed up corrupt UserDefaults payload to \(file.path)")
        } catch {
            logger.fault("Failed to back up corrupt UserDefaults payload for \(key): \(error)")
        }
    }
}
