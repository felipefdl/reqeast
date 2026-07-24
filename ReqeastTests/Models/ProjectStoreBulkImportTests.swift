//
//  ProjectStoreBulkImportTests.swift
//  ReqeastTests
//

import Foundation
import Testing
@testable import Reqeast

@Suite("ProjectStore Bulk Import", .serialized)
struct ProjectStoreBulkImportTests {

    @Test @MainActor func performBulkImportAddsAllItems() throws {
        let store = ProjectStore.mock()
        let project = Project(name: "Imported API")
        let projectId = project.id
        let folder = RequestFolder(projectId: projectId, name: "Auth")
        let requests = [
            Request(projectId: projectId, name: "GET /users"),
            Request(projectId: projectId, name: "POST /users", folderId: folder.id),
        ]
        let environment = ApiEnvironment(projectId: projectId, name: "Staging")

        try store.performBulkImport(
            project: project,
            folders: [folder],
            requests: requests,
            environments: [environment]
        )

        #expect(store.projects.count == 1)
        #expect(store.projects.first?.name == "Imported API")
        #expect(store.requestFolders.count == 1)
        #expect(store.requests.count == 2)
        #expect(store.environments.count == 1)
        #expect(store.requests(for: projectId).count == 2)
        #expect(!store.importInProgress)
    }

    @Test @MainActor func performBulkImportCallsSaveLocalAndQueueSaveBatchOnce() throws {
        let store = ProjectStore.mock()
        let sync = CloudSyncService.shared
        store.bulkImportSaveLocalCallCount = 0
        sync.queueSaveBatchCallCount = 0
        let dirtyBefore = sync.dirtyRecordIDs

        let project = Project(name: "Batch Import")
        let projectId = project.id
        let folder = RequestFolder(projectId: projectId, name: "Endpoints")
        let requests = [
            Request(projectId: projectId, name: "one"),
            Request(projectId: projectId, name: "two"),
            Request(projectId: projectId, name: "three"),
        ]
        let environment = ApiEnvironment(projectId: projectId, name: "prod")

        try store.performBulkImport(
            project: project,
            folders: [folder],
            requests: requests,
            environments: [environment]
        )

        #expect(store.bulkImportSaveLocalCallCount == 1)
        #expect(sync.queueSaveBatchCallCount == 1)

        let expectedNames: Set<String> = [
            "Project/\(project.id.uuidString)",
            "RequestFolder/\(folder.id.uuidString)",
            "Request/\(requests[0].id.uuidString)",
            "Request/\(requests[1].id.uuidString)",
            "Request/\(requests[2].id.uuidString)",
            "ApiEnvironment/\(environment.id.uuidString)",
        ]
        let newlyDirty = sync.dirtyRecordIDs.subtracting(dirtyBefore)
        #expect(newlyDirty == expectedNames)
    }

    @Test @MainActor func performBulkImportValidationFailureLeavesStoreUnchanged() {
        let store = ProjectStore.mock()
        let existingProject = Project(name: "Existing")
        store.projects.append(existingProject)

        let project = Project(name: "Would Orphan")
        let projectId = project.id

        var validRequest = Request(projectId: projectId, name: "ok")
        validRequest.touch()

        var oversizedRequest = Request(projectId: projectId, name: "too-large")
        oversizedRequest.httpData?.bodyContent = String(repeating: "x", count: 950_000)
        oversizedRequest.touch()

        do {
            try store.performBulkImport(
                project: project,
                folders: [],
                requests: [validRequest, oversizedRequest],
                environments: []
            )
            Issue.record("Expected performBulkImport to throw for oversized request")
        } catch let error as BulkImportError {
            if case .recordTooLarge(let recordType, let id, let byteCount) = error {
                #expect(recordType == .request)
                #expect(id == oversizedRequest.id)
                #expect(byteCount > CloudSyncService.maxRecordPayloadBytes)
            } else {
                Issue.record("Expected recordTooLarge, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }

        #expect(store.projects == [existingProject])
        #expect(store.requests.isEmpty)
        #expect(store.requestFolders.isEmpty)
        #expect(store.environments.isEmpty)
        #expect(!store.importInProgress)
    }

    @Test @MainActor func performBulkImportCommitFailureLeavesStoreUnchanged() {
        let store = ProjectStore.mock()
        let sync = CloudSyncService.shared
        let existingProject = Project(name: "Existing")
        store.projects.append(existingProject)
        store.bulkImportSaveLocalShouldFail = true
        sync.queueSaveBatchCallCount = 0

        let project = Project(name: "Would Commit")
        let projectId = project.id
        let request = Request(projectId: projectId, name: "GET /items")

        do {
            try store.performBulkImport(
                project: project,
                folders: [],
                requests: [request],
                environments: []
            )
            Issue.record("Expected performBulkImport to throw on persist failure")
        } catch let error as BulkImportError {
            #expect(error == .localPersistFailed)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }

        #expect(store.projects == [existingProject])
        #expect(store.requests.isEmpty)
        #expect(store.requestFolders.isEmpty)
        #expect(store.environments.isEmpty)
        #expect(sync.queueSaveBatchCallCount == 0)
        #expect(!store.importInProgress)
    }

    @Test @MainActor func performBulkMergeAppendsIntoExistingProject() throws {
        let store = ProjectStore.mock()
        let existingProject = Project(name: "Existing API")
        let projectId = existingProject.id
        let existingFolder = RequestFolder(projectId: projectId, name: "Auth")
        var existingRequest = Request(projectId: projectId, name: "GET /users", folderId: existingFolder.id)
        existingRequest.specIdentity = SpecOperationIdentity(primaryKey: "GET /users")
        store.projects.append(existingProject)
        store.requestFolders.append(existingFolder)
        store.requests.append(existingRequest)

        var updatedProject = existingProject
        updatedProject.specLink = SpecLink(
            format: .openapi,
            source: .file,
            contentFingerprint: "abc123",
            importedAt: Date()
        )

        let newFolder = RequestFolder(projectId: projectId, name: "Pets")
        let newRequest = Request(projectId: projectId, name: "GET /pets", folderId: newFolder.id)

        try store.performBulkMerge(
            project: updatedProject,
            folders: [newFolder],
            requests: [newRequest],
            environments: []
        )

        #expect(store.projects.count == 1)
        #expect(store.projects.first?.specLink?.contentFingerprint == "abc123")
        #expect(store.requestFolders.count == 2)
        #expect(store.requests.count == 2)
        #expect(store.requests(for: projectId).map(\.name).contains("GET /pets"))
        #expect(!store.importInProgress)
    }

    @Test @MainActor func performBulkMergeValidationFailureLeavesStoreUnchanged() {
        let store = ProjectStore.mock()
        let existingProject = Project(name: "Existing")
        let projectId = existingProject.id
        store.projects.append(existingProject)

        var oversizedRequest = Request(projectId: projectId, name: "too-large")
        oversizedRequest.httpData?.bodyContent = String(repeating: "x", count: 950_000)

        do {
            try store.performBulkMerge(
                project: existingProject,
                folders: [],
                requests: [oversizedRequest],
                environments: []
            )
            Issue.record("Expected performBulkMerge to throw for oversized request")
        } catch let error as BulkImportError {
            if case .recordTooLarge = error {
                #expect(true)
            } else {
                Issue.record("Expected recordTooLarge, got \(error)")
            }
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }

        #expect(store.projects == [existingProject])
        #expect(store.requests.isEmpty)
        #expect(!store.importInProgress)
    }

    @Test @MainActor func performBulkMergeCommitFailureLeavesStoreUnchanged() {
        let store = ProjectStore.mock()
        let sync = CloudSyncService.shared
        let existingProject = Project(name: "Existing")
        let projectId = existingProject.id
        store.projects.append(existingProject)
        store.bulkImportSaveLocalShouldFail = true
        sync.queueSaveBatchCallCount = 0

        let request = Request(projectId: projectId, name: "GET /items")

        do {
            try store.performBulkMerge(
                project: existingProject,
                folders: [],
                requests: [request],
                environments: []
            )
            Issue.record("Expected performBulkMerge to throw on persist failure")
        } catch let error as BulkImportError {
            #expect(error == .localPersistFailed)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }

        #expect(store.projects == [existingProject])
        #expect(store.requests.isEmpty)
        #expect(sync.queueSaveBatchCallCount == 0)
        #expect(!store.importInProgress)
    }

    @Test @MainActor func performBulkImportWithSpecDocumentQueuesSpecDocument() throws {
        let store = ProjectStore.mock()
        let sync = CloudSyncService.shared
        sync.queueSaveBatchCallCount = 0
        let dirtyBefore = sync.dirtyRecordIDs

        let project = Project(name: "Linked API")
        let projectId = project.id
        let specDocument = SpecDocument(
            id: projectId,
            projectId: projectId,
            contentFingerprint: "abc123",
            specFileName: "spec.json",
            sourceURL: "https://example.test/openapi.json",
            assetHydrated: true
        )

        try store.performBulkImport(
            project: project,
            folders: [],
            requests: [],
            environments: [],
            specDocument: specDocument
        )

        #expect(store.specDocuments.count == 1)
        let stored = try #require(store.specDocuments.first)
        #expect(stored.projectId == projectId)
        #expect(stored.contentFingerprint == "abc123")
        #expect(sync.queueSaveBatchCallCount == 1)

        let expectedNames: Set<String> = [
            "Project/\(project.id.uuidString)",
            "SpecDocument/\(projectId.uuidString)",
        ]
        let newlyDirty = sync.dirtyRecordIDs.subtracting(dirtyBefore)
        #expect(newlyDirty == expectedNames)
    }

    @Test @MainActor func performBulkImportClearsImportInProgressOnThrow() {
        let store = ProjectStore.mock()
        let project = Project(name: "Blocked")
        let projectId = project.id

        var oversizedRequest = Request(projectId: projectId, name: "too-large")
        oversizedRequest.httpData?.bodyContent = String(repeating: "y", count: 950_000)

        do {
            try store.performBulkImport(
                project: project,
                folders: [],
                requests: [oversizedRequest],
                environments: []
            )
            Issue.record("Expected performBulkImport to throw")
        } catch {
            #expect(!store.importInProgress)
        }
    }
}