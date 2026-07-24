//
//  SpecSnapshotServiceTests.swift
//  ReqeastTests
//

import Foundation
import Testing
@testable import Reqeast

@Suite("SpecSnapshotService", .serialized)
struct SpecSnapshotServiceTests {

    // MARK: - Model round-trip

    @Test func specOperationSnapshotRoundTrip() throws {
        let snapshot = SpecOperationSnapshot(
            method: "GET",
            urlTemplate: "{{base_url}}/pets",
            params: [SpecKeyValue(key: "limit", value: "10", enabled: true)],
            headers: [SpecKeyValue(key: "Accept", value: "application/json", enabled: true)],
            body: .json(content: #"{"name":"Fluffy"}"#)
        )

        let decoded = try roundTrip(snapshot)
        #expect(decoded == snapshot)
    }

    @Test func fingerprintIsStableForCanonicalJSON() throws {
        let snapshot = SpecOperationSnapshot(
            method: "POST",
            urlTemplate: "{{base_url}}/pets",
            params: [
                SpecKeyValue(key: "z", value: "1", enabled: true),
                SpecKeyValue(key: "a", value: "2", enabled: true),
            ],
            headers: [],
            body: .none
        )

        let first = SpecSnapshotService.fingerprint(for: snapshot)
        let second = SpecSnapshotService.fingerprint(for: snapshot)
        #expect(first == second)
        #expect(first.count == 64)
    }

    // MARK: - Extraction

    @Test func makeSnapshotStripsEmptyRowsAndSortsByKey() {
        var httpData = HttpRequestData()
        httpData.method = .get
        httpData.url = "{{base_url}}/pets"
        httpData.params = [
            KeyValueEntry(key: "z", value: "9", enabled: true),
            KeyValueEntry(),
            KeyValueEntry(key: "a", value: "1", enabled: false),
        ]
        httpData.headers = [
            KeyValueEntry(),
            KeyValueEntry(key: "X-Trace", value: "1", enabled: true),
        ]
        httpData.bodyType = .json
        httpData.bodyContent = "{}"

        let snapshot = SpecSnapshotService.makeSnapshot(from: httpData)
        #expect(snapshot.method == "GET")
        #expect(snapshot.params.map(\.key) == ["a", "z"])
        #expect(snapshot.headers.map(\.key) == ["X-Trace"])
        #expect(snapshot.body == .json(content: "{}"))
    }

    @Test func makeSnapshotExcludesAuthScaffoldHeaders() {
        var httpData = HttpRequestData()
        httpData.headers = [
            KeyValueEntry(key: "Accept", value: "application/json", enabled: true),
            KeyValueEntry(key: "Authorization", value: "Bearer secret", enabled: true),
        ]
        httpData.authType = .bearer
        httpData.authToken = "secret"

        let snapshot = SpecSnapshotService.makeSnapshot(from: httpData)
        #expect(snapshot.headers.count == 1)
        #expect(snapshot.headers.first?.key == "Accept")
    }

    @Test func makeSnapshotMapsBodyVariants() {
        var urlencoded = HttpRequestData()
        urlencoded.bodyType = .urlencoded
        urlencoded.bodyFormData = [KeyValueEntry(key: "name", value: "cat", enabled: true)]
        #expect(
            SpecSnapshotService.makeSnapshot(from: urlencoded).body
                == .urlencoded(fields: [SpecKeyValue(key: "name", value: "cat", enabled: true)])
        )

        var formData = HttpRequestData()
        formData.bodyType = .formData
        formData.bodyFormDataEntries = [
            FormDataEntry(key: "avatar", value: "", fieldType: .file, fileName: "cat.png", mimeType: "image/png"),
        ]
        if case .formData(let entries) = SpecSnapshotService.makeSnapshot(from: formData).body {
            #expect(entries.count == 1)
            #expect(entries[0].fieldType == .file)
            #expect(entries[0].fileName == "cat.png")
        } else {
            Issue.record("Expected formData body snapshot")
        }

        var raw = HttpRequestData()
        raw.bodyType = .raw
        raw.bodyContent = "<xml/>"
        raw.rawContentType = .xml
        #expect(
            SpecSnapshotService.makeSnapshot(from: raw).body
                == .raw(content: "<xml/>", contentType: "application/xml")
        )

        var binary = HttpRequestData()
        binary.bodyType = .binary
        binary.binaryFileName = "payload.bin"
        #expect(SpecSnapshotService.makeSnapshot(from: binary).body == .binary(fileName: "payload.bin"))
    }

    // MARK: - Disk + payload

    @Test func writeReadDiskRoundTrip() throws {
        let tempRoot = makeTempSpecsRoot()
        defer { cleanup(tempRoot) }

        let projectId = UUID()
        let requestId = UUID()
        let snapshot = sampleSnapshot()

        try SpecSnapshotService.writeSnapshotToDisk(snapshot, projectId: projectId, requestId: requestId)
        let fileURL = SpecSnapshotService.snapshotFileURL(projectId: projectId, requestId: requestId)
        #expect(FileManager.default.fileExists(atPath: fileURL.path))

        let loaded = try #require(SpecSnapshotService.readSnapshotFromDisk(projectId: projectId, requestId: requestId))
        #expect(loaded == snapshot)
    }

    @Test func payloadRoundTrip() throws {
        let snapshot = sampleSnapshot()
        let payload = try #require(SpecSnapshotService.encodePayload(snapshot))
        #expect(payload.count <= SpecSnapshotService.maxSnapshotPayloadBytes)

        let decoded = try SpecSnapshotService.decodePayload(payload)
        #expect(decoded == snapshot)
        #expect(SpecSnapshotService.fingerprint(for: decoded) == SpecSnapshotService.fingerprint(for: snapshot))
    }

    @Test func payloadOmittedWhenCompressedSizeExceedsCap() throws {
        SpecSnapshotService.maxSnapshotPayloadBytesForTesting = 64
        defer { SpecSnapshotService.maxSnapshotPayloadBytesForTesting = nil }

        let snapshot = sampleSnapshot()
        let payload = SpecSnapshotService.encodePayload(snapshot)
        #expect(payload == nil)
    }

    @Test func hydrateWritesDiskFileFromPayload() throws {
        let tempRoot = makeTempSpecsRoot()
        defer { cleanup(tempRoot) }

        let projectId = UUID()
        let requestId = UUID()
        let snapshot = sampleSnapshot()
        let payload = try #require(SpecSnapshotService.encodePayload(snapshot))

        var request = Request(id: requestId, projectId: projectId, name: "List pets", type: .http)
        request.specSnapshotPayload = payload

        let fileURL = SpecSnapshotService.snapshotFileURL(projectId: projectId, requestId: requestId)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))

        try SpecSnapshotService.hydrateFromPayloadIfNeeded(for: request)

        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        let hydrated = try #require(SpecSnapshotService.readSnapshotFromDisk(projectId: projectId, requestId: requestId))
        #expect(hydrated == snapshot)
    }

    @Test func hydrateSkipsWhenDiskFileAlreadyExists() throws {
        let tempRoot = makeTempSpecsRoot()
        defer { cleanup(tempRoot) }

        let projectId = UUID()
        let requestId = UUID()
        let onDisk = sampleSnapshot(url: "{{base_url}}/on-disk")
        try SpecSnapshotService.writeSnapshotToDisk(onDisk, projectId: projectId, requestId: requestId)

        let alternate = sampleSnapshot(url: "{{base_url}}/from-payload")
        let payload = try #require(SpecSnapshotService.encodePayload(alternate))

        var request = Request(id: requestId, projectId: projectId, name: "List pets", type: .http)
        request.specSnapshotPayload = payload

        try SpecSnapshotService.hydrateFromPayloadIfNeeded(for: request)

        let loaded = try #require(SpecSnapshotService.readSnapshotFromDisk(projectId: projectId, requestId: requestId))
        #expect(loaded == onDisk)
    }

    // MARK: - Local modifications

    @Test func hasLocalModificationsReturnsEmptyWhenUnchanged() {
        let baseline = sampleSnapshot()
        let httpData = baselineHttpData()

        let deltas = SpecSnapshotService.hasLocalModifications(baseline: baseline, httpData: httpData)
        #expect(deltas.isEmpty)
        #expect(!SpecSnapshotService.hasAnyLocalModifications(
            request: requestWithFingerprint(for: baseline),
            httpData: httpData
        ))
    }

    @Test func hasLocalModificationsDetectsPerFieldDeltas() {
        let baseline = sampleSnapshot()
        let matchingBaselineData = baselineHttpData()

        var urlChanged = matchingBaselineData
        urlChanged.url = "{{base_url}}/pets-v2"
        let urlDeltas = SpecSnapshotService.hasLocalModifications(baseline: baseline, httpData: urlChanged)
        #expect(urlDeltas.count == 1)
        #expect(urlDeltas[0].field == .url)
        #expect(urlDeltas[0].oldValue == "{{base_url}}/pets")
        #expect(urlDeltas[0].newValue == "{{base_url}}/pets-v2")

        var methodChanged = matchingBaselineData
        methodChanged.method = .post
        let methodDeltas = SpecSnapshotService.hasLocalModifications(baseline: baseline, httpData: methodChanged)
        #expect(methodDeltas.count == 1)
        #expect(methodDeltas[0].field == .method)

        var paramsChanged = matchingBaselineData
        paramsChanged.params = [
            KeyValueEntry(id: UUID(), key: "limit", value: "25", enabled: true),
        ]
        let paramDeltas = SpecSnapshotService.hasLocalModifications(baseline: baseline, httpData: paramsChanged)
        #expect(paramDeltas.count == 1)
        #expect(paramDeltas[0].field == .params)

        var headersChanged = matchingBaselineData
        headersChanged.headers = [
            KeyValueEntry(key: "Accept", value: "application/json", enabled: true),
            KeyValueEntry(key: "X-Custom", value: "1", enabled: true),
        ]
        let headerDeltas = SpecSnapshotService.hasLocalModifications(baseline: baseline, httpData: headersChanged)
        #expect(headerDeltas.count == 1)
        #expect(headerDeltas[0].field == .headers)

        var bodyChanged = matchingBaselineData
        bodyChanged.bodyType = .json
        bodyChanged.bodyContent = #"{"name":"Fluffy"}"#
        let bodyDeltas = SpecSnapshotService.hasLocalModifications(baseline: baseline, httpData: bodyChanged)
        #expect(bodyDeltas.count == 1)
        #expect(bodyDeltas[0].field == .body)
    }

    @Test func hasLocalModificationsIgnoresKeyValueEntryIdChanges() {
        let baseline = sampleSnapshot()
        let httpData = HttpRequestData(
            method: .get,
            url: "{{base_url}}/pets",
            params: [
                KeyValueEntry(id: UUID(), key: "limit", value: "10", enabled: true),
            ],
            headers: [
                KeyValueEntry(id: UUID(), key: "Accept", value: "application/json", enabled: true),
            ],
            bodyType: .none
        )

        let deltas = SpecSnapshotService.hasLocalModifications(baseline: baseline, httpData: httpData)
        #expect(deltas.isEmpty)
    }

    @Test func hasLocalModificationsIgnoresAuthScaffoldHeaderEdits() {
        let baseline = sampleSnapshot()
        var httpData = baselineHttpData()
        httpData.headers = [
            KeyValueEntry(key: "Accept", value: "application/json", enabled: true),
            KeyValueEntry(key: "Authorization", value: "Bearer changed", enabled: true),
        ]
        httpData.authType = .bearer
        httpData.authToken = "changed"

        let deltas = SpecSnapshotService.hasLocalModifications(baseline: baseline, httpData: httpData)
        #expect(deltas.isEmpty)
    }

    @Test func markConflictsFlagsOverlappingSpecAndLocalChanges() {
        let baseline = sampleSnapshot()
        var httpData = baselineHttpData()
        httpData.params = [KeyValueEntry(key: "limit", value: "25", enabled: true)]

        var fieldDeltas = [
            SpecFieldDelta(
                field: .params,
                oldValue: "query:limit=10:req=false:en=false",
                newValue: "query:limit=50:req=false:en=false",
                isConflict: false
            ),
            SpecFieldDelta(
                field: .body,
                oldValue: "none",
                newValue: "json:{}",
                isConflict: false
            ),
        ]

        SpecSnapshotService.markConflicts(
            on: &fieldDeltas,
            baseline: baseline,
            httpData: httpData
        )

        #expect(fieldDeltas.contains { $0.isConflict })
        #expect(fieldDeltas[0].isConflict)
        #expect(!fieldDeltas[1].isConflict)
    }

    @Test func markConflictsUsesStoredBaselineFromRequest() throws {
        let tempRoot = makeTempSpecsRoot()
        defer { cleanup(tempRoot) }

        let projectId = UUID()
        let requestId = UUID()
        let baseline = sampleSnapshot()
        try SpecSnapshotService.writeSnapshotToDisk(baseline, projectId: projectId, requestId: requestId)

        var request = Request(id: requestId, projectId: projectId, name: "List pets", type: .http)
        request.specFieldFingerprint = SpecSnapshotService.fingerprint(for: baseline)

        var httpData = baselineHttpData()
        httpData.params = [KeyValueEntry(key: "limit", value: "99", enabled: true)]

        var fieldDeltas = [
            SpecFieldDelta(
                field: .params,
                oldValue: "query:limit=10:req=false:en=false",
                newValue: "query:limit=50:req=false:en=false",
                isConflict: false
            ),
        ]

        #expect(SpecSnapshotService.markConflicts(on: &fieldDeltas, request: request, httpData: httpData))
        #expect(fieldDeltas[0].isConflict)
        #expect(SpecSnapshotService.baselineSnapshot(for: request) == baseline)
    }

    @Test @MainActor func applySnapshotsPopulatesRequestFields() throws {
        let tempRoot = makeTempSpecsRoot()
        defer { cleanup(tempRoot) }

        let projectId = UUID()
        var request = Request(projectId: projectId, name: "List pets", type: .http)
        request.httpData = HttpRequestData(
            method: .get,
            url: "{{base_url}}/pets",
            params: [KeyValueEntry(key: "limit", value: "10", enabled: true)],
            headers: [KeyValueEntry(key: "Accept", value: "application/json", enabled: true)],
            bodyType: .none
        )

        var requests = [request]
        try SpecSnapshotService.applySnapshots(to: &requests, projectId: projectId)

        let updated = try #require(requests.first)
        #expect(updated.specFieldFingerprint?.count == 64)
        #expect(updated.specSnapshotPayload != nil)
        #expect(updated.specLastSyncedAt != nil)

        let fileURL = SpecSnapshotService.snapshotFileURL(projectId: projectId, requestId: updated.id)
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
    }

    // MARK: - Spec bytes hydration

    @Test func writeSpecBytesToDiskPersistsFileAndFingerprint() throws {
        let tempRoot = makeTempSpecsRoot()
        defer { cleanup(tempRoot) }

        let projectId = UUID()
        let bytes = Data("openapi: 3.0.3\ninfo:\n  title: Petstore\n".utf8)
        let fingerprint = canonicalFingerprint(resolvedBytes: bytes)

        try SpecSnapshotService.writeSpecBytesToDisk(
            bytes: bytes,
            projectId: projectId,
            specFileName: "spec.yaml",
            contentFingerprint: fingerprint
        )

        let specURL = SpecImportService.specsDirectory(for: projectId).appendingPathComponent("spec.yaml")
        let fingerprintURL = SpecImportService.specsDirectory(for: projectId).appendingPathComponent("fingerprint.txt")
        #expect(try Data(contentsOf: specURL) == bytes)
        #expect(try String(contentsOf: fingerprintURL, encoding: .utf8) == fingerprint)
    }

    @Test @MainActor func makeLinkedSpecDocumentSkipsDetachedProjects() {
        var linked = Project(name: "Linked")
        linked.specLink = SpecLink(
            format: .openapi,
            source: .url,
            contentFingerprint: "fp",
            importedAt: Date(),
            sourceURL: "https://example.test/openapi.yaml",
            isDetached: false
        )
        #expect(SpecSnapshotService.makeLinkedSpecDocument(project: linked, specFileName: "spec.yaml") != nil)

        var detached = Project(name: "Detached")
        detached.specLink = SpecLink(
            format: .openapi,
            source: .url,
            contentFingerprint: "fp",
            importedAt: Date(),
            sourceURL: "https://example.test/openapi.yaml",
            isDetached: true
        )
        #expect(SpecSnapshotService.makeLinkedSpecDocument(project: detached, specFileName: "spec.yaml") == nil)
    }

    @Test @MainActor func hydrateSpecBytesFromSourceRefetchesWhenAssetMissing() async throws {
        let tempRoot = makeTempSpecsRoot()
        defer { cleanup(tempRoot) }

        let projectId = UUID()
        let bytes = Data("openapi: 3.0.3\ninfo:\n  title: Petstore\n".utf8)
        let fingerprint = canonicalFingerprint(resolvedBytes: bytes)
        let sourceURL = URL(string: "https://example.test/openapi.yaml")!

        let fetchService = makeMockFetchService { request in
            #expect(request.url?.host == "example.test")
            return mockOKResponse(for: request, body: bytes)
        }
        let originalFetch = SafeFetchService.shared
        SafeFetchService.shared = fetchService
        defer { SafeFetchService.shared = originalFetch }

        var project = Project(id: projectId, name: "Linked")
        project.specLink = SpecLink(
            format: .openapi,
            source: .url,
            contentFingerprint: fingerprint,
            importedAt: Date(),
            sourceURL: sourceURL.absoluteString,
            isDetached: false
        )

        let document = SpecDocument(
            id: projectId,
            projectId: projectId,
            contentFingerprint: fingerprint,
            specFileName: "spec.yaml",
            sourceURL: sourceURL.absoluteString,
            assetHydrated: false
        )

        let store = ProjectStore.mock(projects: [project], specDocuments: [document])

        let outcome = await SpecSnapshotService.hydrateSpecBytesFromSourceIfNeeded(
            document: document,
            specLink: project.specLink,
            store: store
        )

        #expect(outcome == .hydrated)
        #expect(store.specDocuments.first?.assetHydrated == true)
        #expect(store.isSpecProjectReadOnly(projectId: projectId) == false)

        let specURL = SpecImportService.specsDirectory(for: projectId).appendingPathComponent("spec.yaml")
        #expect(FileManager.default.fileExists(atPath: specURL.path))
        #expect(try Data(contentsOf: specURL) == bytes)
    }

    @Test @MainActor func hydrateSpecBytesFromSourceRejectsFingerprintMismatch() async throws {
        let tempRoot = makeTempSpecsRoot()
        defer { cleanup(tempRoot) }

        let projectId = UUID()
        let bytes = Data("openapi: 3.0.3\ninfo:\n  title: Petstore\n".utf8)
        let sourceURL = URL(string: "https://example.test/openapi.yaml")!

        let fetchService = makeMockFetchService { request in
            mockOKResponse(for: request, body: bytes)
        }
        let originalFetch = SafeFetchService.shared
        SafeFetchService.shared = fetchService
        defer { SafeFetchService.shared = originalFetch }

        let specLink = SpecLink(
            format: .openapi,
            source: .url,
            contentFingerprint: "expected-fingerprint",
            importedAt: Date(),
            sourceURL: sourceURL.absoluteString,
            isDetached: false
        )

        let document = SpecDocument(
            id: projectId,
            projectId: projectId,
            contentFingerprint: "expected-fingerprint",
            specFileName: "spec.yaml",
            sourceURL: sourceURL.absoluteString,
            assetHydrated: false
        )

        var linkedProject = Project(id: projectId, name: "Linked")
        linkedProject.specLink = specLink
        let store = ProjectStore.mock(projects: [linkedProject], specDocuments: [document])

        let outcome = await SpecSnapshotService.hydrateSpecBytesFromSourceIfNeeded(
            document: document,
            specLink: specLink,
            store: store
        )

        #expect(outcome == .fingerprintMismatch)
        #expect(store.specDocuments.first?.assetHydrated == false)
        #expect(store.isSpecProjectReadOnly(projectId: projectId) == true)
    }

    // MARK: - Helpers

    @MainActor
    private func makeMockFetchService(
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> SafeFetchService {
        SpecSnapshotMockURLProtocol.handler = handler
        return SafeFetchService(
            resolver: SpecSnapshotMockHostResolver(mapping: ["example.test": ["93.184.216.34"]]),
            protocolClasses: [SpecSnapshotMockURLProtocol.self]
        )
    }

    private func baselineHttpData() -> HttpRequestData {
        HttpRequestData(
            method: .get,
            url: "{{base_url}}/pets",
            params: [KeyValueEntry(key: "limit", value: "10", enabled: true)],
            headers: [KeyValueEntry(key: "Accept", value: "application/json", enabled: true)],
            bodyType: .none
        )
    }

    private func requestWithFingerprint(for snapshot: SpecOperationSnapshot) -> Request {
        var request = Request(projectId: UUID(), name: "List pets", type: .http)
        request.specFieldFingerprint = SpecSnapshotService.fingerprint(for: snapshot)
        return request
    }

    private func sampleSnapshot(url: String = "{{base_url}}/pets") -> SpecOperationSnapshot {
        SpecOperationSnapshot(
            method: "GET",
            urlTemplate: url,
            params: [SpecKeyValue(key: "limit", value: "10", enabled: true)],
            headers: [SpecKeyValue(key: "Accept", value: "application/json", enabled: true)],
            body: .none
        )
    }

    private func makeTempSpecsRoot() -> URL {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("spec-snapshot-tests-\(UUID().uuidString)", isDirectory: true)
        SpecImportService.specsRootDirectoryOverride = tempRoot
        return tempRoot
    }

    private func cleanup(_ tempRoot: URL) {
        SpecImportService.specsRootDirectoryOverride = nil
        try? FileManager.default.removeItem(at: tempRoot)
    }

    private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        let encoded = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(T.self, from: encoded)
        #expect(decoded == value)
        return decoded
    }
}

private struct SpecSnapshotMockHostResolver: HostResolving {
    let mapping: [String: [String]]

    func resolve(hostname: String) throws -> [String] {
        guard let addresses = mapping[hostname] else {
            throw SafeFetchError.dnsResolutionFailed(hostname)
        }
        return addresses
    }
}

nonisolated private func mockOKResponse(for request: URLRequest, body: Data) -> (HTTPURLResponse, Data) {
    let response = HTTPURLResponse(
        url: request.url!,
        statusCode: 200,
        httpVersion: "HTTP/1.1",
        headerFields: nil
    )!
    return (response, body)
}

private final class SpecSnapshotMockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canInit(with task: URLSessionTask) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}