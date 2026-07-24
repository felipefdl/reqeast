//
//  ImportExportService.swift
//  Reqeast
//

import Foundation

enum ImportFolderStrategy: String, CaseIterable {
    case mergeByName
    case createNew
    case noFolders

    var localizedName: String {
        switch self {
        case .mergeByName: return String(localized: "Merge by Name")
        case .createNew:   return String(localized: "Create New Folders")
        case .noFolders:   return String(localized: "No Folders")
        }
    }
}

enum ImportExportService {

    // MARK: - Export

    static func prepareExportData(
        project: Project,
        requests: [Request],
        requestFolders: [RequestFolder],
        environments: [ApiEnvironment],
        includeCredentials: Bool,
        includeSecrets: Bool
    ) throws -> Data {
        let strippedRequests = requests.map { stripMessageHistory($0) }

        let exportedRequests: [ExportedRequest] = strippedRequests.map { request in
            let credentials: RequestCredentials? = if includeCredentials {
                try? KeychainService.shared.loadCredentials(for: request.id)
            } else {
                nil
            }
            return ExportedRequest(request: request, credentials: credentials)
        }

        let exportedEnvironments: [ExportedEnvironment] = environments.map { env in
            if includeSecrets {
                return ExportedEnvironment(environment: env, includesSecrets: true)
            }
            var sanitized = env
            sanitized.variables = env.variables.map { variable in
                guard variable.isSecret else { return variable }
                var cleared = variable
                cleared.value = ""
                return cleared
            }
            return ExportedEnvironment(environment: sanitized, includesSecrets: false)
        }

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

        let document = ExportDocument(
            version: ExportDocument.currentVersion,
            exportedAt: Date(),
            appVersion: appVersion,
            project: project,
            requests: exportedRequests,
            requestFolders: requestFolders,
            environments: exportedEnvironments
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(document)
    }

    // MARK: - Export All

    static func prepareExportAllData(
        store: ProjectStore,
        includeCredentials: Bool,
        includeSecrets: Bool
    ) throws -> Data {
        let documents: [ExportDocument] = try store.projects.filter({ $0.deletedAt == nil }).map { project in
            let data = try prepareExportData(
                project: project,
                requests: store.requests(for: project.id),
                requestFolders: store.requestFolders(for: project.id),
                environments: store.environments(for: project.id),
                includeCredentials: includeCredentials,
                includeSecrets: includeSecrets
            )
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(ExportDocument.self, from: data)
        }

        let exportedProjectIds = Set(store.projects.filter { $0.deletedAt == nil }.map(\.id))
        let projectFolders = store.folders.filter { folder in
            folder.deletedAt == nil && store.projects.contains { $0.folderId == folder.id && exportedProjectIds.contains($0.id) }
        }

        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let bundle = ExportBundle(
            version: ExportBundle.currentVersion,
            exportedAt: Date(),
            appVersion: appVersion,
            projects: documents,
            projectFolders: projectFolders
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(bundle)
    }

    // MARK: - Import Parsing

    enum ParsedImport {
        case single(ImportResult)
        case bundle(ImportBundleResult)
    }

    static func parseImportFile(at url: URL) -> ParsedImport? {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else { return nil }
        let fileName = url.lastPathComponent

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let bundle = try? decoder.decode(ExportBundle.self, from: data) {
            return .bundle(ImportBundleResult(bundle: bundle, fileName: fileName))
        }

        if let document = try? decoder.decode(ExportDocument.self, from: data) {
            return .single(ImportResult(document: document, fileName: fileName))
        }

        return nil
    }

    // MARK: - Import Execution

    @MainActor
    static func performImport(
        document: ExportDocument,
        store: ProjectStore,
        importCredentials: Bool,
        importSecrets: Bool,
        folderStrategy: ImportFolderStrategy
    ) -> Project {
        let newProjectId = UUID()
        let now = Date()

        // Build folder ID mapping
        var folderIdMap: [UUID: UUID] = [:]
        var newFolders: [RequestFolder] = []

        switch folderStrategy {
        case .mergeByName:
            let existingFolders = store.requestFolders
            for folder in document.requestFolders {
                if let existing = existingFolders.first(where: {
                    $0.projectId == newProjectId && $0.name == folder.name
                }) {
                    folderIdMap[folder.id] = existing.id
                } else {
                    let newFolder = RequestFolder(
                        projectId: newProjectId, name: folder.name, color: folder.color
                    )
                    folderIdMap[folder.id] = newFolder.id
                    newFolders.append(newFolder)
                }
            }
        case .createNew:
            for folder in document.requestFolders {
                let newFolder = RequestFolder(
                    projectId: newProjectId, name: folder.name, color: folder.color
                )
                folderIdMap[folder.id] = newFolder.id
                newFolders.append(newFolder)
            }
        case .noFolders:
            break
        }

        // Remap requests
        var newRequests: [Request] = []
        for exported in document.requests {
            var request = exported.request
            let oldRequestId = request.id
            request.id = UUID()
            request.projectId = newProjectId
            request.createdAt = now
            request.updatedAt = now

            if folderStrategy == .noFolders {
                request.folderId = nil
            } else if let oldFolderId = request.folderId, let newFolderId = folderIdMap[oldFolderId] {
                request.folderId = newFolderId
            } else {
                request.folderId = nil
            }

            newRequests.append(request)

            // Import credentials
            if importCredentials, let credentials = exported.credentials {
                try? KeychainService.shared.saveCredentials(credentials, for: request.id)
            }

            _ = oldRequestId // suppress unused warning
        }

        // Remap environments
        var newEnvironments: [ApiEnvironment] = []
        for exported in document.environments {
            var env = exported.environment
            env.id = UUID()
            env.projectId = newProjectId

            if !importSecrets && exported.includesSecrets {
                env.variables = env.variables.map { variable in
                    guard variable.isSecret else { return variable }
                    var cleared = variable
                    cleared.value = ""
                    return cleared
                }
            }

            newEnvironments.append(env)
        }

        // Build the new project
        var newProject = document.project
        newProject.id = newProjectId
        newProject.folderId = nil
        newProject.createdAt = now
        newProject.updatedAt = now

        // Add everything to the store
        store.addProject(newProject)
        for folder in newFolders {
            store.addRequestFolder(folder)
        }
        for request in newRequests {
            store.addRequest(request)
        }
        for env in newEnvironments {
            store.environments.append(env)
        }

        if newProject.iconURL != nil {
            ProjectIconService.shared.downloadMissingIcons(for: [newProject])
        }

        return newProject
    }

    // MARK: - Bundle Import

    @MainActor
    static func performBundleImport(
        bundle: ExportBundle,
        store: ProjectStore,
        importCredentials: Bool,
        importSecrets: Bool,
        folderStrategy: ImportFolderStrategy
    ) -> [Project] {
        // Recreate project folders with fresh IDs
        var projectFolderIdMap: [UUID: UUID] = [:]
        for folder in bundle.projectFolders {
            let newFolder = ProjectFolder(name: folder.name, color: folder.color)
            projectFolderIdMap[folder.id] = newFolder.id
            store.addFolder(newFolder)
        }

        // Import each project document (performImport clears folderId)
        var imported = bundle.projects.map { document in
            performImport(
                document: document,
                store: store,
                importCredentials: importCredentials,
                importSecrets: importSecrets,
                folderStrategy: folderStrategy
            )
        }

        // Remap project folderId using the original document values
        for (index, document) in bundle.projects.enumerated() {
            if let oldFolderId = document.project.folderId,
               let newFolderId = projectFolderIdMap[oldFolderId] {
                imported[index].folderId = newFolderId
                store.updateProject(imported[index])
            }
        }

        return imported
    }

    // MARK: - Helpers

    private static func stripMessageHistory(_ request: Request) -> Request {
        var stripped = request
        stripped.tcpData?.messageHistory = []
        stripped.udpData?.messageHistory = []
        stripped.webSocketData?.messageHistory = []
        return stripped
    }
}
