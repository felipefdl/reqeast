//
//  ProjectStore+Folders.swift
//  Reqeast
//

import Foundation

extension ProjectStore {

    // MARK: - Folder Operations

    func addFolder(_ folder: ProjectFolder) {
        folders.append(folder)
        saveAll()
        CloudSyncService.shared.queueSave(folder)
    }

    func updateFolder(_ folder: ProjectFolder) {
        guard let index = folders.firstIndex(where: { $0.id == folder.id }) else { return }
        var updated = folder
        updated.touch()
        folders[index] = updated
        saveAll()
        CloudSyncService.shared.queueSave(folders[index])
    }

    func deleteFolder(_ folder: ProjectFolder, tombstones: DeletionTombstoneStore = .shared) {
        tombstones.add(ids: [folder.id])
        let affectedProjects = projects.enumerated().filter { $0.element.folderId == folder.id }
        isLoading = true
        for i in projects.indices where projects[i].folderId == folder.id {
            projects[i].folderId = nil
            projects[i].updatedAt = Date()
        }
        folders.removeAll { $0.id == folder.id }
        isLoading = false
        saveAll()
        CloudSyncService.shared.queueDelete(recordType: .projectFolder, id: folder.id)
        for (i, _) in affectedProjects {
            CloudSyncService.shared.queueSave(projects[i])
        }
    }

    func moveProject(_ project: Project, to folder: ProjectFolder?) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[index].folderId = folder?.id
        projects[index].touch()
        saveAll()
        CloudSyncService.shared.queueSave(projects[index])
    }
}
