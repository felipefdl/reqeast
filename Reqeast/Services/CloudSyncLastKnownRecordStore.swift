//
//  CloudSyncLastKnownRecordStore.swift
//  Reqeast
//

import Foundation
import os

private let cacheLogger = Logger(subsystem: "app.reqeast", category: "CloudSync.Cache")

/// Per-record disk cache for CKRecord system fields. The in-memory map used to be JSON-encoded
/// into a single UserDefaults value, which exceeds Apple's 4 MB per-key limit on large libraries.
enum CloudSyncLastKnownRecordStore {

    static let recordsDirectoryName = "last-known-records"

    #if DEBUG
    static var directoryOverride: URL?
    #endif

    // MARK: - Load / save

    static func allRecordNames() -> Set<String> {
        let directory = recordsDirectory()
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }
        return Set(urls.compactMap { recordName(from: $0) })
    }

    static func load(recordName: String) -> Data? {
        let url = fileURL(for: recordName)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? Data(contentsOf: url)
    }

    static func save(recordName: String, data: Data) throws {
        let directory = recordsDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let fileURL = fileURL(for: recordName)
        let tempURL = directory.appendingPathComponent("\(fileName(for: recordName)).tmp")
        try data.write(to: tempURL, options: .atomic)

        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: fileURL)
    }

    static func remove(recordName: String) {
        let url = fileURL(for: recordName)
        try? FileManager.default.removeItem(at: url)
    }

    static func removeAll() {
        let directory = recordsDirectory()
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// One-time import from the legacy monolithic UserDefaults blob.
    static func migrateFromUserDefaults(storage: UserDefaults, key: String) -> Int {
        guard let data = storage.data(forKey: key) else { return 0 }
        guard let legacy = try? JSONDecoder().decode([String: Data].self, from: data) else {
            cacheLogger.fault("Failed to decode legacy last-known records from UserDefaults")
            return 0
        }

        var migrated = 0
        for (recordName, recordData) in legacy {
            do {
                try save(recordName: recordName, data: recordData)
                migrated += 1
            } catch {
                cacheLogger.fault("Failed to migrate last-known record \(recordName): \(error)")
            }
        }
        storage.removeObject(forKey: key)
        cacheLogger.info("Migrated \(migrated) last-known records from UserDefaults to disk")
        return migrated
    }

    // MARK: - Paths

    private static func recordsDirectory() -> URL {
        #if DEBUG
        if let override = directoryOverride {
            return override
        }
        #endif
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return appSupport
            .appendingPathComponent("reqeast", isDirectory: true)
            .appendingPathComponent(StorageEnvironment.syncCacheDirName, isDirectory: true)
            .appendingPathComponent(recordsDirectoryName, isDirectory: true)
    }

    private static func fileURL(for recordName: String) -> URL {
        recordsDirectory().appendingPathComponent("\(fileName(for: recordName)).archive")
    }

    private static func fileName(for recordName: String) -> String {
        recordName.replacingOccurrences(of: "/", with: "__")
    }

    private static func recordName(from fileURL: URL) -> String? {
        guard fileURL.pathExtension == "archive" else { return nil }
        let base = fileURL.deletingPathExtension().lastPathComponent
        guard base.contains("__") else { return nil }
        return base.replacingOccurrences(of: "__", with: "/")
    }
}