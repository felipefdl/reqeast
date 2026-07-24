//
//  ProjectStoreSyncTests.swift
//  ReqeastTests
//

import Foundation
import Testing
@testable import Reqeast

@Suite("ProjectStore Sync", .serialized)
struct ProjectStoreSyncTests {

    // MARK: - applyRemoteUpsert

    @Test @MainActor func upsertNewProjectAppendsIt() {
        let store = ProjectStore.mock()
        let project = Project(name: "Remote Project")
        store.applyRemoteUpsert(project)
        #expect(store.projects.count == 1)
        #expect(store.projects.first?.name == "Remote Project")
    }

    @Test @MainActor func upsertExistingWithNewerTimestampReplaces() {
        let store = ProjectStore.mock()
        var original = Project(name: "Original")
        original.updatedAt = Date(timeIntervalSince1970: 1000)
        store.projects.append(original)

        var updated = original
        updated.name = "Updated"
        updated.updatedAt = Date(timeIntervalSince1970: 2000)
        store.applyRemoteUpsert(updated)

        #expect(store.projects.count == 1)
        #expect(store.projects.first?.name == "Updated")
    }

    @Test @MainActor func upsertExistingWithOlderTimestampIsRejected() {
        let store = ProjectStore.mock()
        var original = Project(name: "Original")
        original.updatedAt = Date(timeIntervalSince1970: 2000)
        store.projects.append(original)

        var stale = original
        stale.name = "Stale"
        stale.updatedAt = Date(timeIntervalSince1970: 1000)
        store.applyRemoteUpsert(stale)

        #expect(store.projects.count == 1)
        #expect(store.projects.first?.name == "Original")
    }

    @Test @MainActor func upsertNewRequestAppendsIt() {
        let store = ProjectStore.mock()
        let request = Request(projectId: UUID(), name: "GET /api")
        store.applyRemoteUpsert(request)
        #expect(store.requests.count == 1)
    }

    @Test @MainActor func upsertNewFolderAppendsIt() {
        let store = ProjectStore.mock()
        let folder = ProjectFolder(name: "APIs")
        store.applyRemoteUpsert(folder)
        #expect(store.folders.count == 1)
    }

    @Test @MainActor func upsertNewRequestFolderAppendsIt() {
        let store = ProjectStore.mock()
        let folder = RequestFolder(projectId: UUID(), name: "Auth")
        store.applyRemoteUpsert(folder)
        #expect(store.requestFolders.count == 1)
    }

    @Test @MainActor func upsertNewEnvironmentAppendsIt() {
        let store = ProjectStore.mock()
        let env = ApiEnvironment(projectId: UUID(), name: "Dev")
        store.applyRemoteUpsert(env)
        #expect(store.environments.count == 1)
    }

    @Test @MainActor func upsertWithEqualTimestampReplaces() {
        let store = ProjectStore.mock()
        let timestamp = Date(timeIntervalSince1970: 1000)
        var original = Project(name: "Original")
        original.updatedAt = timestamp
        store.projects.append(original)

        var updated = original
        updated.name = "Same Timestamp"
        updated.updatedAt = timestamp
        store.applyRemoteUpsert(updated)

        // >= means equal timestamps replace (server wins)
        #expect(store.projects.first?.name == "Same Timestamp")
    }

    // MARK: - applyRemoteDeletion

    @Test @MainActor func deleteProjectCascadesToChildren() {
        let store = ProjectStore.mock()
        let project = Project(name: "P")
        store.projects.append(project)
        store.requests.append(Request(projectId: project.id, name: "R"))
        store.requestFolders.append(RequestFolder(projectId: project.id, name: "RF"))
        store.environments.append(ApiEnvironment(projectId: project.id, name: "E"))

        store.applyRemoteDeletion(recordType: .project, id: project.id)

        #expect(store.projects.isEmpty)
        #expect(store.requests.isEmpty)
        #expect(store.requestFolders.isEmpty)
        #expect(store.environments.isEmpty)
    }

    @Test @MainActor func deleteProjectFolderUnfoldersProjects() {
        let store = ProjectStore.mock()
        let folder = ProjectFolder(name: "APIs")
        store.folders.append(folder)
        store.projects.append(Project(name: "P", folderId: folder.id))

        store.applyRemoteDeletion(recordType: .projectFolder, id: folder.id)

        #expect(store.folders.isEmpty)
        #expect(store.projects.count == 1)
        #expect(store.projects.first?.folderId == nil)
    }

    @Test @MainActor func deleteRequestRemovesOnlyThat() {
        let store = ProjectStore.mock()
        let projectId = UUID()
        let r1 = Request(projectId: projectId, name: "R1")
        let r2 = Request(projectId: projectId, name: "R2")
        store.requests.append(contentsOf: [r1, r2])

        store.applyRemoteDeletion(recordType: .request, id: r1.id)

        #expect(store.requests.count == 1)
        #expect(store.requests.first?.id == r2.id)
    }

    @Test @MainActor func deleteRequestFolderUnfoldersRequests() {
        let store = ProjectStore.mock()
        let projectId = UUID()
        let folder = RequestFolder(projectId: projectId, name: "Auth")
        store.requestFolders.append(folder)
        store.requests.append(Request(projectId: projectId, name: "R", folderId: folder.id))

        store.applyRemoteDeletion(recordType: .requestFolder, id: folder.id)

        #expect(store.requestFolders.isEmpty)
        #expect(store.requests.count == 1)
        #expect(store.requests.first?.folderId == nil)
    }

    @Test @MainActor func deleteEnvironmentRemovesOnlyThat() {
        let store = ProjectStore.mock()
        let projectId = UUID()
        let e1 = ApiEnvironment(projectId: projectId, name: "Dev")
        let e2 = ApiEnvironment(projectId: projectId, name: "Prod")
        store.environments.append(contentsOf: [e1, e2])

        store.applyRemoteDeletion(recordType: .apiEnvironment, id: e1.id)

        #expect(store.environments.count == 1)
        #expect(store.environments.first?.id == e2.id)
    }

    @Test @MainActor func deleteNonexistentIdIsNoOp() {
        let store = ProjectStore.mock()
        store.projects.append(Project(name: "P"))

        store.applyRemoteDeletion(recordType: .project, id: UUID())

        #expect(store.projects.count == 1)
    }

    // MARK: - Tombstone Guards

    @Test @MainActor func upsertRejectsItemInTombstoneTable() {
        let store = ProjectStore.mock()
        let project = Project(name: "Ghost")
        let tombstones = DeletionTombstoneStore(storage: .init(suiteName: "test.\(UUID())")!)
        tombstones.add(ids: [project.id])

        store.applyRemoteUpsert(project, tombstones: tombstones)
        #expect(store.projects.isEmpty)
    }

    @Test @MainActor func upsertRejectsChildOfTombstonedProject() {
        let store = ProjectStore.mock()
        let projectId = UUID()
        let request = Request(projectId: projectId, name: "Ghost Request")
        let tombstones = DeletionTombstoneStore(storage: .init(suiteName: "test.\(UUID())")!)
        tombstones.add(ids: [projectId])

        store.applyRemoteUpsert(request, tombstones: tombstones)
        #expect(store.requests.isEmpty)
    }

    @Test @MainActor func upsertSpecDocumentBlockedByProjectTombstone() {
        let store = ProjectStore.mock()
        let projectId = UUID()
        let document = SpecDocument(
            id: projectId,
            projectId: projectId,
            contentFingerprint: "ghost-fingerprint",
            specFileName: "spec.json",
            sourceURL: "https://example.test/openapi.json"
        )
        let tombstones = DeletionTombstoneStore(storage: .init(suiteName: "test.\(UUID())")!)
        tombstones.add(ids: [projectId])

        store.applyRemoteUpsert(document, tombstones: tombstones)
        #expect(store.specDocuments.isEmpty)
    }

    @Test @MainActor func upsertRejectsSoftDeletedLocalItem() {
        let store = ProjectStore.mock()
        var project = Project(name: "Local Deleted")
        project.deletedAt = Date()
        store.projects.append(project)
        let tombstones = DeletionTombstoneStore(storage: .init(suiteName: "test.\(UUID())")!)

        var remote = project
        remote.deletedAt = nil
        remote.updatedAt = Date(timeIntervalSinceNow: 100)
        store.applyRemoteUpsert(remote, tombstones: tombstones)

        // Local soft-delete wins, remote does not overwrite
        #expect(store.projects.first?.deletedAt != nil)
    }

    // MARK: - Backward-compatible decoding (deletedAt)

    @Test func decodingProjectWithoutDeletedAtDefaultsToNil() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-000000000001","name":"Test","color":"gray","createdAt":0,"updatedAt":0}
        """
        let project = try JSONDecoder().decode(Project.self, from: Data(json.utf8))
        #expect(project.deletedAt == nil)
    }

    @Test func decodingProjectWithDeletedAtPreservesIt() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-000000000001","name":"Test","color":"gray","createdAt":0,"updatedAt":0,"deletedAt":1000}
        """
        let project = try JSONDecoder().decode(Project.self, from: Data(json.utf8))
        #expect(project.deletedAt != nil)
    }

    // MARK: - Cascade Delete Tombstones

    @Test @MainActor func deleteProjectRecordsTombstones() {
        let store = ProjectStore.mock()
        let tombstones = DeletionTombstoneStore(storage: .init(suiteName: "test.\(UUID())")!)

        let project = Project(name: "P")
        store.projects.append(project)
        let request = Request(projectId: project.id, name: "R")
        store.requests.append(request)
        let folder = RequestFolder(projectId: project.id, name: "RF")
        store.requestFolders.append(folder)
        let env = ApiEnvironment(projectId: project.id, name: "E")
        store.environments.append(env)

        store.cascadeDeleteProject(id: project.id, queueCloudDeletes: false, tombstones: tombstones)

        #expect(tombstones.contains(project.id))
        #expect(tombstones.contains(request.id))
        #expect(tombstones.contains(folder.id))
        #expect(tombstones.contains(env.id))
    }

    // MARK: - Individual Delete Tombstones

    @Test @MainActor func deleteFolderRecordsTombstone() {
        let store = ProjectStore.mock()
        let tombstones = DeletionTombstoneStore(storage: .init(suiteName: "test.\(UUID())")!)

        let folder = ProjectFolder(name: "APIs")
        store.folders.append(folder)
        store.projects.append(Project(name: "P", folderId: folder.id))

        store.deleteFolder(folder, tombstones: tombstones)

        #expect(tombstones.contains(folder.id))
        #expect(store.folders.isEmpty)
        #expect(store.projects.first?.folderId == nil)
    }

    @Test @MainActor func deleteRequestRecordsTombstone() {
        let store = ProjectStore.mock()
        let tombstones = DeletionTombstoneStore(storage: .init(suiteName: "test.\(UUID())")!)

        let request = Request(projectId: UUID(), name: "R")
        store.requests.append(request)

        store.deleteRequest(request, tombstones: tombstones)

        #expect(tombstones.contains(request.id))
        #expect(store.requests.isEmpty)
    }

    @Test @MainActor func deleteRequestFolderRecordsTombstone() {
        let store = ProjectStore.mock()
        let tombstones = DeletionTombstoneStore(storage: .init(suiteName: "test.\(UUID())")!)

        let projectId = UUID()
        let folder = RequestFolder(projectId: projectId, name: "Auth")
        store.requestFolders.append(folder)
        store.requests.append(Request(projectId: projectId, name: "R", folderId: folder.id))

        store.deleteRequestFolder(folder, tombstones: tombstones)

        #expect(tombstones.contains(folder.id))
        #expect(store.requestFolders.isEmpty)
        #expect(store.requests.first?.folderId == nil)
    }

    @Test @MainActor func updateEnvironmentsRecordsTombstonesForRemoved() {
        let store = ProjectStore.mock()
        let tombstones = DeletionTombstoneStore(storage: .init(suiteName: "test.\(UUID())")!)

        let projectId = UUID()
        let env1 = ApiEnvironment(projectId: projectId, name: "Dev")
        let env2 = ApiEnvironment(projectId: projectId, name: "Prod")
        store.environments.append(contentsOf: [env1, env2])

        // Update with only env1 (env2 is removed)
        store.updateEnvironments([env1], for: projectId, tombstones: tombstones)

        #expect(tombstones.contains(env2.id))
        #expect(!tombstones.contains(env1.id))
    }

    // MARK: - Individual Delete Ghost Prevention

    @Test @MainActor func individualDeleteBlocksGhostRecordAfterPurge() {
        let store = ProjectStore.mock()
        let tombstones = DeletionTombstoneStore(storage: .init(suiteName: "test.\(UUID())")!)

        // Create a project with a request
        let project = Project(name: "My API")
        store.projects.append(project)
        let request = Request(projectId: project.id, name: "GET /users")
        store.requests.append(request)

        // Individual delete (not bulk reset)
        store.cascadeDeleteProject(id: project.id, queueCloudDeletes: false, tombstones: tombstones)

        #expect(store.projects.isEmpty)
        #expect(store.requests.isEmpty)

        // Ghost record arrives from CloudKit (same UUID, different data)
        let ghost = Project(id: project.id, name: "Ghost")
        store.applyRemoteUpsert(ghost, tombstones: tombstones)
        #expect(store.projects.isEmpty) // blocked by tombstone

        // Ghost child arrives too
        let ghostRequest = Request(id: request.id, projectId: project.id, name: "Ghost Request")
        store.applyRemoteUpsert(ghostRequest, tombstones: tombstones)
        #expect(store.requests.isEmpty) // blocked by tombstone
    }

    @Test @MainActor func individualRequestDeleteBlocksGhost() {
        let store = ProjectStore.mock()
        let tombstones = DeletionTombstoneStore(storage: .init(suiteName: "test.\(UUID())")!)

        let request = Request(projectId: UUID(), name: "DELETE me")
        store.requests.append(request)

        store.deleteRequest(request, tombstones: tombstones)
        #expect(store.requests.isEmpty)

        // Ghost arrives
        let ghost = Request(id: request.id, projectId: request.projectId, name: "Ghost")
        store.applyRemoteUpsert(ghost, tombstones: tombstones)
        #expect(store.requests.isEmpty)
    }

    // MARK: - Full Reset Flow Integration

    @Test @MainActor func fullResetFlowBlocksGhostData() {
        let store = ProjectStore.mock()
        let tombstones = DeletionTombstoneStore(storage: .init(suiteName: "test.\(UUID())")!)

        // Setup: active project with request and environment
        let project = Project(name: "My API")
        store.addProject(project)
        store.requests.append(Request(projectId: project.id, name: "GET /users"))
        store.environments.append(ApiEnvironment(projectId: project.id, name: "Prod"))

        // Soft delete all
        let ids = store.softDeleteAll()
        tombstones.add(ids: ids)

        // Verify hidden from queries
        #expect(store.unfolderedProjects.isEmpty)
        #expect(store.requests(for: project.id).isEmpty)
        #expect(store.environments(for: project.id).isEmpty)

        // Items still in raw arrays (waiting for CK delete confirmation)
        #expect(store.projects.count == 1)
        #expect(store.requests.count == 1)
        #expect(store.environments.count == 1)

        // Simulate ghost data arriving via remote upsert
        let ghost = Project(id: project.id, name: "Ghost")
        store.applyRemoteUpsert(ghost, tombstones: tombstones)
        #expect(store.projects.count == 1)
        #expect(store.projects.first?.deletedAt != nil) // still soft-deleted

        // Simulate ghost child arriving
        let ghostRequest = Request(projectId: project.id, name: "Ghost Request")
        store.applyRemoteUpsert(ghostRequest, tombstones: tombstones)
        #expect(store.requests.count == 1) // rejected, not added

        // Simulate CK delete confirmed -> purge
        store.purgeDeletedItem(recordType: .project, id: project.id)
        #expect(store.projects.isEmpty)

        // Ghost arrives AFTER purge -> still blocked by tombstone
        let lateGhost = Project(id: project.id, name: "Late Ghost")
        store.applyRemoteUpsert(lateGhost, tombstones: tombstones)
        #expect(store.projects.isEmpty)
    }

    // MARK: - importInProgress Guard

    @Test @MainActor func upsertSkippedWhenImportInProgress() {
        let store = ProjectStore.mock()
        store.importInProgress = true

        store.applyRemoteUpsert(Project(name: "Remote"))
        #expect(store.projects.isEmpty)
    }

    @Test @MainActor func deletionSkippedWhenImportInProgress() {
        let store = ProjectStore.mock()
        let project = Project(name: "P")
        store.projects.append(project)
        store.requests.append(Request(projectId: project.id, name: "R"))

        store.importInProgress = true
        store.applyRemoteDeletion(recordType: .project, id: project.id)

        #expect(store.projects.count == 1)
        #expect(store.requests.count == 1)
    }

    @Test @MainActor func purgeSkippedWhenImportInProgress() {
        let store = ProjectStore.mock()
        var project = Project(name: "P")
        project.deletedAt = Date()
        store.projects.append(project)

        store.importInProgress = true
        store.purgeDeletedItem(recordType: .project, id: project.id)

        #expect(store.projects.count == 1)
    }

    @Test @MainActor func upsertAppliesAfterImportCompletes() {
        let store = ProjectStore.mock()
        store.importInProgress = true
        store.applyRemoteUpsert(Project(name: "During Import"))
        #expect(store.projects.isEmpty)

        store.importInProgress = false
        store.applyRemoteUpsert(Project(name: "After Import"))
        #expect(store.projects.count == 1)
        #expect(store.projects.first?.name == "After Import")
    }

    @Test @MainActor func withRemoteBatchDoesNotClearImportInProgress() {
        let store = ProjectStore.mock()
        store.importInProgress = true

        store.withRemoteBatch {
            store.applyRemoteUpsert(Project(name: "Inside Batch"))
        }

        #expect(store.importInProgress)
        #expect(!store.isLoading)
        #expect(store.projects.isEmpty)
    }
}
