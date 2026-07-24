import Foundation
import os

private let logger = Logger(subsystem: "app.reqeast", category: "DeletionTombstoneStore")

@MainActor
final class DeletionTombstoneStore {
    static let shared = DeletionTombstoneStore(storage: .standard)

    private static let storageKey = "deletionTombstones"
    private let storage: UserDefaults

    private(set) var tombstones: [UUID: Date]

    init(storage: UserDefaults) {
        self.storage = storage
        if let data = storage.data(forKey: Self.storageKey) {
            do {
                tombstones = try JSONDecoder().decode([UUID: Date].self, from: data)
            } catch {
                logger.fault("Failed to decode tombstones: \(error). Backing up corrupt data.")
                let timestamp = Int(Date().timeIntervalSince1970)
                storage.set(data, forKey: "\(Self.storageKey)_corrupt_backup_\(timestamp)")
                tombstones = [:]
            }
        } else {
            tombstones = [:]
        }
    }

    func add(ids: [UUID]) {
        let now = Date()
        for id in ids {
            tombstones[id] = now
        }
        persist()
    }

    func add(id: UUID, date: Date) {
        tombstones[id] = date
        persist()
    }

    func contains(_ id: UUID) -> Bool {
        tombstones[id] != nil
    }

    func pruneOlderThan(days: Int) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
        tombstones = tombstones.filter { $0.value > cutoff }
        persist()
    }

    func clear() {
        tombstones = [:]
        persist()
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(tombstones)
            storage.set(data, forKey: Self.storageKey)
        } catch {
            logger.fault("Failed to persist tombstones: \(error)")
        }
    }
}
