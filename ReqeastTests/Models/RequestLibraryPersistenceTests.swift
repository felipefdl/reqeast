//
//  RequestLibraryPersistenceTests.swift
//  ReqeastTests
//

import Foundation
import Testing
@testable import Reqeast

@Suite("RequestLibraryPersistence", .serialized)
struct RequestLibraryPersistenceTests {
    @Test @MainActor func roundTripPreservesRequestsWithoutSnapshotPayloadOnDisk() throws {
        let tempDir = try makeTempLibraryDirectory()
        defer { cleanup(tempDir) }

        let projectId = UUID()
        let request = Request(projectId: projectId, name: "GET /users", type: .http)
        var requestWithPayload = request
        requestWithPayload.specSnapshotPayload = Data("gzip-placeholder".utf8)
        requestWithPayload.httpData = HttpRequestData(method: .get, url: "{{base_url}}/users")

        try RequestLibraryPersistence.save([requestWithPayload])
        let loaded = try #require(RequestLibraryPersistence.load())

        #expect(loaded.count == 1)
        #expect(loaded[0].name == "GET /users")
        #expect(loaded[0].httpData?.url == "{{base_url}}/users")

        let fileData = try Data(contentsOf: tempDir.appendingPathComponent(RequestLibraryPersistence.requestsFileName))
        let decoded = try JSONDecoder().decode([Request].self, from: fileData)
        #expect(decoded[0].specSnapshotPayload == nil)
    }

    @Test @MainActor func loadRehydratesSnapshotPayloadFromDisk() throws {
        let tempDir = try makeTempLibraryDirectory()
        defer { cleanup(tempDir) }

        let projectId = UUID()
        let requestId = UUID()
        let httpData = HttpRequestData(method: .post, url: "{{base_url}}/login")
        let snapshot = SpecSnapshotService.makeSnapshot(from: httpData)
        try SpecSnapshotService.writeSnapshotToDisk(snapshot, projectId: projectId, requestId: requestId)

        var request = Request(id: requestId, projectId: projectId, name: "Login", type: .http)
        request.httpData = httpData
        request.specFieldFingerprint = SpecSnapshotService.fingerprint(for: snapshot)

        try RequestLibraryPersistence.save([request])
        let loaded = try #require(RequestLibraryPersistence.load())

        #expect(loaded[0].specSnapshotPayload != nil)
        let restored = try SpecSnapshotService.decodePayload(try #require(loaded[0].specSnapshotPayload))
        #expect(restored.method == snapshot.method)
        #expect(restored.urlTemplate == snapshot.urlTemplate)
    }

    @Test @MainActor func saveHandlesLargeLibrary() throws {
        let tempDir = try makeTempLibraryDirectory()
        defer { cleanup(tempDir) }

        let projectId = UUID()
        var requests: [Request] = []
        requests.reserveCapacity(500)
        for index in 0..<500 {
            var request = Request(projectId: projectId, name: "Operation \(index)", type: .http)
            request.httpData = HttpRequestData(
                method: .get,
                url: "{{base_url}}/resource/\(index)",
                bodyContent: String(repeating: "x", count: 2_000)
            )
            requests.append(request)
        }

        try RequestLibraryPersistence.save(requests)
        let loaded = try #require(RequestLibraryPersistence.load())
        #expect(loaded.count == 500)
        #expect(loaded.last?.name == "Operation 499")
    }

    @Test @MainActor func deleteAllRemovesRequestsFile() throws {
        let tempDir = try makeTempLibraryDirectory()
        defer { cleanup(tempDir) }

        try RequestLibraryPersistence.save([Request(projectId: UUID(), name: "R")])
        RequestLibraryPersistence.deleteAll()

        #expect(RequestLibraryPersistence.load() == nil)
    }

    // MARK: - Helpers

    @MainActor
    private func makeTempLibraryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("reqeast-library-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        RequestLibraryPersistence.directoryOverride = url
        return url
    }

    @MainActor
    private func cleanup(_ directory: URL) {
        RequestLibraryPersistence.directoryOverride = nil
        try? FileManager.default.removeItem(at: directory)
    }
}