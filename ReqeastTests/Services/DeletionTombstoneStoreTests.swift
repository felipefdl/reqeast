import Foundation
import Testing
@testable import Reqeast

@Suite("DeletionTombstoneStore")
struct DeletionTombstoneStoreTests {

    @Test func addAndContains() {
        let store = DeletionTombstoneStore(storage: .init(suiteName: "test.\(UUID())")!)
        let id = UUID()
        store.add(ids: [id])
        #expect(store.contains(id))
    }

    @Test func doesNotContainUnknownId() {
        let store = DeletionTombstoneStore(storage: .init(suiteName: "test.\(UUID())")!)
        store.add(ids: [UUID()])
        #expect(!store.contains(UUID()))
    }

    @Test func pruneRemovesOldEntries() {
        let store = DeletionTombstoneStore(storage: .init(suiteName: "test.\(UUID())")!)
        let oldId = UUID()
        let recentId = UUID()
        store.add(id: oldId, date: Date.distantPast)
        store.add(id: recentId, date: Date())

        store.pruneOlderThan(days: 90)

        #expect(!store.contains(oldId))
        #expect(store.contains(recentId))
    }

    @Test func persistAndReload() {
        let suiteName = "test.\(UUID())"
        let id = UUID()

        let store1 = DeletionTombstoneStore(storage: .init(suiteName: suiteName)!)
        store1.add(ids: [id])

        let store2 = DeletionTombstoneStore(storage: .init(suiteName: suiteName)!)
        #expect(store2.contains(id))
    }

    @Test func clearRemovesAll() {
        let store = DeletionTombstoneStore(storage: .init(suiteName: "test.\(UUID())")!)
        store.add(ids: [UUID(), UUID(), UUID()])
        #expect(!store.tombstones.isEmpty)

        store.clear()
        #expect(store.tombstones.isEmpty)
    }

    @Test func pruneKeepsEntriesBelowBoundary() {
        let store = DeletionTombstoneStore(storage: .init(suiteName: "test.\(UUID())")!)
        let justInsideId = UUID()
        let justOutsideId = UUID()
        // 89 days old: should be kept; 91 days old: should be pruned at days: 90
        let dayInSeconds: TimeInterval = 86_400
        store.add(id: justInsideId, date: Date(timeIntervalSinceNow: -89 * dayInSeconds))
        store.add(id: justOutsideId, date: Date(timeIntervalSinceNow: -91 * dayInSeconds))

        store.pruneOlderThan(days: 90)

        #expect(store.contains(justInsideId), "89-day tombstone must survive 90-day prune")
        #expect(!store.contains(justOutsideId), "91-day tombstone must be pruned at 90 days")
    }

    @Test func persistRoundTripsDates() {
        let suite = "test.\(UUID())"
        let id = UUID()
        let dayInSeconds: TimeInterval = 86_400

        let store1 = DeletionTombstoneStore(storage: .init(suiteName: suite)!)
        store1.add(id: id, date: Date(timeIntervalSinceNow: -200 * dayInSeconds))

        let store2 = DeletionTombstoneStore(storage: .init(suiteName: suite)!)
        store2.pruneOlderThan(days: 90)
        #expect(!store2.contains(id), "Stored date must survive reload so prune uses the original date, not now")
    }

    @Test func corruptBlobBacksUpAndResetsToEmpty() {
        let suite = "test.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        // Plant corrupt data under the storage key
        defaults.set("garbage".data(using: .utf8)!, forKey: "deletionTombstones")

        let store = DeletionTombstoneStore(storage: defaults)
        #expect(store.tombstones.isEmpty, "Decode failure must reset tombstones to empty")

        // Verify a backup key exists
        let allKeys = defaults.dictionaryRepresentation().keys
        let backupKeys = allKeys.filter { $0.hasPrefix("deletionTombstones_corrupt_backup_") }
        #expect(!backupKeys.isEmpty, "Corrupt data must be backed up under timestamped key")
    }
}
