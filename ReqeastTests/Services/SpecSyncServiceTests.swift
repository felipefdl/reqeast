//
//  SpecSyncServiceTests.swift
//  ReqeastTests
//

import Foundation
import Testing
@testable import Reqeast

@Suite("SpecSyncService", .serialized)
struct SpecSyncServiceTests {

    // MARK: - AC6: Rule A preserves user-owned fields

    @Test @MainActor func applyRuleAPreservesRenameCustomHeaderAndAuth() throws {
        let tempRoot = makeTempSpecsRoot()
        defer { cleanup(tempRoot) }

        let projectId = UUID()
        let requestId = UUID()

        var httpData = HttpRequestData(
            method: .get,
            url: "{{base_url}}/pet",
            params: [KeyValueEntry(key: "limit", value: "10", enabled: true)],
            headers: [KeyValueEntry(key: "Accept", value: "application/json", enabled: true)],
            bodyType: .none
        )
        httpData.authType = .bearer
        httpData.authToken = "user-secret"

        var request = Request(id: requestId, projectId: projectId, name: "List pets", type: .http)
        request.specIdentity = SpecOperationIdentity(primaryKey: "listPets")
        request.httpData = httpData

        var requests = [request]
        try SpecSnapshotService.applySnapshots(to: &requests, projectId: projectId)
        request = try #require(requests.first)

        // User edits after last sync (AC6).
        request.name = "My custom list"
        request.isRenamed = true
        request.httpData?.authToken = "user-secret"
        request.httpData?.headers.append(KeyValueEntry(key: "X-Custom", value: "keep-me", enabled: true))

        let store = ProjectStore.mock(requests: [request])

        let newOperation = NormalizedOperation(
            primaryKey: "listPets",
            alternateKeys: [],
            name: "List pets from spec",
            method: "GET",
            path: "/pet",
            deprecated: false,
            tags: [],
            protocol: .http,
            binding: nil,
            folderId: nil,
            parameters: [
                NormalizedParameter(
                    location: .query,
                    name: "limit",
                    value: "25",
                    required: false,
                    enabled: true,
                    valueSource: .fromExample
                ),
                NormalizedParameter(
                    location: .header,
                    name: "Accept",
                    value: "application/hal+json",
                    required: false,
                    enabled: true,
                    valueSource: .fromExample
                ),
            ],
            body: .none,
            bodyCandidates: [],
            auth: NormalizedAuth(
                schemeType: "http:Bearer",
                headerName: nil,
                queryName: nil,
                placeholderValue: "Bearer spec-token",
                oauth2GrantType: nil,
                oauth2AuthUrl: nil,
                oauth2TokenUrl: nil,
                oauth2Scopes: nil
            ),
            description: nil
        )

        let oldOperation = NormalizedOperation(
            primaryKey: "listPets",
            alternateKeys: [],
            name: "List pets",
            method: "GET",
            path: "/pet",
            deprecated: false,
            tags: [],
            protocol: .http,
            binding: nil,
            folderId: nil,
            parameters: [
                NormalizedParameter(
                    location: .query,
                    name: "limit",
                    value: "10",
                    required: false,
                    enabled: true,
                    valueSource: .fromExample
                ),
            ],
            body: .none,
            bodyCandidates: [],
            auth: nil,
            description: nil
        )

        let diff = SpecSyncDiff(
            added: [],
            removed: [],
            modified: [
                OperationDiff(
                    requestId: requestId.uuidString,
                    primaryKey: "listPets",
                    oldOperation: oldOperation,
                    newOperation: newOperation,
                    fieldDeltas: [
                        SpecFieldDelta(field: .name, oldValue: "List pets", newValue: "List pets from spec", isConflict: false),
                        SpecFieldDelta(field: .params, oldValue: "old", newValue: "new", isConflict: false),
                    ]
                ),
            ],
            unchanged: [],
            identityChanged: []
        )

        try SpecSyncService.applyRuleA(
            diff: diff,
            selections: SpecSyncSelections(modifiedRequestIDs: [requestId.uuidString]),
            projectId: projectId,
            store: store
        )

        let updated = try #require(store.requests.first)
        let updatedData = try #require(updated.httpData)

        #expect(updated.name == "My custom list")
        #expect(updated.isRenamed == true)
        #expect(updatedData.authType == .bearer)
        #expect(updatedData.authToken == "user-secret")
        #expect(updatedData.headers.contains { $0.key == "X-Custom" && $0.value == "keep-me" })
        #expect(updatedData.params.contains { $0.key == "limit" && $0.value == "25" })
        #expect(updatedData.headers.contains { $0.key == "Accept" && $0.value == "application/hal+json" })
        #expect(!store.syncApplyInProgress)
    }

    @Test @MainActor func applyRuleAPreservesOAuth2Auth() throws {
        let tempRoot = makeTempSpecsRoot()
        defer { cleanup(tempRoot) }

        let projectId = UUID()
        let requestId = UUID()

        var httpData = HttpRequestData(
            method: .post,
            url: "{{base_url}}/oauth",
            params: [KeyValueEntry()],
            headers: [KeyValueEntry()],
            bodyType: .none
        )
        httpData.authType = .oauth2
        httpData.authToken = "user-token"
        httpData.authOAuth2GrantType = OAuth2GrantType.clientCredentials.rawValue
        httpData.authOAuth2TokenURL = "https://user.example.test/oauth/token"
        httpData.authOAuth2Scopes = "read write"

        var request = Request(id: requestId, projectId: projectId, name: "OAuth protected", type: .http)
        request.specIdentity = SpecOperationIdentity(primaryKey: "postOAuth")
        request.httpData = httpData

        var requests = [request]
        try SpecSnapshotService.applySnapshots(to: &requests, projectId: projectId)
        request = try #require(requests.first)

        let store = ProjectStore.mock(requests: [request])

        let newOperation = NormalizedOperation(
            primaryKey: "postOAuth",
            alternateKeys: [],
            name: "OAuth protected",
            method: "POST",
            path: "/oauth",
            deprecated: false,
            tags: [],
            protocol: .http,
            binding: nil,
            folderId: nil,
            parameters: [],
            body: .none,
            bodyCandidates: [],
            auth: NormalizedAuth(
                schemeType: "oauth2",
                headerName: "Authorization",
                queryName: nil,
                placeholderValue: "Bearer spec-token",
                oauth2GrantType: "clientCredentials",
                oauth2AuthUrl: nil,
                oauth2TokenUrl: "https://auth.example.test/oauth/token",
                oauth2Scopes: "write"
            ),
            description: nil
        )

        let oldOperation = NormalizedOperation(
            primaryKey: "postOAuth",
            alternateKeys: [],
            name: "OAuth protected",
            method: "POST",
            path: "/oauth",
            deprecated: false,
            tags: [],
            protocol: .http,
            binding: nil,
            folderId: nil,
            parameters: [],
            body: .none,
            bodyCandidates: [],
            auth: nil,
            description: nil
        )

        let diff = SpecSyncDiff(
            added: [],
            removed: [],
            modified: [
                OperationDiff(
                    requestId: requestId.uuidString,
                    primaryKey: "postOAuth",
                    oldOperation: oldOperation,
                    newOperation: newOperation,
                    fieldDeltas: [
                        SpecFieldDelta(field: .params, oldValue: "old", newValue: "new", isConflict: false),
                    ]
                ),
            ],
            unchanged: [],
            identityChanged: []
        )

        try SpecSyncService.applyRuleA(
            diff: diff,
            selections: SpecSyncSelections(modifiedRequestIDs: [requestId.uuidString]),
            projectId: projectId,
            store: store
        )

        let updatedData = try #require(store.requests.first?.httpData)
        #expect(updatedData.authType == .oauth2)
        #expect(updatedData.authToken == "user-token")
        #expect(updatedData.authOAuth2GrantType == OAuth2GrantType.clientCredentials.rawValue)
        #expect(updatedData.authOAuth2TokenURL == "https://user.example.test/oauth/token")
        #expect(updatedData.authOAuth2Scopes == "read write")
    }

    // MARK: - AC7: removed ops marked stale, never deleted

    @Test @MainActor func applyRuleAMarksRemovedOpsStaleWithoutDeleting() throws {
        let projectId = UUID()
        let requestId = UUID()

        var request = Request(id: requestId, projectId: projectId, name: "List pets", type: .http)
        request.specIdentity = SpecOperationIdentity(primaryKey: "listPets")
        request.httpData = HttpRequestData(method: .get, url: "{{base_url}}/pet")

        let store = ProjectStore.mock(requests: [request])

        let removedOperation = NormalizedOperation(
            primaryKey: "listPets",
            alternateKeys: [],
            name: "List pets",
            method: "GET",
            path: "/pet",
            deprecated: false,
            tags: [],
            protocol: .http,
            binding: nil,
            folderId: nil,
            parameters: [],
            body: .none,
            bodyCandidates: [],
            auth: nil,
            description: nil
        )

        let diff = SpecSyncDiff(
            added: [],
            removed: [
                MatchedOperation(
                    requestId: requestId.uuidString,
                    primaryKey: "listPets",
                    operation: removedOperation
                ),
            ],
            modified: [],
            unchanged: [],
            identityChanged: []
        )

        try SpecSyncService.applyRuleA(
            diff: diff,
            selections: SpecSyncSelections(removedRequestIDs: [requestId.uuidString]),
            projectId: projectId,
            store: store
        )

        #expect(store.requests.count == 1)
        #expect(store.requests.first?.isSpecStale == true)
        #expect(store.requests.first?.id == requestId)
    }

    // MARK: - Identity change

    @Test @MainActor func applyRuleARotatesAlternateKeysOnIdentityChange() throws {
        let tempRoot = makeTempSpecsRoot()
        defer { cleanup(tempRoot) }

        let projectId = UUID()
        let requestId = UUID()

        var request = Request(id: requestId, projectId: projectId, name: "List pets", type: .http)
        request.specIdentity = SpecOperationIdentity(primaryKey: "listPets")
        request.httpData = HttpRequestData(method: .get, url: "{{base_url}}/pet")

        var requests = [request]
        try SpecSnapshotService.applySnapshots(to: &requests, projectId: projectId)
        request = try #require(requests.first)

        let store = ProjectStore.mock(requests: [request])

        let oldOperation = NormalizedOperation(
            primaryKey: "listPets",
            alternateKeys: [],
            name: "List pets",
            method: "GET",
            path: "/pet",
            deprecated: false,
            tags: [],
            protocol: .http,
            binding: nil,
            folderId: nil,
            parameters: [],
            body: .none,
            bodyCandidates: [],
            auth: nil,
            description: nil
        )

        let newOperation = NormalizedOperation(
            primaryKey: "listAllPets",
            alternateKeys: [],
            name: "List all pets",
            method: "GET",
            path: "/pet",
            deprecated: false,
            tags: [],
            protocol: .http,
            binding: nil,
            folderId: nil,
            parameters: [],
            body: .none,
            bodyCandidates: [],
            auth: nil,
            description: nil
        )

        let diff = SpecSyncDiff(
            added: [],
            removed: [],
            modified: [],
            unchanged: [],
            identityChanged: [
                IdentityChangeDiff(
                    requestId: requestId.uuidString,
                    oldPrimaryKey: "listPets",
                    newPrimaryKey: "listAllPets",
                    oldOperation: oldOperation,
                    newOperation: newOperation,
                    fieldDeltas: [
                        SpecFieldDelta(field: .name, oldValue: "List pets", newValue: "List all pets", isConflict: false),
                    ]
                ),
            ]
        )

        try SpecSyncService.applyRuleA(
            diff: diff,
            selections: SpecSyncSelections(identityChangedRequestIDs: [requestId.uuidString]),
            projectId: projectId,
            store: store
        )

        let updated = try #require(store.requests.first)
        #expect(updated.id == requestId)
        #expect(updated.specIdentity?.primaryKey == "listAllPets")
        #expect(updated.specIdentity?.alternateKeys.contains("listPets") == true)
        #expect(updated.name == "List all pets")
    }

    // MARK: - Conflict handling

    @Test @MainActor func enrichDiffWithConflictsMarksLocallyModifiedFields() throws {
        let tempRoot = makeTempSpecsRoot()
        defer { cleanup(tempRoot) }

        let projectId = UUID()
        let requestId = UUID()

        var request = Request(id: requestId, projectId: projectId, name: "Get pet", type: .http)
        request.specIdentity = SpecOperationIdentity(primaryKey: "getPet")
        request.httpData = HttpRequestData(method: .get, url: "{{base_url}}/pet")

        var requests = [request]
        try SpecSnapshotService.applySnapshots(to: &requests, projectId: projectId)
        request = try #require(requests.first)

        request.httpData?.url = "{{base_url}}/pet/custom"
        let store = ProjectStore.mock(requests: [request])

        let diff = SpecSyncDiff(
            added: [],
            removed: [],
            modified: [
                OperationDiff(
                    requestId: requestId.uuidString,
                    primaryKey: "getPet",
                    oldOperation: sampleOperation(primaryKey: "getPet"),
                    newOperation: sampleOperation(primaryKey: "getPet"),
                    fieldDeltas: [
                        SpecFieldDelta(field: .url, oldValue: "/pet", newValue: "/pets", isConflict: false),
                    ]
                ),
            ],
            unchanged: [],
            identityChanged: []
        )

        let enriched = SpecSyncService.enrichDiffWithConflicts(diff, store: store)
        let urlDelta = try #require(enriched.modified.first?.fieldDeltas.first { $0.field == .url })
        #expect(urlDelta.isConflict == true)
    }

    @Test @MainActor func applyRuleAAddsSelectedOperation() throws {
        let tempRoot = makeTempSpecsRoot()
        defer { cleanup(tempRoot) }

        let projectId = UUID()
        let store = ProjectStore.mock()

        let addedOperation = NormalizedOperation(
            primaryKey: "createPet",
            alternateKeys: [],
            name: "Create pet",
            method: "POST",
            path: "/pet",
            deprecated: false,
            tags: [],
            protocol: .http,
            binding: nil,
            folderId: nil,
            parameters: [],
            body: .none,
            bodyCandidates: [],
            auth: nil,
            description: nil
        )

        let diff = SpecSyncDiff(
            added: [addedOperation],
            removed: [],
            modified: [],
            unchanged: [],
            identityChanged: []
        )

        try SpecSyncService.applyRuleA(
            diff: diff,
            selections: SpecSyncSelections(addedPrimaryKeys: ["createPet"]),
            projectId: projectId,
            store: store
        )

        #expect(store.requests.count == 1)
        let added = try #require(store.requests.first)
        #expect(added.projectId == projectId)
        #expect(added.specIdentity?.primaryKey == "createPet")
        #expect(added.name == "Create pet")
    }

    @Test @MainActor func applyRuleAKeepsLocalURLWhenLocallyModified() throws {
        let tempRoot = makeTempSpecsRoot()
        defer { cleanup(tempRoot) }

        let projectId = UUID()
        let requestId = UUID()

        var request = Request(id: requestId, projectId: projectId, name: "Get pet", type: .http)
        request.specIdentity = SpecOperationIdentity(primaryKey: "getPet")
        request.httpData = HttpRequestData(method: .get, url: "{{base_url}}/pet")

        var requests = [request]
        try SpecSnapshotService.applySnapshots(to: &requests, projectId: projectId)
        request = try #require(requests.first)

        request.httpData?.url = "{{base_url}}/pet/custom"
        let store = ProjectStore.mock(requests: [request])

        let oldOperation = NormalizedOperation(
            primaryKey: "getPet",
            alternateKeys: [],
            name: "Get pet",
            method: "GET",
            path: "/pet",
            deprecated: false,
            tags: [],
            protocol: .http,
            binding: nil,
            folderId: nil,
            parameters: [],
            body: .none,
            bodyCandidates: [],
            auth: nil,
            description: nil
        )

        let newOperation = NormalizedOperation(
            primaryKey: "getPet",
            alternateKeys: [],
            name: "Get pet",
            method: "GET",
            path: "/pets",
            deprecated: false,
            tags: [],
            protocol: .http,
            binding: nil,
            folderId: nil,
            parameters: [],
            body: .none,
            bodyCandidates: [],
            auth: nil,
            description: nil
        )

        let diff = SpecSyncDiff(
            added: [],
            removed: [],
            modified: [
                OperationDiff(
                    requestId: requestId.uuidString,
                    primaryKey: "getPet",
                    oldOperation: oldOperation,
                    newOperation: newOperation,
                    fieldDeltas: [
                        SpecFieldDelta(field: .url, oldValue: "/pet", newValue: "/pets", isConflict: true),
                    ]
                ),
            ],
            unchanged: [],
            identityChanged: []
        )

        try SpecSyncService.applyRuleA(
            diff: diff,
            selections: SpecSyncSelections(modifiedRequestIDs: [requestId.uuidString]),
            projectId: projectId,
            store: store
        )

        #expect(store.requests.first?.httpData?.url == "{{base_url}}/pet/custom")
    }

    // MARK: - sync apply batch pipeline

    @Test @MainActor func applyBumpsSpecRevisionAndFingerprint() throws {
        let tempRoot = makeTempSpecsRoot()
        defer { cleanup(tempRoot) }

        let projectId = UUID()
        let requestId = UUID()
        let oldFingerprint = "old-fingerprint"
        let newFingerprint = "new-fingerprint"
        let newBytes = Data("{\"openapi\":\"3.0.0\"}".utf8)

        var project = Project(id: projectId, name: "Petstore")
        project.specLink = SpecLink(
            format: .openapi,
            source: .url,
            contentFingerprint: oldFingerprint,
            importedAt: Date(),
            sourceURL: "https://example.test/openapi.json",
            specRevision: 2,
            isDetached: false
        )

        var request = Request(id: requestId, projectId: projectId, name: "List pets", type: .http)
        request.specIdentity = SpecOperationIdentity(primaryKey: "listPets")
        request.httpData = HttpRequestData(method: .get, url: "{{base_url}}/pet")

        let store = ProjectStore.mock(projects: [project], requests: [request])
        let diff = SpecSyncDiff(
            added: [],
            removed: [
                MatchedOperation(
                    requestId: requestId.uuidString,
                    primaryKey: "listPets",
                    operation: sampleOperation(primaryKey: "listPets")
                ),
            ],
            modified: [],
            unchanged: [],
            identityChanged: []
        )

        try SpecSyncService.apply(
            diff: diff,
            selections: SpecSyncSelections(removedRequestIDs: [requestId.uuidString]),
            projectId: projectId,
            newContentFingerprint: newFingerprint,
            specBytes: newBytes,
            store: store
        )

        let updatedProject = try #require(store.projects.first)
        #expect(updatedProject.specLink?.specRevision == 3)
        #expect(updatedProject.specLink?.contentFingerprint == newFingerprint)
        #expect(updatedProject.specLink?.lastSyncedAt != nil)

        let fingerprintURL = SpecImportService.specsDirectory(for: projectId)
            .appendingPathComponent("fingerprint.txt")
        let diskFingerprint = try String(contentsOf: fingerprintURL, encoding: .utf8)
        #expect(diskFingerprint == newFingerprint)
    }

    @Test @MainActor func applyCallsSaveLocalAndQueueSaveBatchOnce() throws {
        let tempRoot = makeTempSpecsRoot()
        defer { cleanup(tempRoot) }

        let sync = CloudSyncService.shared
        sync.queueSaveBatchCallCount = 0
        storeCountersReset()

        let projectId = UUID()
        let requestId = UUID()
        var project = Project(id: projectId, name: "Petstore")
        project.specLink = SpecLink(
            format: .openapi,
            source: .url,
            contentFingerprint: "old",
            importedAt: Date(),
            sourceURL: "https://example.test/openapi.json",
            isDetached: false
        )

        var request = Request(id: requestId, projectId: projectId, name: "List pets", type: .http)
        request.specIdentity = SpecOperationIdentity(primaryKey: "listPets")
        request.httpData = HttpRequestData(method: .get, url: "{{base_url}}/pet")

        let store = ProjectStore.mock(projects: [project], requests: [request])
        store.syncApplySaveLocalCallCount = 0

        let diff = SpecSyncDiff(
            added: [],
            removed: [
                MatchedOperation(
                    requestId: requestId.uuidString,
                    primaryKey: "listPets",
                    operation: sampleOperation(primaryKey: "listPets")
                ),
            ],
            modified: [],
            unchanged: [],
            identityChanged: []
        )

        try SpecSyncService.apply(
            diff: diff,
            selections: SpecSyncSelections(removedRequestIDs: [requestId.uuidString]),
            projectId: projectId,
            newContentFingerprint: "new",
            specBytes: Data("{\"openapi\":\"3.0.0\"}".utf8),
            store: store
        )

        #expect(store.syncApplySaveLocalCallCount == 1)
        #expect(sync.queueSaveBatchCallCount == 1)

        let requestRecord = "Request/\(requestId.uuidString)"
        let specDocumentRecord = "SpecDocument/\(projectId.uuidString)"
        let projectRecord = "Project/\(projectId.uuidString)"
        #expect(sync.lastQueueSaveBatchRecordOrder == [requestRecord, specDocumentRecord, projectRecord])

        let specDocument = try #require(store.specDocuments.first)
        #expect(specDocument.projectId == projectId)
        #expect(specDocument.contentFingerprint == "new")
        #expect(specDocument.assetHydrated == true)
    }

    @Test @MainActor func applyClearsSyncApplyInProgressAfterApply() throws {
        let tempRoot = makeTempSpecsRoot()
        defer { cleanup(tempRoot) }

        let projectId = UUID()
        let requestId = UUID()
        var project = Project(id: projectId, name: "Petstore")
        project.specLink = SpecLink(
            format: .openapi,
            source: .url,
            contentFingerprint: "old",
            importedAt: Date(),
            sourceURL: "https://example.test/openapi.json",
            isDetached: false
        )

        var request = Request(id: requestId, projectId: projectId, name: "List pets", type: .http)
        request.specIdentity = SpecOperationIdentity(primaryKey: "listPets")
        request.httpData = HttpRequestData(method: .get, url: "{{base_url}}/pet")

        let store = ProjectStore.mock(projects: [project], requests: [request])
        let diff = SpecSyncDiff(
            added: [],
            removed: [
                MatchedOperation(
                    requestId: requestId.uuidString,
                    primaryKey: "listPets",
                    operation: sampleOperation(primaryKey: "listPets")
                ),
            ],
            modified: [],
            unchanged: [],
            identityChanged: []
        )

        #expect(!store.syncApplyInProgress)

        try SpecSyncService.apply(
            diff: diff,
            selections: SpecSyncSelections(removedRequestIDs: [requestId.uuidString]),
            projectId: projectId,
            newContentFingerprint: "new",
            specBytes: Data("{\"openapi\":\"3.0.0\"}".utf8),
            store: store
        )

        #expect(!store.syncApplyInProgress)
    }

    @Test @MainActor func applyRollsBackStoreOnPersistFailure() {
        let tempRoot = makeTempSpecsRoot()
        defer { cleanup(tempRoot) }

        let projectId = UUID()
        let requestId = UUID()
        let originalProject = {
            var project = Project(id: projectId, name: "Petstore")
            project.specLink = SpecLink(
                format: .openapi,
                source: .url,
                contentFingerprint: "old",
                importedAt: Date(),
                sourceURL: "https://example.test/openapi.json",
                specRevision: 1,
                isDetached: false
            )
            return project
        }()

        var request = Request(id: requestId, projectId: projectId, name: "List pets", type: .http)
        request.specIdentity = SpecOperationIdentity(primaryKey: "listPets")
        request.httpData = HttpRequestData(method: .get, url: "{{base_url}}/pet")

        let store = ProjectStore.mock(projects: [originalProject], requests: [request])
        store.syncApplySaveLocalShouldFail = true

        let sync = CloudSyncService.shared
        sync.queueSaveBatchCallCount = 0

        let diff = SpecSyncDiff(
            added: [],
            removed: [
                MatchedOperation(
                    requestId: requestId.uuidString,
                    primaryKey: "listPets",
                    operation: sampleOperation(primaryKey: "listPets")
                ),
            ],
            modified: [],
            unchanged: [],
            identityChanged: []
        )

        do {
            try SpecSyncService.apply(
                diff: diff,
                selections: SpecSyncSelections(removedRequestIDs: [requestId.uuidString]),
                projectId: projectId,
                newContentFingerprint: "new",
                specBytes: Data("{\"openapi\":\"3.0.0\"}".utf8),
                store: store
            )
            Issue.record("Expected apply to throw on persist failure")
        } catch {
            #expect(store.projects.first?.specLink?.specRevision == 1)
            #expect(store.projects.first?.specLink?.contentFingerprint == "old")
            #expect(store.requests.first?.isSpecStale != true)
            #expect(sync.queueSaveBatchCallCount == 0)
            #expect(!store.syncApplyInProgress)
        }
    }

    @Test @MainActor func remoteUpsertSkippedWhenSyncApplyInProgress() {
        let store = ProjectStore.mock()
        store.syncApplyInProgress = true

        store.applyRemoteUpsert(Project(name: "Remote"))
        #expect(store.projects.isEmpty)
    }

    // MARK: - checkForUpdates

    @Test @MainActor func checkForUpdatesReturnsUpToDateWhenFingerprintMatches() async throws {
        let sourceURL = "https://example.test/petstore.yaml"
        let fixtureBytes = Data(
            """
            openapi: 3.0.3
            info:
              title: Petstore
              version: 1.0.0
            paths:
              /pet:
                get:
                  operationId: listPets
                  responses:
                    '200':
                      description: ok
            """.utf8
        )
        let parseResult = try parseSpec(
            bytes: fixtureBytes,
            sourceHint: .openApi,
            bundleEntryPath: nil,
            options: SpecParseOptions()
        )
        let fingerprint = parseResult.contentFingerprint

        let fetchService = makeMockFetchService { request in
            #expect(request.url?.absoluteString == sourceURL)
            return mockOKResponse(for: request, body: fixtureBytes)
        }
        let originalFetch = SafeFetchService.shared
        SafeFetchService.shared = fetchService
        defer { SafeFetchService.shared = originalFetch }

        let projectId = UUID()
        var project = Project(id: projectId, name: "Petstore")
        project.specLink = SpecLink(
            format: .openapi,
            source: .url,
            contentFingerprint: fingerprint,
            importedAt: Date(timeIntervalSinceReferenceDate: 1000),
            sourceURL: sourceURL,
            isDetached: false
        )
        let store = ProjectStore.mock(projects: [project])

        let outcome = try await SpecSyncService.checkForUpdates(project: project, store: store)

        #expect(outcome == .upToDate)
        let updated = try #require(store.projects.first)
        #expect(updated.specLink?.lastCheckedAt != nil)
    }

    @Test @MainActor func checkForUpdatesAllowsDetachedURLSnapshotWhenFingerprintMatches() async throws {
        let sourceURL = "https://example.test/petstore.yaml"
        let fixtureBytes = Data(
            """
            openapi: 3.0.3
            info:
              title: Petstore
              version: 1.0.0
            paths:
              /pet:
                get:
                  operationId: listPets
                  responses:
                    '200':
                      description: ok
            """.utf8
        )
        let parseResult = try parseSpec(
            bytes: fixtureBytes,
            sourceHint: .openApi,
            bundleEntryPath: nil,
            options: SpecParseOptions()
        )

        let fetchService = makeMockFetchService { request in
            #expect(request.url?.absoluteString == sourceURL)
            return mockOKResponse(for: request, body: fixtureBytes)
        }
        let originalFetch = SafeFetchService.shared
        SafeFetchService.shared = fetchService
        defer { SafeFetchService.shared = originalFetch }

        let projectId = UUID()
        var project = Project(id: projectId, name: "Detached Petstore")
        project.specLink = SpecLink(
            format: .openapi,
            source: .url,
            contentFingerprint: parseResult.contentFingerprint,
            importedAt: Date(timeIntervalSinceReferenceDate: 1000),
            sourceURL: sourceURL,
            isDetached: true
        )
        let store = ProjectStore.mock(projects: [project])

        let outcome = try await SpecSyncService.checkForUpdates(project: project, store: store)
        #expect(outcome == .upToDate)
    }

    @Test @MainActor func checkForUpdatesRejectsDetachedFileSnapshot() async {
        let projectId = UUID()
        var project = Project(id: projectId, name: "Detached File Import")
        project.specLink = SpecLink(
            format: .openapi,
            source: .file,
            contentFingerprint: "snapshot-fingerprint",
            importedAt: Date(timeIntervalSinceReferenceDate: 1000),
            isDetached: true
        )
        let store = ProjectStore.mock(projects: [project])

        do {
            _ = try await SpecSyncService.checkForUpdates(project: project, store: store)
            Issue.record("Expected checkForUpdates to reject file-only detached snapshot")
        } catch {
            let importError = SpecImportError.from(error)
            #expect(importError.kind == .invalidSpec)
        }
    }

    @Test @MainActor func applyRuleASkipsUnselectedModifiedAndAddedRows() throws {
        let tempRoot = makeTempSpecsRoot()
        defer { cleanup(tempRoot) }

        let projectId = UUID()
        let modifiedRequestId = UUID()

        var modifiedRequest = Request(id: modifiedRequestId, projectId: projectId, name: "List pets", type: .http)
        modifiedRequest.specIdentity = SpecOperationIdentity(primaryKey: "listPets")
        modifiedRequest.httpData = HttpRequestData(method: .get, url: "{{base_url}}/pet")

        var requests = [modifiedRequest]
        try SpecSnapshotService.applySnapshots(to: &requests, projectId: projectId)
        modifiedRequest = try #require(requests.first)

        let store = ProjectStore.mock(requests: [modifiedRequest])

        let addedOperation = NormalizedOperation(
            primaryKey: "createPet",
            alternateKeys: [],
            name: "Create pet",
            method: "POST",
            path: "/pet",
            deprecated: false,
            tags: [],
            protocol: .http,
            binding: nil,
            folderId: nil,
            parameters: [],
            body: .none,
            bodyCandidates: [],
            auth: nil,
            description: nil
        )

        let oldOperation = NormalizedOperation(
            primaryKey: "listPets",
            alternateKeys: [],
            name: "List pets",
            method: "GET",
            path: "/pet",
            deprecated: false,
            tags: [],
            protocol: .http,
            binding: nil,
            folderId: nil,
            parameters: [],
            body: .none,
            bodyCandidates: [],
            auth: nil,
            description: nil
        )

        let newOperation = NormalizedOperation(
            primaryKey: "listPets",
            alternateKeys: [],
            name: "List pets from spec",
            method: "GET",
            path: "/pet",
            deprecated: false,
            tags: [],
            protocol: .http,
            binding: nil,
            folderId: nil,
            parameters: [],
            body: .none,
            bodyCandidates: [],
            auth: nil,
            description: nil
        )

        let diff = SpecSyncDiff(
            added: [addedOperation],
            removed: [],
            modified: [
                OperationDiff(
                    requestId: modifiedRequestId.uuidString,
                    primaryKey: "listPets",
                    oldOperation: oldOperation,
                    newOperation: newOperation,
                    fieldDeltas: [
                        SpecFieldDelta(field: .name, oldValue: "List pets", newValue: "List pets from spec", isConflict: false),
                    ]
                ),
            ],
            unchanged: [],
            identityChanged: []
        )

        let emptyAffected = try SpecSyncService.applyRuleA(
            diff: diff,
            selections: SpecSyncSelections(),
            projectId: projectId,
            store: store
        )
        #expect(emptyAffected.isEmpty)
        #expect(store.requests.count == 1)
        #expect(store.requests.first?.name == "List pets")

        let addedOnlyAffected = try SpecSyncService.applyRuleA(
            diff: diff,
            selections: SpecSyncSelections(addedPrimaryKeys: ["createPet"]),
            projectId: projectId,
            store: store
        )
        #expect(addedOnlyAffected.count == 1)
        #expect(store.requests.count == 2)
        #expect(store.requests.first(where: { $0.id == modifiedRequestId })?.name == "List pets")
        #expect(store.requests.contains { $0.specIdentity?.primaryKey == "createPet" })

        store.requests.removeAll { $0.specIdentity?.primaryKey == "createPet" }

        let modifiedOnlyAffected = try SpecSyncService.applyRuleA(
            diff: diff,
            selections: SpecSyncSelections(modifiedRequestIDs: [modifiedRequestId.uuidString]),
            projectId: projectId,
            store: store
        )
        #expect(modifiedOnlyAffected.count == 1)
        #expect(store.requests.count == 1)
        #expect(store.requests.first?.name == "List pets from spec")
    }

    // MARK: - Helpers

    private func sampleOperation(primaryKey: String) -> NormalizedOperation {
        NormalizedOperation(
            primaryKey: primaryKey,
            alternateKeys: [],
            name: "List pets",
            method: "GET",
            path: "/pet",
            deprecated: false,
            tags: [],
            protocol: .http,
            binding: nil,
            folderId: nil,
            parameters: [],
            body: .none,
            bodyCandidates: [],
            auth: nil,
            description: nil
        )
    }

    private func makeTempSpecsRoot() -> URL {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("spec-sync-tests-\(UUID().uuidString)", isDirectory: true)
        SpecImportService.specsRootDirectoryOverride = tempRoot
        return tempRoot
    }

    private func cleanup(_ tempRoot: URL) {
        SpecImportService.specsRootDirectoryOverride = nil
        try? FileManager.default.removeItem(at: tempRoot)
    }

    private func storeCountersReset() {
        CloudSyncService.shared.lastQueueSaveBatchRecordOrder = []
    }

    @MainActor
    private func makeMockFetchService(
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> SafeFetchService {
        SpecSyncMockURLProtocol.handler = handler
        return SafeFetchService(
            resolver: SpecSyncMockHostResolver(mapping: ["example.test": ["93.184.216.34"]]),
            protocolClasses: [SpecSyncMockURLProtocol.self]
        )
    }
}

private struct SpecSyncMockHostResolver: HostResolving {
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

private final class SpecSyncMockURLProtocol: URLProtocol, @unchecked Sendable {
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