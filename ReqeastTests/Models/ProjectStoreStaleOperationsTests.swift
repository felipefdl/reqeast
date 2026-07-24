//
//  ProjectStoreStaleOperationsTests.swift
//  ReqeastTests
//

import Foundation
import Testing
@testable import Reqeast

@Suite("ProjectStore Stale Operations", .serialized)
struct ProjectStoreStaleOperationsTests {
    @Test @MainActor func dismissSpecStaleClearsFlag() {
        let store = ProjectStore.mock()
        let projectId = UUID()
        var request = Request(projectId: projectId, name: "Stale op")
        request.isSpecStale = true
        store.requests.append(request)

        store.dismissSpecStale(for: request)

        #expect(store.requests.first?.isSpecStale == false)
    }

    @Test @MainActor func dismissSpecStaleBatchUsesQueueSaveBatch() {
        let store = ProjectStore.mock()
        let projectId = UUID()
        var staleA = Request(projectId: projectId, name: "A")
        var staleB = Request(projectId: projectId, name: "B")
        var fresh = Request(projectId: projectId, name: "C")
        staleA.isSpecStale = true
        staleB.isSpecStale = true
        store.requests.append(contentsOf: [staleA, staleB, fresh])

        CloudSyncService.shared.queueSaveBatchCallCount = 0
        store.dismissSpecStale(for: [staleA, staleB, fresh])

        #expect(store.requests.filter(\.isSpecStale).isEmpty)
        #expect(CloudSyncService.shared.queueSaveBatchCallCount == 1)
    }

    @Test @MainActor func staleRequestsReturnsOnlyStaleForProject() {
        let store = ProjectStore.mock()
        let projectId = UUID()
        var stale = Request(projectId: projectId, name: "Stale")
        let fresh = Request(projectId: projectId, name: "Fresh")
        stale.isSpecStale = true
        store.requests.append(contentsOf: [stale, fresh])

        let result = store.staleRequests(for: projectId)

        #expect(result.count == 1)
        #expect(result.first?.name == "Stale")
    }

    @Test @MainActor func deleteRequestsRemovesOnlyTargets() {
        let store = ProjectStore.mock()
        let tombstones = DeletionTombstoneStore(storage: .init(suiteName: "test.\(UUID())")!)
        let projectId = UUID()
        var stale = Request(projectId: projectId, name: "Stale")
        let fresh = Request(projectId: projectId, name: "Fresh")
        stale.isSpecStale = true
        store.requests.append(contentsOf: [stale, fresh])

        store.deleteRequests([stale], tombstones: tombstones)

        #expect(store.requests.count == 1)
        #expect(store.requests.first?.name == "Fresh")
        #expect(tombstones.contains(stale.id))
        #expect(!tombstones.contains(fresh.id))
    }
}