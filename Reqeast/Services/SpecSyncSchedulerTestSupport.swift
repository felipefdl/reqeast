//
//  SpecSyncSchedulerTestSupport.swift
//  Reqeast
//

import Foundation

#if DEBUG
/// Deterministic hooks for `SpecSyncSchedulerTests` (no network).
enum SpecSyncSchedulerTestSupport {
    static var isEnabled: Bool {
        StorageEnvironment.isRunningTests
            || ProcessInfo.processInfo.arguments.contains("-specSyncSchedulerTest")
    }

    private static let lock = NSLock()
    private nonisolated(unsafe) static var fetchCounts: [UUID: Int] = [:]

    static func reset() {
        lock.withLock {
            fetchCounts = [:]
        }
    }

    static func recordFetch(projectId: UUID) {
        guard isEnabled else { return }
        lock.withLock {
            fetchCounts[projectId, default: 0] += 1
        }
    }

    static func fetchCount(for projectId: UUID) -> Int {
        lock.withLock {
            fetchCounts[projectId, default: 0]
        }
    }

    static var totalFetchCount: Int {
        lock.withLock {
            fetchCounts.values.reduce(0, +)
        }
    }
}
#endif