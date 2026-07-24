//
//  CloudSyncRecordsTests.swift
//  ReqeastTests
//

import CloudKit
import Foundation
import Testing
@testable import Reqeast

@Suite("CloudSyncRecords", .serialized)
struct CloudSyncRecordsTests {

    // MARK: - parseRecordName

    @Test @MainActor func parseValidProjectRecordName() {
        let service = CloudSyncService.shared
        let id = UUID()
        let result = service.parseRecordName("Project/\(id.uuidString)")
        #expect(result?.type == .project)
        #expect(result?.id == id)
    }

    @Test @MainActor func parseAllRecordTypes() {
        let service = CloudSyncService.shared
        let id = UUID()
        let cases: [(String, SyncRecordType)] = [
            ("Project", .project),
            ("ProjectFolder", .projectFolder),
            ("Request", .request),
            ("RequestFolder", .requestFolder),
            ("ApiEnvironment", .apiEnvironment),
            ("SpecDocument", .specDocument),
            ("ProtoBundle", .protoBundle),
        ]
        for (name, expectedType) in cases {
            let result = service.parseRecordName("\(name)/\(id.uuidString)")
            #expect(result?.type == expectedType, "Failed for \(name)")
            #expect(result?.id == id, "Failed for \(name)")
        }
    }

    @Test @MainActor func parseInvalidUUIDReturnsNil() {
        let service = CloudSyncService.shared
        let result = service.parseRecordName("Project/not-a-uuid")
        #expect(result == nil)
    }

    @Test @MainActor func parseMissingSlashReturnsNil() {
        let service = CloudSyncService.shared
        #expect(service.parseRecordName("ProjectNoSlash") == nil)
    }

    @Test @MainActor func parseEmptyStringReturnsNil() {
        let service = CloudSyncService.shared
        #expect(service.parseRecordName("") == nil)
    }

    @Test @MainActor func parseUnknownTypeReturnsNil() {
        let service = CloudSyncService.shared
        let id = UUID()
        #expect(service.parseRecordName("UnknownType/\(id.uuidString)") == nil)
    }

    @Test @MainActor func parseExtraSlashesReturnsNil() {
        let service = CloudSyncService.shared
        // maxSplits: 1 means second part is "sub/path" which is not a valid UUID
        #expect(service.parseRecordName("Project/sub/path") == nil)
    }

    // MARK: - Conflict Resolution

    @Test @MainActor func localNewerWins() {
        let local = Self.makeTimestampData(date: Date(timeIntervalSince1970: 2000))
        let server = Self.makeTimestampData(date: Date(timeIntervalSince1970: 1000))
        #expect(CloudSyncService.localIsNewer(localData: local, serverData: server) == .localNewer)
    }

    @Test @MainActor func serverNewerWins() {
        let local = Self.makeTimestampData(date: Date(timeIntervalSince1970: 1000))
        let server = Self.makeTimestampData(date: Date(timeIntervalSince1970: 2000))
        #expect(CloudSyncService.localIsNewer(localData: local, serverData: server) == .serverNewer)
    }

    @Test @MainActor func equalTimestampsServerWins() {
        let timestamp = Date(timeIntervalSince1970: 1000)
        let local = Self.makeTimestampData(date: timestamp)
        let server = Self.makeTimestampData(date: timestamp)
        // Strict `>`: equal timestamps fall to serverNewer.
        #expect(CloudSyncService.localIsNewer(localData: local, serverData: server) == .serverNewer)
    }

    @Test @MainActor func malformedLocalIsUndecidable() {
        let local = Data("not json".utf8)
        let server = Self.makeTimestampData(date: Date(timeIntervalSince1970: 1000))
        let outcome = CloudSyncService.localIsNewer(localData: local, serverData: server)
        if case .undecidable = outcome { } else { Issue.record("Expected .undecidable, got \(outcome)") }
    }

    @Test @MainActor func malformedServerIsUndecidable() {
        let local = Self.makeTimestampData(date: Date(timeIntervalSince1970: 1000))
        let server = Data("not json".utf8)
        let outcome = CloudSyncService.localIsNewer(localData: local, serverData: server)
        if case .undecidable = outcome { } else { Issue.record("Expected .undecidable, got \(outcome)") }
    }

    @Test @MainActor func bothMalformedIsUndecidable() {
        let local = Data("bad".utf8)
        let server = Data("bad".utf8)
        let outcome = CloudSyncService.localIsNewer(localData: local, serverData: server)
        if case .undecidable = outcome { } else { Issue.record("Expected .undecidable, got \(outcome)") }
    }

    private static func makeTimestampData(date: Date) -> Data {
        struct TimestampOnly: Encodable {
            let updatedAt: Date
        }
        return try! JSONEncoder().encode(TimestampOnly(updatedAt: date))
    }

    // MARK: - Conflict Resolution via CKRecord field

    @Test @MainActor func fieldBasedLocalNewerWins() {
        let local = Self.makeRecord(updatedAt: Date(timeIntervalSince1970: 2000))
        let server = Self.makeRecord(updatedAt: Date(timeIntervalSince1970: 1000))
        #expect(CloudSyncService.localIsNewer(localRecord: local, serverRecord: server) == .localNewer)
    }

    @Test @MainActor func fieldBasedServerNewerWins() {
        let local = Self.makeRecord(updatedAt: Date(timeIntervalSince1970: 1000))
        let server = Self.makeRecord(updatedAt: Date(timeIntervalSince1970: 2000))
        #expect(CloudSyncService.localIsNewer(localRecord: local, serverRecord: server) == .serverNewer)
    }

    @Test @MainActor func fieldBasedEqualTimestampsServerWins() {
        let timestamp = Date(timeIntervalSince1970: 1000)
        let local = Self.makeRecord(updatedAt: timestamp)
        let server = Self.makeRecord(updatedAt: timestamp)
        #expect(CloudSyncService.localIsNewer(localRecord: local, serverRecord: server) == .serverNewer)
    }

    @Test @MainActor func fieldBasedMissingLocalFieldIsUndecidable() {
        let local = CKRecord(recordType: "Project", recordID: Self.recordID())
        let server = Self.makeRecord(updatedAt: Date(timeIntervalSince1970: 1000))
        let outcome = CloudSyncService.localIsNewer(localRecord: local, serverRecord: server)
        if case .undecidable = outcome { } else { Issue.record("Expected .undecidable, got \(outcome)") }
    }

    @Test @MainActor func fieldBasedMissingServerFieldIsUndecidable() {
        let local = Self.makeRecord(updatedAt: Date(timeIntervalSince1970: 1000))
        let server = CKRecord(recordType: "Project", recordID: Self.recordID())
        let outcome = CloudSyncService.localIsNewer(localRecord: local, serverRecord: server)
        if case .undecidable = outcome { } else { Issue.record("Expected .undecidable, got \(outcome)") }
    }

    private static func recordID() -> CKRecord.ID {
        CKRecord.ID(recordName: "Project/\(UUID().uuidString)", zoneID: CKRecordZone.ID(zoneName: "Reqeast"))
    }

    private static func makeRecord(updatedAt: Date) -> CKRecord {
        let record = CKRecord(recordType: "Project", recordID: recordID())
        record["updatedAt"] = updatedAt as NSDate
        return record
    }

    // MARK: - resolveConflict fallback

    @Test @MainActor func resolveConflictServerMissingDataFavorsLocal() {
        let service = CloudSyncService.shared
        let local = CKRecord(recordType: "Project", recordID: Self.recordID())
        let server = CKRecord(recordType: "Project", recordID: Self.recordID())
        // Neither side has updatedAt field; server also missing data blob.
        local["data"] = Self.timestampBlob(Date(timeIntervalSince1970: 100)) as NSData
        #expect(service.resolveConflict(localRecord: local, serverRecord: server) == .localNewer)
    }

    @Test @MainActor func resolveConflictServerMissingDataReportsError() {
        let service = CloudSyncService.shared
        service.syncState.clearError()
        let local = CKRecord(recordType: "Project", recordID: Self.recordID())
        let server = CKRecord(recordType: "Project", recordID: Self.recordID())
        local["data"] = Self.timestampBlob(Date(timeIntervalSince1970: 100)) as NSData
        _ = service.resolveConflict(localRecord: local, serverRecord: server)
        #expect(service.syncState.currentError?.kind == .cloudConflictUnresolvable)
    }

    @Test @MainActor func resolveConflictBothMissingDataReturnsUndecidable() {
        let service = CloudSyncService.shared
        let local = CKRecord(recordType: "Project", recordID: Self.recordID())
        let server = CKRecord(recordType: "Project", recordID: Self.recordID())
        let outcome = service.resolveConflict(localRecord: local, serverRecord: server)
        if case .undecidable = outcome { } else { Issue.record("Expected .undecidable, got \(outcome)") }
    }

    @Test @MainActor func resolveConflictJsonFallbackWhenFieldMissing() {
        let service = CloudSyncService.shared
        let local = CKRecord(recordType: "Project", recordID: Self.recordID())
        let server = CKRecord(recordType: "Project", recordID: Self.recordID())
        local["data"] = Self.timestampBlob(Date(timeIntervalSince1970: 2000)) as NSData
        server["data"] = Self.timestampBlob(Date(timeIntervalSince1970: 1000)) as NSData
        #expect(service.resolveConflict(localRecord: local, serverRecord: server) == .localNewer)
    }

    private static func timestampBlob(_ date: Date) -> Data {
        struct TimestampOnly: Encodable { let updatedAt: Date }
        return try! JSONEncoder().encode(TimestampOnly(updatedAt: date))
    }

    // MARK: - Oversized record rejection

    @Test @MainActor func oversizedRequestBodyReturnsNilAndReportsError() {
        let service = CloudSyncService.shared
        service.syncState.clearError()
        let oversized = String(repeating: "a", count: 950_000)
        var request = Request(projectId: UUID(), name: "big")
        request.httpData?.bodyContent = oversized
        request.updatedAt = Date()
        let record = service.buildRecord(for: request)
        #expect(record == nil)
        #expect(service.syncState.currentError?.kind == .cloudRecordTooLarge)
    }

    @Test @MainActor func normalSizedRecordStillBuilds() {
        let service = CloudSyncService.shared
        service.syncState.clearError()
        var request = Request(projectId: UUID(), name: "small")
        request.httpData?.bodyContent = "small body"
        request.updatedAt = Date()
        let record = service.buildRecord(for: request)
        #expect(record != nil)
        #expect(service.syncState.currentError == nil)
    }

    @Test @MainActor func oversizedRecordGetsTombstoned() {
        let service = CloudSyncService.shared
        service.syncState.clearError()
        service.oversizedRecordIDs.removeAll()
        let oversized = String(repeating: "a", count: 950_000)
        var request = Request(projectId: UUID(), name: "big")
        request.httpData?.bodyContent = oversized
        request.updatedAt = Date()
        _ = service.buildRecord(for: request)
        let expectedName = "Request/\(request.id.uuidString)"
        #expect(service.oversizedRecordIDs.contains(expectedName))
    }

    @Test @MainActor func shouldRequeueBlocksOversizedRecord() {
        let name = "Request/abc"
        let result = CloudSyncService.shouldRequeueUnconfirmed(
            recordName: name,
            confirmedRecordNames: [],
            oversizedRecordIDs: [name],
            dirtyRecordIDs: []
        )
        #expect(result == false)
    }

    @Test @MainActor func shouldRequeueBlocksConfirmedRecord() {
        let name = "Request/abc"
        let result = CloudSyncService.shouldRequeueUnconfirmed(
            recordName: name,
            confirmedRecordNames: [name],
            oversizedRecordIDs: [],
            dirtyRecordIDs: []
        )
        #expect(result == false)
    }

    @Test @MainActor func shouldRequeueAllowsUnconfirmedRecord() {
        let result = CloudSyncService.shouldRequeueUnconfirmed(
            recordName: "Request/abc",
            confirmedRecordNames: [],
            oversizedRecordIDs: [],
            dirtyRecordIDs: []
        )
        #expect(result == true)
    }

    @Test @MainActor func shouldRequeueBlocksWhenBothOversizedAndConfirmed() {
        let name = "Request/abc"
        let result = CloudSyncService.shouldRequeueUnconfirmed(
            recordName: name,
            confirmedRecordNames: [name],
            oversizedRecordIDs: [name],
            dirtyRecordIDs: []
        )
        #expect(result == false)
    }

    @Test @MainActor func shouldRequeueDirtyConfirmedRecord() {
        let name = "Request/abc"
        let result = CloudSyncService.shouldRequeueUnconfirmed(
            recordName: name,
            confirmedRecordNames: [name],
            oversizedRecordIDs: [],
            dirtyRecordIDs: [name]
        )
        #expect(result == true)
    }

    @Test @MainActor func shouldRequeueOversizedBeatsDirty() {
        let name = "Request/abc"
        let result = CloudSyncService.shouldRequeueUnconfirmed(
            recordName: name,
            confirmedRecordNames: [name],
            oversizedRecordIDs: [name],
            dirtyRecordIDs: [name]
        )
        #expect(result == false)
    }

    @Test @MainActor func resetOversizedRecordIDsClearsMemoryAndStorage() {
        let service = CloudSyncService.shared
        service.oversizedRecordIDs.insert("Request/reset-test")
        service.persistOversizedRecordIDs()
        #expect(service.storage.data(forKey: CloudSyncService.oversizedRecordsKey) != nil)
        service.resetOversizedRecordIDs()
        #expect(service.oversizedRecordIDs.isEmpty)
        #expect(service.storage.data(forKey: CloudSyncService.oversizedRecordsKey) == nil)
    }

    @Test @MainActor func queueSaveClearsOversizedTombstone() {
        let service = CloudSyncService.shared
        service.syncState.clearError()
        service.oversizedRecordIDs.removeAll()
        var request = Request(projectId: UUID(), name: "will-shrink")
        request.updatedAt = Date()
        let name = "Request/\(request.id.uuidString)"
        service.oversizedRecordIDs.insert(name)
        service.queueSave(request)
        #expect(!service.oversizedRecordIDs.contains(name))
    }

    // MARK: - queueSaveBatch

    @Test @MainActor func queueSaveBatchMarksAllItemsDirty() {
        let service = CloudSyncService.shared
        let dirtyBefore = service.dirtyRecordIDs

        let project = Project(name: "imported")
        let projectId = project.id
        let projectFolder = ProjectFolder(name: "pf")
        let requestFolder = RequestFolder(projectId: projectId, name: "rf")
        let requests = [
            Request(projectId: projectId, name: "one"),
            Request(projectId: projectId, name: "two"),
        ]
        let environment = ApiEnvironment(projectId: projectId, name: "prod")

        service.queueSaveBatch(
            project: project,
            projectFolders: [projectFolder],
            folders: [requestFolder],
            requests: requests,
            environments: [environment]
        )

        let expectedNames: Set<String> = [
            "Project/\(project.id.uuidString)",
            "ProjectFolder/\(projectFolder.id.uuidString)",
            "RequestFolder/\(requestFolder.id.uuidString)",
            "Request/\(requests[0].id.uuidString)",
            "Request/\(requests[1].id.uuidString)",
            "ApiEnvironment/\(environment.id.uuidString)",
        ]
        let newlyDirty = service.dirtyRecordIDs.subtracting(dirtyBefore)
        #expect(newlyDirty == expectedNames)
    }

    @Test @MainActor func queueSaveBatchClearsOversizedTombstones() {
        let service = CloudSyncService.shared
        service.oversizedRecordIDs.removeAll()

        let project = Project(name: "imported")
        let projectId = project.id
        let request = Request(projectId: projectId, name: "one")
        let names = [
            "Project/\(project.id.uuidString)",
            "Request/\(request.id.uuidString)",
        ]
        for name in names {
            service.oversizedRecordIDs.insert(name)
        }

        service.queueSaveBatch(project: project, requests: [request])

        for name in names {
            #expect(!service.oversizedRecordIDs.contains(name))
        }
    }

    @Test @MainActor func queueSaveBatchEmptyArgumentsDoNotCrash() {
        let service = CloudSyncService.shared
        service.queueSaveBatch()
        service.queueSaveBatch(project: nil, projectFolders: [], folders: [], requests: [], environments: [])
    }

    @Test @MainActor func queueSaveBatchQueuesChildrenBeforeProject() {
        let service = CloudSyncService.shared
        service.lastQueueSaveBatchRecordOrder = []

        let project = Project(name: "imported")
        let projectId = project.id
        let projectFolder = ProjectFolder(name: "pf")
        let requestFolder = RequestFolder(projectId: projectId, name: "rf")
        let request = Request(projectId: projectId, name: "one")
        let environment = ApiEnvironment(projectId: projectId, name: "prod")
        let protoBundle = ProtoBundle(
            projectId: projectId,
            name: "Greeter",
            contentFingerprint: "fp",
            entryFile: "hello.proto",
            fileCount: 1
        )

        service.queueSaveBatch(
            project: project,
            projectFolders: [projectFolder],
            folders: [requestFolder],
            requests: [request],
            environments: [environment],
            protoBundles: [protoBundle]
        )

        let expectedOrder = [
            "ProjectFolder/\(projectFolder.id.uuidString)",
            "RequestFolder/\(requestFolder.id.uuidString)",
            "Request/\(request.id.uuidString)",
            "ApiEnvironment/\(environment.id.uuidString)",
            "ProtoBundle/\(protoBundle.id.uuidString)",
            "Project/\(project.id.uuidString)",
        ]
        #expect(service.lastQueueSaveBatchRecordOrder == expectedOrder)
    }

    // MARK: - SpecDocument CKAsset

    @Test @MainActor func specDocumentUploadsAssetOnFingerprintChange() throws {
        let service = CloudSyncService.shared
        let tempRoot = try Self.makeTempSpecsRoot()
        defer { Self.cleanup(tempRoot) }

        let projectId = UUID()
        try Self.writeSpecFile(
            projectId: projectId,
            fileName: "spec.yaml",
            contents: "openapi: 3.0.0\n"
        )

        var document = Self.makeSpecDocument(
            projectId: projectId,
            fingerprint: "fingerprint-a",
            fileName: "spec.yaml"
        )
        let first = try #require(service.buildRecord(for: document))
        #expect(first[SpecDocument.ckAssetField] as? CKAsset != nil)

        document.lastUploadedFingerprint = "fingerprint-a"
        document.contentFingerprint = "fingerprint-b"
        let second = try #require(service.buildRecord(for: document))
        #expect(second[SpecDocument.ckAssetField] as? CKAsset != nil)
        #expect(second[SpecDocument.fingerprintField] as? String == "fingerprint-b")
    }

    @Test @MainActor func specDocumentSkipsAssetUploadWhenFingerprintUnchanged() throws {
        let service = CloudSyncService.shared
        let tempRoot = try Self.makeTempSpecsRoot()
        defer { Self.cleanup(tempRoot) }

        let projectId = UUID()
        try Self.writeSpecFile(
            projectId: projectId,
            fileName: "spec.yaml",
            contents: "openapi: 3.0.0\n"
        )

        let document = Self.makeSpecDocument(
            projectId: projectId,
            fingerprint: "same-fingerprint",
            fileName: "spec.yaml"
        )

        var uploaded = document
        uploaded.lastUploadedFingerprint = "same-fingerprint"
        #expect(service.shouldUploadSpecAsset(for: uploaded) == false)

        let record = try #require(service.buildRecord(for: uploaded))
        #expect(record[SpecDocument.ckAssetField] as? CKAsset == nil)
    }

    @Test @MainActor func specDocumentDetachedDeletesAssetField() throws {
        let service = CloudSyncService.shared
        let tempRoot = try Self.makeTempSpecsRoot()
        defer { Self.cleanup(tempRoot) }

        let projectId = UUID()
        try Self.writeSpecFile(
            projectId: projectId,
            fileName: "spec.yaml",
            contents: "openapi: 3.0.0\n"
        )

        var document = Self.makeSpecDocument(
            projectId: projectId,
            fingerprint: "fingerprint-a",
            fileName: "spec.yaml",
            isDetached: false
        )
        let linked = try #require(service.buildRecord(for: document))
        #expect(linked[SpecDocument.ckAssetField] as? CKAsset != nil)
        service.cacheSystemFields(of: linked)

        document.isDetached = true
        let detached = try #require(service.buildRecord(for: document))
        #expect(detached[SpecDocument.ckAssetField] == nil)
    }

    @Test @MainActor func specDocumentInternalSkipsAssetUpload() throws {
        let service = CloudSyncService.shared
        let tempRoot = try Self.makeTempSpecsRoot()
        defer { Self.cleanup(tempRoot) }

        let projectId = UUID()
        try Self.writeSpecFile(
            projectId: projectId,
            fileName: "spec.yaml",
            contents: "openapi: 3.0.0\n"
        )

        let document = Self.makeSpecDocument(
            projectId: projectId,
            fingerprint: "fingerprint-a",
            fileName: "spec.yaml",
            classification: .internal,
            sourceURL: "https://corp.example/internal/openapi.yaml"
        )

        let record = try #require(service.buildRecord(for: document))
        #expect(record[SpecDocument.ckAssetField] as? CKAsset == nil)

        let payload = try #require(record["data"] as? Data)
        let decoded = try JSONDecoder().decode(SpecDocument.self, from: payload)
        #expect(decoded.sourceURL == nil)
        #expect(decoded.classification == .internal)
    }

    @Test @MainActor func specDocumentFetchWritesAssetToSpecDirectory() throws {
        let service = CloudSyncService.shared
        let tempRoot = try Self.makeTempSpecsRoot()
        defer { Self.cleanup(tempRoot) }

        let projectId = UUID()
        let assetTemp = tempRoot.appendingPathComponent("asset-\(UUID().uuidString).yaml")
        let specBytes = Data("openapi: 3.0.3\ninfo:\n  title: Petstore\n".utf8)
        try specBytes.write(to: assetTemp)

        let document = Self.makeSpecDocument(
            projectId: projectId,
            fingerprint: "remote-fingerprint",
            fileName: "spec.yaml"
        )

        let record = CKRecord(recordType: "SpecDocument", recordID: service.recordID(for: document))
        record["data"] = try JSONEncoder().encode(document) as NSData
        record["updatedAt"] = document.updatedAt as NSDate
        record[SpecDocument.fingerprintField] = document.contentFingerprint as NSString
        record[SpecDocument.ckAssetField] = CKAsset(fileURL: assetTemp)

        let store = ProjectStore.mock()
        #expect(service.applySpecDocumentUpsert(record: record, store: store))

        let specURL = SpecImportService.specsDirectory(for: projectId).appendingPathComponent("spec.yaml")
        let fingerprintURL = SpecImportService.specsDirectory(for: projectId).appendingPathComponent("fingerprint.txt")
        #expect(FileManager.default.fileExists(atPath: specURL.path))
        #expect(try String(contentsOf: fingerprintURL, encoding: .utf8) == "remote-fingerprint")
        #expect(store.specDocuments.first?.assetHydrated == true)
    }

    @Test @MainActor func specDocumentFetchWithoutAssetRefetchesFromSourceURL() async throws {
        let service = CloudSyncService.shared
        let tempRoot = try Self.makeTempSpecsRoot()
        defer { Self.cleanup(tempRoot) }

        let projectId = UUID()
        let bytes = Data("openapi: 3.0.3\ninfo:\n  title: Petstore\n".utf8)
        let fingerprint = canonicalFingerprint(resolvedBytes: bytes)
        let sourceURL = "https://example.test/openapi.yaml"

        let fetchService = Self.makeMockFetchService { request in
            Self.mockOKResponse(for: request, body: bytes)
        }
        let originalFetch = SafeFetchService.shared
        SafeFetchService.shared = fetchService
        defer { SafeFetchService.shared = originalFetch }

        let document = Self.makeSpecDocument(
            projectId: projectId,
            fingerprint: fingerprint,
            fileName: "spec.yaml",
            sourceURL: sourceURL,
            assetHydrated: false
        )

        let record = CKRecord(recordType: "SpecDocument", recordID: service.recordID(for: document))
        record["data"] = try JSONEncoder().encode(document) as NSData
        record["updatedAt"] = document.updatedAt as NSDate

        var project = Project(name: "Linked")
        project.id = projectId
        project.specLink = SpecLink(
            format: .openapi,
            source: .url,
            contentFingerprint: fingerprint,
            importedAt: Date(),
            sourceURL: sourceURL,
            isDetached: false
        )
        let store = ProjectStore.mock(projects: [project])

        #expect(service.applySpecDocumentUpsert(record: record, store: store))
        let hydrationTask = service.scheduleSpecBytesHydrationFallbackIfNeeded(
            recordId: document.id,
            store: store
        )
        await hydrationTask?.value

        let applied = try #require(store.specDocuments.first)
        #expect(applied.assetHydrated == true)
        #expect(store.isSpecProjectReadOnly(projectId: projectId) == false)

        let specURL = SpecImportService.specsDirectory(for: projectId).appendingPathComponent("spec.yaml")
        #expect(FileManager.default.fileExists(atPath: specURL.path))
        #expect(try Data(contentsOf: specURL) == bytes)
    }

    @Test @MainActor func specDocumentFetchWithoutAssetMarksReadOnlyWhenDiskMissing() throws {
        let service = CloudSyncService.shared
        let tempRoot = try Self.makeTempSpecsRoot()
        defer { Self.cleanup(tempRoot) }

        let projectId = UUID()
        let document = Self.makeSpecDocument(
            projectId: projectId,
            fingerprint: "remote-fingerprint",
            fileName: "spec.yaml",
            assetHydrated: true
        )

        let record = CKRecord(recordType: "SpecDocument", recordID: service.recordID(for: document))
        record["data"] = try JSONEncoder().encode(document) as NSData
        record["updatedAt"] = document.updatedAt as NSDate

        var project = Project(name: "Linked")
        project.id = projectId
        project.specLink = SpecLink(
            format: .openapi,
            source: .url,
            contentFingerprint: "remote-fingerprint",
            importedAt: Date(),
            sourceURL: "https://example.com/openapi.yaml",
            isDetached: false
        )
        let store = ProjectStore.mock(projects: [project])

        #expect(service.applySpecDocumentUpsert(record: record, store: store))
        let applied = try #require(store.specDocuments.first)
        #expect(applied.assetHydrated == false)
        #expect(applied.isReadOnlyDueToMissingAsset == true)
        #expect(store.isSpecProjectReadOnly(projectId: projectId) == true)
    }

    private static func makeSpecDocument(
        projectId: UUID,
        fingerprint: String,
        fileName: String,
        classification: SpecClassification = .standard,
        sourceURL: String? = "https://example.com/openapi.yaml",
        isDetached: Bool = false,
        assetHydrated: Bool = true
    ) -> SpecDocument {
        SpecDocument(
            id: projectId,
            projectId: projectId,
            contentFingerprint: fingerprint,
            specFileName: fileName,
            sourceURL: sourceURL,
            classification: classification,
            isDetached: isDetached,
            assetHydrated: assetHydrated,
            updatedAt: Date()
        )
    }

    private static func makeTempSpecsRoot() throws -> URL {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("cloud-sync-spec-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        SpecImportService.specsRootDirectoryOverride = tempRoot
        return tempRoot
    }

    private static func cleanup(_ tempRoot: URL) {
        SpecImportService.specsRootDirectoryOverride = nil
        try? FileManager.default.removeItem(at: tempRoot)
    }

    @MainActor
    private static func makeMockFetchService(
        handler: @escaping @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    ) -> SafeFetchService {
        CloudSyncMockURLProtocol.handler = handler
        return SafeFetchService(
            resolver: CloudSyncMockHostResolver(mapping: ["example.test": ["93.184.216.34"]]),
            protocolClasses: [CloudSyncMockURLProtocol.self]
        )
    }

    nonisolated private static func mockOKResponse(for request: URLRequest, body: Data) -> (HTTPURLResponse, Data) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return (response, body)
    }

    private static func writeSpecFile(projectId: UUID, fileName: String, contents: String) throws {
        let projectDir = SpecImportService.specsDirectory(for: projectId)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        let specURL = projectDir.appendingPathComponent(fileName)
        try contents.write(to: specURL, atomically: true, encoding: .utf8)
    }
}

private struct CloudSyncMockHostResolver: HostResolving {
    let mapping: [String: [String]]

    func resolve(hostname: String) throws -> [String] {
        guard let addresses = mapping[hostname] else {
            throw SafeFetchError.dnsResolutionFailed(hostname)
        }
        return addresses
    }
}

private final class CloudSyncMockURLProtocol: URLProtocol, @unchecked Sendable {
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
