//
//  ProjectStoreFolderDeleteTests.swift
//  ReqeastTests
//

import Foundation
import Testing
@testable import Reqeast

@Suite("ProjectStore Folder Delete", .serialized)
struct ProjectStoreFolderDeleteTests {

    @Test @MainActor func deleteFolderBumpsProjectUpdatedAt() {
        let store = ProjectStore.mock()
        let folder = ProjectFolder(name: "APIs")
        store.folders.append(folder)
        var project = Project(name: "My API", folderId: folder.id)
        project.updatedAt = Date(timeIntervalSince1970: 1000)
        store.projects.append(project)

        let tombstones = DeletionTombstoneStore(storage: .init(suiteName: "test-folder-delete")!)
        store.deleteFolder(folder, tombstones: tombstones)

        let updated = store.projects.first!
        #expect(updated.folderId == nil)
        #expect(updated.updatedAt > Date(timeIntervalSince1970: 1000))
    }

    @Test @MainActor func deleteRequestFolderBumpsRequestUpdatedAt() {
        let store = ProjectStore.mock()
        let projectId = UUID()
        let folder = RequestFolder(projectId: projectId, name: "Auth")
        store.requestFolders.append(folder)
        var request = Request(projectId: projectId, name: "Login", folderId: folder.id)
        request.updatedAt = Date(timeIntervalSince1970: 1000)
        store.requests.append(request)

        let tombstones = DeletionTombstoneStore(storage: .init(suiteName: "test-rf-delete")!)
        store.deleteRequestFolder(folder, tombstones: tombstones)

        let updated = store.requests.first!
        #expect(updated.folderId == nil)
        #expect(updated.updatedAt > Date(timeIntervalSince1970: 1000))
    }
}
