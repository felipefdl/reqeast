//
//  ProjectStoreTests.swift
//  ReqeastTests
//

import Foundation
import Testing
@testable import Reqeast

@Suite("ProjectStore", .serialized)
struct ProjectStoreTests {
    @Test @MainActor func addAndRetrieveProject() {
        let store = ProjectStore.mock()
        let project = Project(name: "Test")
        store.addProject(project)
        #expect(store.projects.count == 1)
        #expect(store.projects.first?.name == "Test")
    }

    @Test @MainActor func deleteProjectRemovesRequests() {
        let store = ProjectStore.mock()
        let project = Project(name: "Test")
        store.addProject(project)
        let request = Request(projectId: project.id, name: "GET /api")
        store.addRequest(request)
        #expect(store.requests.count == 1)

        store.deleteProject(project)
        #expect(store.projects.isEmpty)
        #expect(store.requests.isEmpty)
    }

    @Test @MainActor func duplicateProjectCopiesRequests() {
        let store = ProjectStore.mock()
        let project = Project(name: "Original")
        store.addProject(project)
        store.addRequest(Request(projectId: project.id, name: "R1"))
        store.addRequest(Request(projectId: project.id, name: "R2"))

        let duplicate = store.duplicateProject(project)
        #expect(duplicate.name == "Original (2)")
        #expect(store.requests(for: duplicate.id).count == 2)
    }

    @Test @MainActor func folderOperations() {
        let store = ProjectStore.mock()
        let folder = ProjectFolder(name: "APIs", color: .blue)
        store.addFolder(folder)
        #expect(store.folders.count == 1)

        let project = Project(name: "Test", folderId: folder.id)
        store.addProject(project)
        #expect(store.projects(in: folder).count == 1)
        #expect(store.unfolderedProjects.isEmpty)

        store.deleteFolder(folder)
        #expect(store.folders.isEmpty)
        #expect(store.unfolderedProjects.count == 1)
    }

    @Test @MainActor func environmentOperations() {
        let store = ProjectStore.mock()
        let projectId = UUID()
        let env = ApiEnvironment(projectId: projectId, name: "Dev", variables: [
            EnvironmentVariable(key: "host", value: "localhost")
        ], isActive: true)
        store.updateEnvironments([env], for: projectId)
        #expect(store.environments(for: projectId).count == 1)
        #expect(store.activeEnvironment(for: projectId)?.name == "Dev")
    }

    @Test @MainActor func resetAllDataClearsEverything() {
        let store = ProjectStore.mock()
        store.addProject(Project(name: "P"))
        store.addFolder(ProjectFolder(name: "F"))
        store.addRequest(Request(projectId: UUID(), name: "R"))
        store.addRequestFolder(RequestFolder(projectId: UUID(), name: "RF"))
        store.resetAllData()
        #expect(store.projects.isEmpty)
        #expect(store.folders.isEmpty)
        #expect(store.requests.isEmpty)
        #expect(store.requestFolders.isEmpty)
    }

    // MARK: - Request Folder Operations

    @Test @MainActor func requestFolderCRUD() {
        let store = ProjectStore.mock()
        let projectId = UUID()
        let folder = RequestFolder(projectId: projectId, name: "Auth", color: .red)
        store.addRequestFolder(folder)
        #expect(store.requestFolders.count == 1)
        #expect(store.requestFolders(for: projectId).count == 1)
        #expect(store.requestFolders(for: projectId).first?.name == "Auth")

        var updated = folder
        updated.name = "Authentication"
        store.updateRequestFolder(updated)
        #expect(store.requestFolders(for: projectId).first?.name == "Authentication")

        // Folders for a different project should be empty
        #expect(store.requestFolders(for: UUID()).isEmpty)
    }

    @Test @MainActor func deleteRequestFolderMovesRequestsToRoot() {
        let store = ProjectStore.mock()
        let projectId = UUID()
        let folder = RequestFolder(projectId: projectId, name: "Auth")
        store.addRequestFolder(folder)

        let request = Request(projectId: projectId, name: "Login", folderId: folder.id)
        store.addRequest(request)
        #expect(store.requests(for: projectId, inFolder: folder.id).count == 1)
        #expect(store.unfolderedRequests(for: projectId).isEmpty)

        store.deleteRequestFolder(folder)
        #expect(store.requestFolders.isEmpty)
        #expect(store.unfolderedRequests(for: projectId).count == 1)
        #expect(store.requests.first?.folderId == nil)
    }

    @Test @MainActor func moveRequestBetweenFolders() {
        let store = ProjectStore.mock()
        let projectId = UUID()
        let folderA = RequestFolder(projectId: projectId, name: "A")
        let folderB = RequestFolder(projectId: projectId, name: "B")
        store.addRequestFolder(folderA)
        store.addRequestFolder(folderB)

        let request = Request(projectId: projectId, name: "R1")
        store.addRequest(request)
        #expect(store.unfolderedRequests(for: projectId).count == 1)

        store.moveRequest(request, toFolder: folderA)
        #expect(store.requests(for: projectId, inFolder: folderA.id).count == 1)
        #expect(store.unfolderedRequests(for: projectId).isEmpty)

        let movedRequest = store.requests.first!
        store.moveRequest(movedRequest, toFolder: folderB)
        #expect(store.requests(for: projectId, inFolder: folderA.id).isEmpty)
        #expect(store.requests(for: projectId, inFolder: folderB.id).count == 1)

        let movedAgain = store.requests.first!
        store.moveRequest(movedAgain, toFolder: nil)
        #expect(store.unfolderedRequests(for: projectId).count == 1)
    }

    @Test @MainActor func deleteProjectRemovesRequestFolders() {
        let store = ProjectStore.mock()
        let project = Project(name: "Test")
        store.addProject(project)
        store.addRequestFolder(RequestFolder(projectId: project.id, name: "F1"))
        store.addRequestFolder(RequestFolder(projectId: project.id, name: "F2"))
        #expect(store.requestFolders.count == 2)

        store.deleteProject(project)
        #expect(store.requestFolders.isEmpty)
    }

    // MARK: - Soft Delete Filtering

    @Test @MainActor func queriesExcludeSoftDeletedItems() {
        let store = ProjectStore.mock()
        let folder = ProjectFolder(name: "F")
        store.addFolder(folder)

        let activeProject = Project(name: "Active", folderId: folder.id)
        store.addProject(activeProject)

        var deletedProject = Project(name: "Deleted", folderId: folder.id)
        deletedProject.deletedAt = Date()
        store.projects.append(deletedProject)

        // projects(in:) should exclude soft-deleted
        #expect(store.projects(in: folder).count == 1)
        #expect(store.projects(in: folder).first?.name == "Active")

        // unfolderedProjects should exclude soft-deleted
        var deletedUnfoldered = Project(name: "Deleted Unfoldered")
        deletedUnfoldered.deletedAt = Date()
        store.projects.append(deletedUnfoldered)
        #expect(store.unfolderedProjects.allSatisfy { $0.deletedAt == nil })

        // sortedFolders should exclude soft-deleted
        var deletedFolder = ProjectFolder(name: "Dead")
        deletedFolder.deletedAt = Date()
        store.folders.append(deletedFolder)
        #expect(store.sortedFolders.count == 1)
    }

    @Test @MainActor func requestQueriesExcludeSoftDeleted() {
        let store = ProjectStore.mock()
        let projectId = UUID()

        let active = Request(projectId: projectId, name: "Active")
        store.requests.append(active)

        var deleted = Request(projectId: projectId, name: "Deleted")
        deleted.deletedAt = Date()
        store.requests.append(deleted)

        #expect(store.requests(for: projectId).count == 1)
        #expect(store.unfolderedRequests(for: projectId).count == 1)
    }

    @Test @MainActor func environmentQueriesExcludeSoftDeleted() {
        let store = ProjectStore.mock()
        let projectId = UUID()
        store.environments.append(ApiEnvironment(projectId: projectId, name: "Active"))

        var deleted = ApiEnvironment(projectId: projectId, name: "Deleted")
        deleted.deletedAt = Date()
        store.environments.append(deleted)

        #expect(store.environments(for: projectId).count == 1)
        #expect(store.activeEnvironment(for: projectId) == nil) // neither is active
    }

    // MARK: - Duplicate Project

    @Test @MainActor func softDeleteAllMarksAllItemsDeleted() {
        let store = ProjectStore.mock()
        store.addProject(Project(name: "P1"))
        store.addProject(Project(name: "P2"))
        store.addFolder(ProjectFolder(name: "F"))
        let projectId = UUID()
        store.requests.append(Request(projectId: projectId, name: "R"))
        store.requestFolders.append(RequestFolder(projectId: projectId, name: "RF"))
        store.environments.append(ApiEnvironment(projectId: projectId, name: "E"))

        let ids = store.softDeleteAll()

        // Items still in arrays but all have deletedAt set
        #expect(store.projects.allSatisfy { $0.deletedAt != nil })
        #expect(store.folders.allSatisfy { $0.deletedAt != nil })
        #expect(store.requests.allSatisfy { $0.deletedAt != nil })
        #expect(store.requestFolders.allSatisfy { $0.deletedAt != nil })
        #expect(store.environments.allSatisfy { $0.deletedAt != nil })

        // Returned IDs contain all items
        #expect(ids.count == 6) // 2 projects + 1 folder + 1 request + 1 requestFolder + 1 env

        // Filtered queries return empty
        #expect(store.unfolderedProjects.isEmpty)
        #expect(store.sortedFolders.isEmpty)
    }

    @Test @MainActor func duplicateProjectCopiesRequestFolders() {
        let store = ProjectStore.mock()
        let project = Project(name: "API")
        store.addProject(project)

        let folder = RequestFolder(projectId: project.id, name: "Auth", color: .green)
        store.addRequestFolder(folder)

        let request = Request(projectId: project.id, name: "Login", folderId: folder.id)
        store.addRequest(request)

        let duplicate = store.duplicateProject(project)

        // Should have folders for both projects
        let originalFolders = store.requestFolders(for: project.id)
        let duplicatedFolders = store.requestFolders(for: duplicate.id)
        #expect(originalFolders.count == 1)
        #expect(duplicatedFolders.count == 1)
        #expect(duplicatedFolders.first?.name == "Auth")
        #expect(duplicatedFolders.first?.color == .green)

        // Duplicated request should reference the new folder, not the original
        let duplicatedRequests = store.requests(for: duplicate.id)
        #expect(duplicatedRequests.count == 1)
        #expect(duplicatedRequests.first?.folderId == duplicatedFolders.first?.id)
        #expect(duplicatedRequests.first?.folderId != folder.id)
    }

    // MARK: - Deduplication

    @Test @MainActor func deduplicateKeepsLatestByUpdatedAt() {
        let store = ProjectStore.mock()

        let id = UUID()
        var older = Project(id: id, name: "Older")
        older.updatedAt = Date(timeIntervalSince1970: 1000)
        var newer = Project(id: id, name: "Newer")
        newer.updatedAt = Date(timeIntervalSince1970: 2000)

        store.projects = [older, newer]
        store.deduplicate()

        #expect(store.projects.count == 1)
        #expect(store.projects.first?.name == "Newer")
    }

    @Test @MainActor func deduplicatePreservesUniqueItems() {
        let store = ProjectStore.mock()

        let p1 = Project(name: "A")
        let p2 = Project(name: "B")
        store.projects = [p1, p2]
        store.deduplicate()

        #expect(store.projects.count == 2)
    }

    @Test @MainActor func deduplicateHandlesAllArrays() {
        let store = ProjectStore.mock()

        let projectId = UUID()
        let reqId = UUID()
        var r1 = Request(id: reqId, projectId: projectId, name: "Older")
        r1.updatedAt = Date(timeIntervalSince1970: 1000)
        var r2 = Request(id: reqId, projectId: projectId, name: "Newer")
        r2.updatedAt = Date(timeIntervalSince1970: 2000)

        store.requests = [r1, r2]
        store.deduplicate()

        #expect(store.requests.count == 1)
        #expect(store.requests.first?.name == "Newer")
    }

}
