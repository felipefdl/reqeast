//
//  ProjectStore+Projects.swift
//  Reqeast
//

import Foundation

extension ProjectStore {

    // MARK: - Project Operations

    func addProject(_ project: Project) {
        projects.append(project)
        saveAll()
        CloudSyncService.shared.queueSave(project)
    }

    func updateProject(_ project: Project) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        var updated = project
        updated.touch()
        projects[index] = updated
        saveAll()
        CloudSyncService.shared.queueSave(updated)
    }

    func deleteProject(_ project: Project) {
        isLoading = true
        cascadeDeleteProject(id: project.id, queueCloudDeletes: true)
        isLoading = false
        saveAll()
        CloudSyncService.shared.queueDelete(recordType: .project, id: project.id)
    }

    @discardableResult
    func duplicateProject(_ project: Project) -> Project {
        let baseName = project.name
        let existingNames = Set(projects.map(\.name))
        var number = 2
        var candidateName = "\(baseName) (\(number))"
        while existingNames.contains(candidateName) {
            number += 1
            candidateName = "\(baseName) (\(number))"
        }

        let newProject = Project(
            name: candidateName, emoji: project.emoji,
            iconURL: project.iconURL, color: project.color, folderId: project.folderId
        )

        let projectRequestFolders = requestFolders.filter { $0.projectId == project.id && $0.deletedAt == nil }
        var folderIdMap: [UUID: UUID] = [:]
        var newFolders: [RequestFolder] = []
        var newRequests: [Request] = []

        isLoading = true
        for folder in projectRequestFolders {
            let newFolder = RequestFolder(projectId: newProject.id, name: folder.name, color: folder.color)
            folderIdMap[folder.id] = newFolder.id
            requestFolders.append(newFolder)
            newFolders.append(newFolder)
        }

        let projectRequests = requests.filter { $0.projectId == project.id && $0.deletedAt == nil }
        for request in projectRequests {
            var newRequest = request
            newRequest.id = UUID()
            newRequest.projectId = newProject.id
            newRequest.createdAt = Date()
            newRequest.touch()
            if let oldFolderId = newRequest.folderId, let newFolderId = folderIdMap[oldFolderId] {
                newRequest.folderId = newFolderId
            }
            requests.append(newRequest)
            newRequests.append(newRequest)
        }

        projects.append(newProject)
        isLoading = false
        saveAll()

        CloudSyncService.shared.queueSave(newProject)
        for folder in newFolders { CloudSyncService.shared.queueSave(folder) }
        for request in newRequests { CloudSyncService.shared.queueSave(request) }

        if project.iconURL != nil {
            ProjectIconService.shared.downloadMissingIcons(for: [newProject])
        }

        return newProject
    }

    func projects(in folder: ProjectFolder?) -> [Project] {
        projects.filter { $0.deletedAt == nil && $0.folderId == folder?.id }
    }

    var sortedFolders: [ProjectFolder] {
        folders
            .filter { $0.deletedAt == nil }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var hasActiveProjects: Bool {
        projects.contains { $0.deletedAt == nil }
    }

    var unfolderedProjects: [Project] {
        let folderIds = Set(folders.map(\.id))
        return projects.filter { project in
            guard project.deletedAt == nil else { return false }
            guard let folderId = project.folderId else { return true }
            return !folderIds.contains(folderId)
        }
    }
}
