//
//  SpecExportServiceTests.swift
//  ReqeastTests
//

import Foundation
import Testing
@testable import Reqeast

@Suite("SpecExportService", .serialized)
struct SpecExportServiceTests {

    static let fixturesDirectory: URL = {
        if let srcRoot = ProcessInfo.processInfo.environment["SRCROOT"] {
            return URL(fileURLWithPath: srcRoot, isDirectory: true)
                .appendingPathComponent("ReqeastTests/Fixtures/SpecImport", isDirectory: true)
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/SpecImport", isDirectory: true)
    }()

    // MARK: - Export data

    @Test @MainActor func exportOpenApiFromImportedPetstore() async throws {
        let store = try await committedPetstoreStore()
        let project = try #require(store.projects.first)

        let data = try await SpecExportService.exportData(
            project: project,
            store: store,
            kind: .openapi,
            options: SpecExportOptions.default
        )

        let yaml = try #require(String(data: data, encoding: .utf8))
        #expect(yaml.contains("openapi: 3.1.0"))
        #expect(yaml.contains("paths:"))

        let reparsed = try parseSpec(
            bytes: data,
            sourceHint: .yaml,
            bundleEntryPath: nil,
            options: SpecParseOptions(enableSchemaSynthesis: false)
        )
        #expect(reparsed.project.operations.count == 4)
    }

    @Test @MainActor func exportPostmanFromImportedPetstore() async throws {
        let store = try await committedPetstoreStore()
        let project = try #require(store.projects.first)

        let data = try await SpecExportService.exportData(
            project: project,
            store: store,
            kind: .postman,
            options: SpecExportOptions.default
        )

        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let info = json["info"] as! [String: Any]
        #expect(info["schema"] as? String == "https://schema.getpostman.com/json/collection/v2.1.0/collection.json")

        let reparsed = try parseSpec(
            bytes: data,
            sourceHint: .postman,
            bundleEntryPath: nil,
            options: SpecParseOptions(enableSchemaSynthesis: false)
        )
        #expect(reparsed.project.operations.count == 4)
    }

    @Test @MainActor func linkedProjectExportIsReadOnly() async throws {
        let store = try await committedPetstoreStore(linked: true)
        let project = try #require(store.projects.first)
        let revisionBefore = project.specLink?.specRevision
        let requestCountBefore = store.requests.count

        _ = try await SpecExportService.exportData(
            project: project,
            store: store,
            kind: .openapi,
            options: SpecExportOptions.default
        )

        let updatedProject = try #require(store.projects.first { $0.id == project.id })
        #expect(updatedProject.specLink?.specRevision == revisionBefore)
        #expect(store.requests.count == requestCountBefore)
    }

    @Test @MainActor func filtersSoftDeletedRequests() async throws {
        let project = Project(name: "Filter Test")
        var active = Request(projectId: project.id, name: "Active", type: .http)
        active.httpData = HttpRequestData(method: .get, url: "https://api.example.com/active")
        var deleted = Request(projectId: project.id, name: "Deleted", type: .http)
        deleted.httpData = HttpRequestData(method: .get, url: "https://api.example.com/deleted")
        deleted.deletedAt = Date()

        let store = ProjectStore.mock(projects: [project], requests: [active, deleted])
        let input = SpecExportMapper.buildInput(
            project: project,
            store: store,
            options: SpecExportOptions.default
        )

        #expect(input.operations.count == 1)
        #expect(input.operations[0].http.url.contains("active"))
    }

    @Test @MainActor func excludesStaleAndDeprecatedWhenOptionOff() async throws {
        let project = Project(name: "Stale Test")
        var normal = Request(projectId: project.id, name: "Normal", type: .http, sortOrder: 0)
        normal.httpData = HttpRequestData(method: .get, url: "https://api.example.com/normal")

        var stale = Request(projectId: project.id, name: "Stale", type: .http, sortOrder: 1)
        stale.httpData = HttpRequestData(method: .get, url: "https://api.example.com/stale")
        stale.isSpecStale = true

        var deprecated = Request(projectId: project.id, name: "[Deprecated] Old", type: .http, sortOrder: 2)
        deprecated.httpData = HttpRequestData(method: .get, url: "https://api.example.com/old")

        let store = ProjectStore.mock(projects: [project], requests: [normal, stale, deprecated])
        var options = SpecExportOptions.default
        options.includeDeprecatedAndStale = false

        let input = SpecExportMapper.buildInput(project: project, store: store, options: options)
        #expect(input.operations.count == 1)
        #expect(input.operations[0].name == "Normal")
    }

    @Test @MainActor func redactsLiveAuthValues() async throws {
        let project = Project(name: "Auth Redaction")
        var request = Request(projectId: project.id, name: "Secure", type: .http)
        request.httpData = HttpRequestData(
            method: .get,
            url: "https://api.example.com/secure",
            authType: .bearer,
            authToken: "live-secret-token"
        )

        let store = ProjectStore.mock(projects: [project], requests: [request])
        let input = SpecExportMapper.buildInput(
            project: project,
            store: store,
            options: SpecExportOptions.default
        )

        #expect(input.operations[0].http.authToken == "{{token}}")
    }

    @Test @MainActor func throwsWhenNoExportableOperations() async throws {
        let project = Project(name: "Empty")
        let store = ProjectStore.mock(projects: [project])

        await #expect(throws: SpecExportServiceError.noOperations) {
            _ = try await SpecExportService.exportData(
                project: project,
                store: store,
                kind: .openapi,
                options: SpecExportOptions.default
            )
        }
    }

    // MARK: - Delivery

    @Test @MainActor func writeExportToFile() async throws {
        let store = try await committedPetstoreStore()
        let project = try #require(store.projects.first)
        let data = try await SpecExportService.exportData(
            project: project,
            store: store,
            kind: .openapi,
            options: SpecExportOptions.default
        )

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("spec-export-\(UUID().uuidString).yaml")
        defer { try? FileManager.default.removeItem(at: url) }

        try SpecExportService.writeExport(data, to: .file(url))
        let written = try Data(contentsOf: url)
        #expect(written == data)
    }

    @Test func defaultFilenameSanitizesProjectName() {
        let project = Project(name: "My API / v2")
        let filename = SpecExportService.defaultFilename(
            for: project,
            kind: .openapi,
            options: SpecExportOptions.default
        )
        #expect(filename == "My-API---v2-openapi.yaml")
    }

    // MARK: - Helpers

    @MainActor
    private func committedPetstoreStore(linked: Bool = false) async throws -> ProjectStore {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("spec-export-tests-\(UUID().uuidString)", isDirectory: true)
        SpecImportService.specsRootDirectoryOverride = tempRoot
        defer {
            SpecImportService.specsRootDirectoryOverride = nil
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let bytes = try fixtureBytes(named: "petstore-3.1", preferJSON: false)
        var options = SpecImportOptions.default
        options.linkToSpec = linked ? .linked : .detached

        let preview = try await SpecImportService.preview(
            bytes: bytes,
            sourceHint: .yaml,
            source: .file,
            options: options
        )

        let store = ProjectStore.mock()
        try SpecImportService.commit(preview: preview, to: store)
        if linked {
            store.projects[0].specLink?.specRevision = 3
        }
        return store
    }

    private func fixtureBytes(named name: String, preferJSON: Bool) throws -> Data {
        let yamlURL = Self.fixturesDirectory.appendingPathComponent("\(name).input.yaml")
        let jsonURL = Self.fixturesDirectory.appendingPathComponent("\(name).input.json")

        let url: URL
        if preferJSON, FileManager.default.fileExists(atPath: jsonURL.path) {
            url = jsonURL
        } else if FileManager.default.fileExists(atPath: yamlURL.path) {
            url = yamlURL
        } else if FileManager.default.fileExists(atPath: jsonURL.path) {
            url = jsonURL
        } else {
            throw FixtureError.missingInput(name)
        }
        return try Data(contentsOf: url)
    }

    private enum FixtureError: Error {
        case missingInput(String)
    }
}