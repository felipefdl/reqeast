//
//  ImportExportServiceTests.swift
//  ReqeastTests
//

import Foundation
import Testing
@testable import Reqeast

@Suite("ImportExportService")
struct ImportExportServiceTests {
    private let projectId = UUID()

    private func sampleProject() -> Project {
        Project(name: "Test API", emoji: "🚀", color: .blue)
    }

    private func sampleRequests(projectId: UUID, folderId: UUID? = nil) -> [Request] {
        var httpReq = Request(projectId: projectId, name: "Get Users", type: .http, folderId: folderId)
        httpReq.httpData = HttpRequestData(method: .get, url: "https://api.example.com/users")

        var tcpReq = Request(projectId: projectId, name: "TCP Echo", type: .tcp)
        tcpReq.tcpData = TcpRequestData(
            host: "echo.example.com", port: 9000,
            messageHistory: [MessageHistoryEntry(text: "hello", encoding: .utf8)]
        )

        var udpReq = Request(projectId: projectId, name: "UDP Ping", type: .udp)
        udpReq.udpData = UdpRequestData(
            host: "ping.example.com", port: 5000,
            messageHistory: [MessageHistoryEntry(text: "ping", encoding: .utf8)]
        )

        var wsReq = Request(projectId: projectId, name: "WS Feed", type: .webSocket)
        wsReq.webSocketData = WebSocketRequestData(
            url: "wss://feed.example.com",
            messageHistory: [MessageHistoryEntry(text: "subscribe", encoding: .utf8)]
        )

        return [httpReq, tcpReq, udpReq, wsReq]
    }

    private func sampleEnvironments(projectId: UUID) -> [ApiEnvironment] {
        [ApiEnvironment(
            projectId: projectId,
            name: "Dev",
            variables: [
                EnvironmentVariable(key: "host", value: "localhost"),
                EnvironmentVariable(key: "apiKey", value: "secret-key-123", isSecret: true),
            ],
            isActive: true
        )]
    }

    // MARK: - Round-Trip

    @Test func roundTripPreservesData() throws {
        let project = sampleProject()
        let requests = sampleRequests(projectId: project.id)
        let environments = sampleEnvironments(projectId: project.id)

        let data = try ImportExportService.prepareExportData(
            project: project, requests: requests, requestFolders: [],
            environments: environments, includeCredentials: false, includeSecrets: true
        )

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(ExportDocument.self, from: data)

        #expect(document.version == ExportDocument.currentVersion)
        #expect(document.project.name == "Test API")
        #expect(document.project.emoji == "🚀")
        #expect(document.requests.count == 4)
        #expect(document.environments.count == 1)
        #expect(document.environments[0].environment.variables.count == 2)
    }

    // MARK: - Message History Stripped

    @Test func messageHistoryStrippedOnExport() throws {
        let project = sampleProject()
        let requests = sampleRequests(projectId: project.id)

        let data = try ImportExportService.prepareExportData(
            project: project, requests: requests, requestFolders: [],
            environments: [], includeCredentials: false, includeSecrets: false
        )

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(ExportDocument.self, from: data)

        for exported in document.requests {
            if let tcp = exported.request.tcpData {
                #expect(tcp.messageHistory.isEmpty)
            }
            if let udp = exported.request.udpData {
                #expect(udp.messageHistory.isEmpty)
            }
            if let ws = exported.request.webSocketData {
                #expect(ws.messageHistory.isEmpty)
            }
        }
    }

    // MARK: - Credentials Exclusion

    @Test func credentialsExcludedWhenToggleOff() throws {
        let project = sampleProject()
        let requests = sampleRequests(projectId: project.id)

        let data = try ImportExportService.prepareExportData(
            project: project, requests: requests, requestFolders: [],
            environments: [], includeCredentials: false, includeSecrets: false
        )

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(ExportDocument.self, from: data)

        for exported in document.requests {
            #expect(exported.credentials == nil)
        }
    }

    // MARK: - Secret Environment Variables

    @Test func secretValuesStrippedWhenExcluded() throws {
        let project = sampleProject()
        let environments = sampleEnvironments(projectId: project.id)

        let data = try ImportExportService.prepareExportData(
            project: project, requests: [], requestFolders: [],
            environments: environments, includeCredentials: false, includeSecrets: false
        )

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(ExportDocument.self, from: data)

        let exported = document.environments[0]
        #expect(!exported.includesSecrets)

        let secretVar = exported.environment.variables.first { $0.isSecret }
        #expect(secretVar?.value == "")

        let normalVar = exported.environment.variables.first { !$0.isSecret }
        #expect(normalVar?.value == "localhost")
    }

    @Test func secretValuesIncludedWhenToggleOn() throws {
        let project = sampleProject()
        let environments = sampleEnvironments(projectId: project.id)

        let data = try ImportExportService.prepareExportData(
            project: project, requests: [], requestFolders: [],
            environments: environments, includeCredentials: false, includeSecrets: true
        )

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(ExportDocument.self, from: data)

        let exported = document.environments[0]
        #expect(exported.includesSecrets)
        let secretVar = exported.environment.variables.first { $0.isSecret }
        #expect(secretVar?.value == "secret-key-123")
    }

    // MARK: - UUID Regeneration

    @Test @MainActor func importedIdsAllDifferFromOriginals() throws {
        let project = sampleProject()
        let folder = RequestFolder(projectId: project.id, name: "Users", color: .blue)
        let requests = sampleRequests(projectId: project.id, folderId: folder.id)
        let environments = sampleEnvironments(projectId: project.id)

        let data = try ImportExportService.prepareExportData(
            project: project, requests: requests, requestFolders: [folder],
            environments: environments, includeCredentials: false, includeSecrets: true
        )

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(ExportDocument.self, from: data)

        let store = ProjectStore.mock()
        let imported = ImportExportService.performImport(
            document: document, store: store,
            importCredentials: false, importSecrets: true, folderStrategy: .createNew
        )

        #expect(imported.id != project.id)

        let importedRequests = store.requests(for: imported.id)
        let originalIds = Set(requests.map(\.id))
        for req in importedRequests {
            #expect(!originalIds.contains(req.id))
            #expect(req.projectId == imported.id)
        }

        let importedFolders = store.requestFolders(for: imported.id)
        #expect(importedFolders.count == 1)
        #expect(importedFolders[0].id != folder.id)

        let importedEnvs = store.environments(for: imported.id)
        let originalEnvIds = Set(environments.map(\.id))
        for env in importedEnvs {
            #expect(!originalEnvIds.contains(env.id))
            #expect(env.projectId == imported.id)
        }
    }

    // MARK: - Relationship Integrity

    @Test @MainActor func folderRelationshipsRemappedCorrectly() throws {
        let project = sampleProject()
        let folder1 = RequestFolder(projectId: project.id, name: "Auth", color: .red)
        let folder2 = RequestFolder(projectId: project.id, name: "Users", color: .blue)

        var req1 = Request(projectId: project.id, name: "Login", type: .http, folderId: folder1.id)
        req1.httpData = HttpRequestData(method: .post, url: "https://api.example.com/login")

        var req2 = Request(projectId: project.id, name: "List Users", type: .http, folderId: folder2.id)
        req2.httpData = HttpRequestData(method: .get, url: "https://api.example.com/users")

        var req3 = Request(projectId: project.id, name: "Health", type: .http)
        req3.httpData = HttpRequestData(method: .get, url: "https://api.example.com/health")

        let data = try ImportExportService.prepareExportData(
            project: project, requests: [req1, req2, req3],
            requestFolders: [folder1, folder2], environments: [],
            includeCredentials: false, includeSecrets: false
        )

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(ExportDocument.self, from: data)

        let store = ProjectStore.mock()
        let imported = ImportExportService.performImport(
            document: document, store: store,
            importCredentials: false, importSecrets: false, folderStrategy: .createNew
        )

        let importedFolders = store.requestFolders(for: imported.id)
        let importedRequests = store.requests(for: imported.id)

        // Requests in folders should point to new folder IDs
        let folderIds = Set(importedFolders.map(\.id))
        let folderedRequests = importedRequests.filter { $0.folderId != nil }
        for req in folderedRequests {
            #expect(folderIds.contains(req.folderId!))
        }

        // Unfolddered request should have nil folderId
        let unfolderedRequests = importedRequests.filter { $0.folderId == nil }
        #expect(unfolderedRequests.count == 1)
        #expect(unfolderedRequests[0].name == "Health")
    }

    // MARK: - Folder Strategies

    // MARK: - Export All Bundle

    @Test func exportAllBundleRoundTrip() throws {
        let project1 = Project(name: "API One", emoji: "1", color: .blue)
        let project2 = Project(name: "API Two", emoji: "2", color: .red)

        var req1 = Request(projectId: project1.id, name: "Get Users", type: .http)
        req1.httpData = HttpRequestData(method: .get, url: "https://one.example.com/users")

        var req2 = Request(projectId: project2.id, name: "Post Items", type: .http)
        req2.httpData = HttpRequestData(method: .post, url: "https://two.example.com/items")

        let env1 = ApiEnvironment(projectId: project1.id, name: "Dev", variables: [], isActive: true)

        let store = ProjectStore.mock(
            projects: [project1, project2],
            requests: [req1, req2]
        )
        store.environments = [env1]

        let data = try ImportExportService.prepareExportAllData(
            store: store, includeCredentials: false, includeSecrets: false
        )

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let bundle = try decoder.decode(ExportBundle.self, from: data)

        #expect(bundle.version == ExportBundle.currentVersion)
        #expect(bundle.projects.count == 2)
        #expect(bundle.projects[0].project.name == "API One")
        #expect(bundle.projects[0].requests.count == 1)
        #expect(bundle.projects[1].project.name == "API Two")
        #expect(bundle.projects[1].requests.count == 1)
        #expect(bundle.projects[0].environments.count == 1)
    }

    @Test @MainActor func bundleImportCreatesAllProjectsWithFreshIds() throws {
        let project1 = Project(name: "API One", emoji: "1", color: .blue)
        let project2 = Project(name: "API Two", emoji: "2", color: .red)

        var req1 = Request(projectId: project1.id, name: "Get Users", type: .http)
        req1.httpData = HttpRequestData(method: .get, url: "https://one.example.com/users")

        var req2 = Request(projectId: project2.id, name: "Post Items", type: .http)
        req2.httpData = HttpRequestData(method: .post, url: "https://two.example.com/items")

        let sourceStore = ProjectStore.mock(
            projects: [project1, project2],
            requests: [req1, req2]
        )

        let data = try ImportExportService.prepareExportAllData(
            store: sourceStore, includeCredentials: false, includeSecrets: false
        )

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let bundle = try decoder.decode(ExportBundle.self, from: data)

        let targetStore = ProjectStore.mock()
        let imported = ImportExportService.performBundleImport(
            bundle: bundle, store: targetStore,
            importCredentials: false, importSecrets: false, folderStrategy: .createNew
        )

        #expect(imported.count == 2)
        #expect(targetStore.projects.count == 2)

        // All IDs should be fresh
        #expect(imported[0].id != project1.id)
        #expect(imported[1].id != project2.id)

        // Requests should be remapped
        let importedReqs1 = targetStore.requests(for: imported[0].id)
        let importedReqs2 = targetStore.requests(for: imported[1].id)
        #expect(importedReqs1.count == 1)
        #expect(importedReqs2.count == 1)
        #expect(importedReqs1[0].id != req1.id)
        #expect(importedReqs2[0].id != req2.id)
    }

    // MARK: - Single Import Clears Project FolderId

    @Test @MainActor func singleImportClearsProjectFolderId() throws {
        let folder = ProjectFolder(name: "APIs", color: .blue)
        var project = sampleProject()
        project.folderId = folder.id

        let data = try ImportExportService.prepareExportData(
            project: project, requests: [], requestFolders: [],
            environments: [], includeCredentials: false, includeSecrets: false
        )

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(ExportDocument.self, from: data)

        // The exported document preserves folderId
        #expect(document.project.folderId == folder.id)

        let store = ProjectStore.mock()
        let imported = ImportExportService.performImport(
            document: document, store: store,
            importCredentials: false, importSecrets: false, folderStrategy: .createNew
        )

        // But imported project should have nil folderId
        #expect(imported.folderId == nil)
    }

    // MARK: - Bundle Export Includes Project Folders

    @Test func bundleExportIncludesProjectFolders() throws {
        let folder = ProjectFolder(name: "APIs", color: .blue)
        var project1 = Project(name: "API One", emoji: "1", color: .blue)
        project1.folderId = folder.id
        let project2 = Project(name: "API Two", emoji: "2", color: .red)

        let store = ProjectStore.mock(
            projects: [project1, project2],
            folders: [folder]
        )

        let data = try ImportExportService.prepareExportAllData(
            store: store, includeCredentials: false, includeSecrets: false
        )

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let bundle = try decoder.decode(ExportBundle.self, from: data)

        #expect(bundle.projectFolders.count == 1)
        #expect(bundle.projectFolders[0].name == "APIs")
        #expect(bundle.projectFolders[0].id == folder.id)
    }

    // MARK: - Bundle Import Remaps Project Folders

    @Test @MainActor func bundleImportRemapsProjectFolders() throws {
        let folder = ProjectFolder(name: "APIs", color: .blue)
        var project1 = Project(name: "API One", emoji: "1", color: .blue)
        project1.folderId = folder.id
        var project2 = Project(name: "API Two", emoji: "2", color: .red)
        project2.folderId = folder.id

        var req1 = Request(projectId: project1.id, name: "Get Users", type: .http)
        req1.httpData = HttpRequestData(method: .get, url: "https://one.example.com/users")

        let sourceStore = ProjectStore.mock(
            projects: [project1, project2],
            folders: [folder],
            requests: [req1]
        )

        let data = try ImportExportService.prepareExportAllData(
            store: sourceStore, includeCredentials: false, includeSecrets: false
        )

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let bundle = try decoder.decode(ExportBundle.self, from: data)

        let targetStore = ProjectStore.mock()
        let imported = ImportExportService.performBundleImport(
            bundle: bundle, store: targetStore,
            importCredentials: false, importSecrets: false, folderStrategy: .createNew
        )

        // Project folders should be recreated with fresh IDs
        #expect(targetStore.folders.count == 1)
        #expect(targetStore.folders[0].name == "APIs")
        #expect(targetStore.folders[0].id != folder.id)

        // Both imported projects should point to the new folder
        let newFolderId = targetStore.folders[0].id
        #expect(imported[0].folderId == newFolderId)
        #expect(imported[1].folderId == newFolderId)

        // Verify projects in store are also updated
        for project in targetStore.projects {
            #expect(project.folderId == newFolderId)
        }
    }

    // MARK: - Orphaned FolderId Handling

    @Test func orphanedFolderIdAppearsInUnfolderedProjects() {
        var orphanedProject = Project(name: "Orphan", emoji: "?", color: .gray)
        orphanedProject.folderId = UUID() // points to non-existent folder
        let normalProject = Project(name: "Normal", emoji: "!", color: .blue)

        let store = ProjectStore.mock(projects: [orphanedProject, normalProject])

        let unfoldered = store.unfolderedProjects
        #expect(unfoldered.count == 2)
        #expect(unfoldered.contains { $0.name == "Orphan" })
        #expect(unfoldered.contains { $0.name == "Normal" })
    }

    @Test func projectWithValidFolderIdNotInUnfolderedProjects() {
        let folder = ProjectFolder(name: "APIs", color: .blue)
        var folderedProject = Project(name: "Foldered", emoji: "F", color: .blue)
        folderedProject.folderId = folder.id
        let normalProject = Project(name: "Normal", emoji: "N", color: .gray)

        let store = ProjectStore.mock(projects: [folderedProject, normalProject], folders: [folder])

        let unfoldered = store.unfolderedProjects
        #expect(unfoldered.count == 1)
        #expect(unfoldered[0].name == "Normal")
    }

    // MARK: - Backward Compatibility

    @Test func bundleWithoutProjectFoldersFieldDecodesSuccessfully() throws {
        let json = """
        {
            "version": 1,
            "exportedAt": "2025-01-01T00:00:00Z",
            "appVersion": "1.0",
            "projects": []
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let bundle = try decoder.decode(ExportBundle.self, from: Data(json.utf8))

        #expect(bundle.projectFolders.isEmpty)
        #expect(bundle.projects.isEmpty)
    }

    // MARK: - Folder Strategies

    @Test @MainActor func noFoldersStrategyFlattensRequests() throws {
        let project = sampleProject()
        let folder = RequestFolder(projectId: project.id, name: "Group", color: .green)
        var req = Request(projectId: project.id, name: "Test", type: .http, folderId: folder.id)
        req.httpData = HttpRequestData()

        let data = try ImportExportService.prepareExportData(
            project: project, requests: [req], requestFolders: [folder],
            environments: [], includeCredentials: false, includeSecrets: false
        )

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(ExportDocument.self, from: data)

        let store = ProjectStore.mock()
        let imported = ImportExportService.performImport(
            document: document, store: store,
            importCredentials: false, importSecrets: false, folderStrategy: .noFolders
        )

        let importedFolders = store.requestFolders(for: imported.id)
        let importedRequests = store.requests(for: imported.id)

        #expect(importedFolders.isEmpty)
        #expect(importedRequests.count == 1)
        #expect(importedRequests[0].folderId == nil)
    }
}
