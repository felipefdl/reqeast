//
//  CloudSyncLastKnownRecordStoreTests.swift
//  ReqeastTests
//

import Foundation
import Testing
@testable import Reqeast

@Suite("CloudSyncLastKnownRecordStore", .serialized)
struct CloudSyncLastKnownRecordStoreTests {
    @Test @MainActor func saveLoadRoundTrip() throws {
        let tempDir = try makeTempDirectory()
        defer { cleanup(tempDir) }

        let recordName = "Request/\(UUID().uuidString)"
        let payload = Data("archive-bytes".utf8)
        try CloudSyncLastKnownRecordStore.save(recordName: recordName, data: payload)

        #expect(CloudSyncLastKnownRecordStore.load(recordName: recordName) == payload)
        #expect(CloudSyncLastKnownRecordStore.allRecordNames().contains(recordName))
    }

    @Test @MainActor func removeDeletesRecord() throws {
        let tempDir = try makeTempDirectory()
        defer { cleanup(tempDir) }

        let recordName = "Project/\(UUID().uuidString)"
        try CloudSyncLastKnownRecordStore.save(recordName: recordName, data: Data([0x01]))
        CloudSyncLastKnownRecordStore.remove(recordName: recordName)

        #expect(CloudSyncLastKnownRecordStore.load(recordName: recordName) == nil)
        #expect(!CloudSyncLastKnownRecordStore.allRecordNames().contains(recordName))
    }

    @Test @MainActor func migrateFromUserDefaultsWritesPerRecordFiles() throws {
        let tempDir = try makeTempDirectory()
        defer { cleanup(tempDir) }

        let defaults = UserDefaults(suiteName: "CloudSyncLastKnownRecordStoreTests")!
        defaults.removePersistentDomain(forName: "CloudSyncLastKnownRecordStoreTests")
        defer { defaults.removePersistentDomain(forName: "CloudSyncLastKnownRecordStoreTests") }

        let key = "test.cloudSyncLastKnownRecords"
        let legacy: [String: Data] = [
            "Request/\(UUID().uuidString)": Data("one".utf8),
            "Project/\(UUID().uuidString)": Data("two".utf8),
        ]
        defaults.set(try JSONEncoder().encode(legacy), forKey: key)

        let migrated = CloudSyncLastKnownRecordStore.migrateFromUserDefaults(storage: defaults, key: key)
        #expect(migrated == 2)
        #expect(defaults.data(forKey: key) == nil)
        #expect(CloudSyncLastKnownRecordStore.allRecordNames().count == 2)
    }

    @MainActor
    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("reqeast-sync-cache-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        CloudSyncLastKnownRecordStore.directoryOverride = url
        return url
    }

    @MainActor
    private func cleanup(_ directory: URL) {
        CloudSyncLastKnownRecordStore.directoryOverride = nil
        try? FileManager.default.removeItem(at: directory)
    }
}