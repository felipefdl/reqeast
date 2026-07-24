//
//  MCPExportServiceTests.swift
//  ReqeastTests
//

#if os(macOS)

import Foundation
import Testing
@testable import Reqeast

@Suite("MCPExportService", .serialized)
struct MCPExportServiceTests {
    @MainActor
    private func withIsolatedMCPDirectory(
        _ body: (URL) async throws -> Void
    ) async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcp-export-tests-\(UUID().uuidString)", isDirectory: true)
        MCPExportService.mcpDirectoryOverride = tempDir
        defer {
            MCPExportService.mcpDirectoryOverride = nil
            try? FileManager.default.removeItem(at: tempDir)
        }
        try await body(tempDir)
    }

    private func projectsExportData(at url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    @Test @MainActor func stripsSensitiveHeadersAndParamsFromExport() async throws {
        try await withIsolatedMCPDirectory { directory in
            let project = Project(name: "MCP Redaction Test")
            var request = Request(projectId: project.id, name: "Auth Test", type: .http)
            request.httpData = HttpRequestData(
                method: .get,
                url: "https://api.example.com/data",
                params: [
                    KeyValueEntry(key: "q", value: "search", enabled: true),
                    KeyValueEntry(key: "api_key", value: "secret-key", enabled: true),
                    KeyValueEntry(key: "API_KEY", value: "also-secret", enabled: true),
                ],
                headers: [
                    KeyValueEntry(key: "Content-Type", value: "application/json", enabled: true),
                    KeyValueEntry(key: "Authorization", value: "Bearer token123", enabled: true),
                    KeyValueEntry(key: "Cookie", value: "session=abc", enabled: true),
                    KeyValueEntry(key: "X-Api-Key", value: "key456", enabled: true),
                    KeyValueEntry(key: "x-api-key", value: "key789", enabled: true),
                ]
            )

            let store = ProjectStore.mock(projects: [project], requests: [request])
            MCPExportService.shared.flushProjectsExportForTesting(store: store)

            let url = directory.appendingPathComponent("projects.json")
            let data = try projectsExportData(at: url)
            let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            let requests = json["requests"] as! [[String: Any]]
            #expect(requests.count == 1)

            let httpData = requests[0]["httpData"] as! [String: Any]
            let headers = httpData["headers"] as! [[String: Any]]
            let params = httpData["params"] as! [[String: Any]]

            let headerKeys = Set(headers.compactMap { ($0["key"] as? String)?.lowercased() })
            let paramKeys = Set(params.compactMap { ($0["key"] as? String)?.lowercased() })

            #expect(headerKeys.contains("content-type"))
            #expect(!headerKeys.contains("authorization"))
            #expect(!headerKeys.contains("cookie"))
            #expect(!headerKeys.contains("x-api-key"))

            #expect(paramKeys.contains("q"))
            #expect(!paramKeys.contains("api_key"))
        }
    }

    @Test @MainActor func stripsCredentialsFromImportedSpecRequests() async throws {
        try await withIsolatedMCPDirectory { directory in
            let project = Project(name: "Imported Auth")
            var request = Request(projectId: project.id, name: "API key protected", type: .http)
            request.httpData = HttpRequestData(
                method: .get,
                url: "{{base_url}}/api-key",
                params: [
                    KeyValueEntry(key: "api_key", value: "live-query-key", enabled: true),
                ],
                headers: [
                    KeyValueEntry(key: "X-Api-Key", value: "live-header-key", enabled: true),
                    KeyValueEntry(key: "Authorization", value: "Bearer imported-token", enabled: true),
                ],
                authType: .apiKey,
                authApiKeyName: "X-API-Key",
                authApiKeyValue: "{{api_key}}",
                authApiKeyLocation: "header"
            )

            let store = ProjectStore.mock(projects: [project], requests: [request])
            MCPExportService.shared.flushProjectsExportForTesting(store: store)

            let url = directory.appendingPathComponent("projects.json")
            let data = try projectsExportData(at: url)
            let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            let requests = json["requests"] as! [[String: Any]]
            let httpData = requests[0]["httpData"] as! [String: Any]
            let headers = httpData["headers"] as! [[String: Any]]
            let params = httpData["params"] as! [[String: Any]]

            let headerKeys = Set(headers.compactMap { ($0["key"] as? String)?.lowercased() })
            let paramKeys = Set(params.compactMap { ($0["key"] as? String)?.lowercased() })

            #expect(!headerKeys.contains("authorization"))
            #expect(!headerKeys.contains("x-api-key"))
            #expect(!paramKeys.contains("api_key"))
            #expect(httpData["authType"] as? String == "apiKey")
        }
    }

    @Test @MainActor func preservesNonSensitiveExportValues() async throws {
        try await withIsolatedMCPDirectory { directory in
            let project = Project(name: "MCP Preserve Test")
            var request = Request(projectId: project.id, name: "Safe Headers", type: .http)
            request.httpData = HttpRequestData(
                method: .post,
                url: "https://api.example.com/items",
                params: [KeyValueEntry(key: "page", value: "2", enabled: true)],
                headers: [KeyValueEntry(key: "Accept", value: "application/json", enabled: true)]
            )

            let store = ProjectStore.mock(projects: [project], requests: [request])
            MCPExportService.shared.flushProjectsExportForTesting(store: store)

            let url = directory.appendingPathComponent("projects.json")
            let data = try projectsExportData(at: url)
            let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            let requests = json["requests"] as! [[String: Any]]
            let httpData = requests[0]["httpData"] as! [String: Any]
            let headers = httpData["headers"] as! [[String: Any]]
            let params = httpData["params"] as! [[String: Any]]

            #expect(headers.contains { ($0["key"] as? String) == "Accept" && ($0["value"] as? String) == "application/json" })
            #expect(params.contains { ($0["key"] as? String) == "page" && ($0["value"] as? String) == "2" })
        }
    }

}

#endif