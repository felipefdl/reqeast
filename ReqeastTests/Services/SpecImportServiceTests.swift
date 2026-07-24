//
//  SpecImportServiceTests.swift
//  ReqeastTests
//

import Foundation
import Testing
@testable import Reqeast

@Suite("SpecImportService", .serialized)
struct SpecImportServiceTests {

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

    // MARK: - Preview

    @Test func previewParsesAndMapsWithoutStoreMutation() async throws {
        let store = await ProjectStore.mock()
        let bytes = try fixtureBytes(named: "petstore-3.1", preferJSON: false)

        let preview = try await SpecImportService.preview(
            bytes: bytes,
            sourceHint: .yaml,
            source: .file
        )

        #expect(preview.projectName == "OpenAPI 3.1 Petstore")
        #expect(preview.operationCount == 4)
        #expect(preview.mapped.requests.count == 4)
        #expect(preview.mapped.folders.count == 2)
        #expect(preview.mapped.environments.count == 1)
        #expect(!preview.contentFingerprint.isEmpty)
        #expect(preview.specFileName == "spec.yaml")
        #expect(preview.format == .openapi)
        #expect(preview.source == .file)
        #expect(preview.mapped.project.specLink == nil)

        await #expect(store.projects.isEmpty)
        await #expect(store.requests.isEmpty)
    }

    @Test func previewDetectsPostmanCollectionFormat() async throws {
        let bytes = try fixtureBytes(named: "postman-nested", preferJSON: true)

        let preview = try await SpecImportService.preview(
            bytes: bytes,
            sourceHint: .json,
            source: .paste
        )

        #expect(preview.format == .postman)
        #expect(preview.sourceHint == .postman)
        #expect(preview.projectName == "Nested Postman API")
        #expect(preview.operationCount == 3)
        #expect(preview.specFileName == "spec.json")
    }

    @Test @MainActor func commitPostmanImportStoresPostmanSpecLink() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("spec-import-tests-\(UUID().uuidString)", isDirectory: true)
        SpecImportService.specsRootDirectoryOverride = tempRoot
        defer {
            SpecImportService.specsRootDirectoryOverride = nil
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let store = ProjectStore.mock()
        let bytes = try fixtureBytes(named: "postman-vars", preferJSON: true)
        let preview = try await SpecImportService.preview(
            bytes: bytes,
            sourceHint: .json,
            source: .file
        )

        try SpecImportService.commit(preview: preview, to: store)

        let project = try #require(store.projects.first)
        #expect(project.specLink?.format == .postman)
        #expect(store.projects.count == 1)
    }

    @Test func previewUsesJsonFileNameForJsonHint() async throws {
        let bytes = try fixtureBytes(named: "petstore-3.1", preferJSON: true)

        let preview = try await SpecImportService.preview(
            bytes: bytes,
            sourceHint: .json,
            source: .paste
        )

        #expect(preview.specFileName == "spec.json")
        #expect(preview.source == .paste)
    }

    @Test @MainActor func commitGitHTTPSStoresGitRefOnLinkedSpec() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("spec-import-tests-\(UUID().uuidString)", isDirectory: true)
        SpecImportService.specsRootDirectoryOverride = tempRoot
        defer {
            SpecImportService.specsRootDirectoryOverride = nil
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let store = ProjectStore.mock()
        let bytes = try fixtureBytes(named: "petstore-3.1", preferJSON: false)
        let gitRef = GitSourceRef(
            provider: .github,
            owner: "acme",
            repo: "api",
            ref: "main",
            path: "openapi.yaml",
            tokenKey: "github:acme"
        )
        var preview = try await SpecImportService.preview(
            SpecImportRequest(
                bytes: bytes,
                sourceHint: .yaml,
                source: .gitHTTPS,
                sourceURL: "https://raw.githubusercontent.com/acme/api/main/openapi.yaml",
                gitRef: gitRef
            ),
            options: SpecImportOptions(linkToSpec: .linked)
        )
        preview.projectName = "Git Petstore"

        try SpecImportService.commit(preview: preview, to: store)

        let project = try #require(store.projects.first)
        #expect(project.specLink?.source == .gitHTTPS)
        #expect(project.specLink?.sourceURL == "https://raw.githubusercontent.com/acme/api/main/openapi.yaml")
        #expect(project.specLink?.gitRef?.owner == "acme")
        #expect(project.specLink?.gitRef?.path == "openapi.yaml")
        #expect(project.specLink?.isDetached == false)
    }

    @Test func previewInvalidSpecThrowsSpecImportError() async {
        do {
            _ = try await SpecImportService.preview(
                bytes: Data("{not json".utf8),
                sourceHint: .json,
                source: .paste
            )
            Issue.record("expected preview to throw")
        } catch {
            let mapped = SpecImportError.from(error)
            #expect(mapped.kind == .parseError)
        }
    }

    // MARK: - Commit

    @Test @MainActor func commitWritesSpecToDiskAndImportsProject() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("spec-import-tests-\(UUID().uuidString)", isDirectory: true)
        SpecImportService.specsRootDirectoryOverride = tempRoot
        defer {
            SpecImportService.specsRootDirectoryOverride = nil
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let store = ProjectStore.mock()
        let bytes = try fixtureBytes(named: "petstore-3.1", preferJSON: false)
        var preview = try await SpecImportService.preview(
            bytes: bytes,
            sourceHint: .yaml,
            source: .file
        )
        preview.projectName = "My Petstore API"

        try SpecImportService.commit(preview: preview, to: store)

        let projectDir = SpecImportService.specsDirectory(for: preview.projectId)
        let specURL = projectDir.appendingPathComponent("spec.yaml")
        let fingerprintURL = projectDir.appendingPathComponent("fingerprint.txt")

        #expect(FileManager.default.fileExists(atPath: specURL.path))
        #expect(FileManager.default.fileExists(atPath: fingerprintURL.path))

        let writtenBytes = try Data(contentsOf: specURL)
        #expect(writtenBytes == bytes)

        let writtenFingerprint = try String(contentsOf: fingerprintURL, encoding: .utf8)
        #expect(writtenFingerprint == preview.contentFingerprint)

        #expect(store.projects.count == 1)
        let project = try #require(store.projects.first)
        #expect(project.name == "My Petstore API")
        #expect(project.specLink?.format == .openapi)
        #expect(project.specLink?.source == .file)
        #expect(project.specLink?.contentFingerprint == preview.contentFingerprint)
        #expect(project.specLink?.isDetached == true)
        #expect(project.specLink?.specRevision == 0)
        #expect(project.specLink?.sourceURL == nil)

        #expect(store.requests.count == 4)
        #expect(store.requestFolders.count == 2)
        #expect(store.environments.count == 1)

        let snapshotsDir = projectDir.appendingPathComponent("snapshots", isDirectory: true)
        #expect(FileManager.default.fileExists(atPath: snapshotsDir.path))

        for request in store.requests where request.type == .http {
            #expect(request.specFieldFingerprint?.count == 64)
            #expect(request.specSnapshotPayload != nil)
            #expect(request.specLastSyncedAt != nil)

            let snapshotURL = snapshotsDir.appendingPathComponent("\(request.id.uuidString).json")
            #expect(FileManager.default.fileExists(atPath: snapshotURL.path))

            let diskSnapshot = SpecSnapshotService.readSnapshotFromDisk(
                projectId: preview.projectId,
                requestId: request.id
            )
            let httpData = try #require(request.httpData)
            #expect(diskSnapshot == SpecSnapshotService.makeSnapshot(from: httpData))
        }
    }

    @Test @MainActor func mergePreviewWarnsOnDuplicateOperations() async throws {
        let store = ProjectStore.mock()
        let existingProject = Project(name: "Petstore")
        let projectId = existingProject.id
        let existingRequest = Request(projectId: projectId, name: "List pets")
        var withIdentity = existingRequest
        withIdentity.specIdentity = SpecOperationIdentity(primaryKey: "listPets")
        store.projects.append(existingProject)
        store.requests.append(withIdentity)

        let bytes = try fixtureBytes(named: "petstore-3.1", preferJSON: false)
        let preview = try await SpecImportService.preview(
            bytes: bytes,
            sourceHint: .yaml,
            source: .file
        )

        let mergePreview = SpecImportService.mergePreview(
            preview: preview,
            in: store,
            targetProjectId: projectId
        )

        let info = try #require(mergePreview)
        #expect(info.duplicateWarnings.contains { $0.code == "DUPLICATE_OPERATION" })
        #expect(info.importableOperationCount < preview.operationCount)
    }

    @Test @MainActor func commitMergeAppendsRequestsAndMergesFoldersByName() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("spec-import-tests-\(UUID().uuidString)", isDirectory: true)
        SpecImportService.specsRootDirectoryOverride = tempRoot
        defer {
            SpecImportService.specsRootDirectoryOverride = nil
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let store = ProjectStore.mock()
        let existingProject = Project(name: "Petstore")
        let projectId = existingProject.id
        let petFolder = RequestFolder(projectId: projectId, name: "pet")
        var existingRequest = Request(projectId: projectId, name: "List pets", folderId: petFolder.id)
        existingRequest.specIdentity = SpecOperationIdentity(primaryKey: "listPets")
        store.projects.append(existingProject)
        store.requestFolders.append(petFolder)
        store.requests.append(existingRequest)

        let bytes = try fixtureBytes(named: "petstore-3.1", preferJSON: false)
        let preview = try await SpecImportService.preview(
            bytes: bytes,
            sourceHint: .yaml,
            source: .file
        )

        try SpecImportService.commit(
            preview: preview,
            to: store,
            importTarget: .existingProject,
            targetProjectId: projectId
        )

        #expect(store.projects.count == 1)
        #expect(store.projects.first?.specLink?.format == .openapi)
        #expect(store.requests(for: projectId).count == 4)
        #expect(store.requestFolders(for: projectId).count == 2)
        #expect(store.requestFolders(for: projectId).contains { $0.name == "pet" && $0.id == petFolder.id })

        let projectDir = SpecImportService.specsDirectory(for: projectId)
        #expect(FileManager.default.fileExists(atPath: projectDir.appendingPathComponent("spec.yaml").path))
    }

    @Test @MainActor func commitPreservesSourceURLForDetachedURLImports() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("spec-import-tests-\(UUID().uuidString)", isDirectory: true)
        SpecImportService.specsRootDirectoryOverride = tempRoot
        defer {
            SpecImportService.specsRootDirectoryOverride = nil
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let store = ProjectStore.mock()
        let bytes = try fixtureBytes(named: "petstore-3.1", preferJSON: true)
        let preview = try await SpecImportService.preview(
            bytes: bytes,
            sourceHint: .json,
            source: .url,
            sourceURL: "https://example.test/openapi.json"
        )

        try SpecImportService.commit(preview: preview, to: store)

        let project = try #require(store.projects.first)
        #expect(project.specLink?.source == .url)
        #expect(project.specLink?.sourceURL == "https://example.test/openapi.json")
        #expect(project.specLink?.isDetached == true)
        #expect(project.specLink?.specRevision == 0)
        #expect(project.specLink?.contentFingerprint == preview.contentFingerprint)
        #expect(FileManager.default.fileExists(atPath: projectDirFile(preview, name: "spec.json").path))
    }

    @Test @MainActor func commitLinkedURLImportStoresLinkedSpecLink() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("spec-import-tests-\(UUID().uuidString)", isDirectory: true)
        SpecImportService.specsRootDirectoryOverride = tempRoot
        defer {
            SpecImportService.specsRootDirectoryOverride = nil
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let store = ProjectStore.mock()
        let bytes = try fixtureBytes(named: "petstore-3.1", preferJSON: true)
        var options = SpecImportOptions.default
        options.linkToSpec = .linked
        let preview = try await SpecImportService.preview(
            bytes: bytes,
            sourceHint: .json,
            source: .url,
            options: options,
            sourceURL: "https://example.test/openapi.json"
        )

        try SpecImportService.commit(preview: preview, to: store)

        let project = try #require(store.projects.first)
        #expect(project.specLink?.source == .url)
        #expect(project.specLink?.sourceURL == "https://example.test/openapi.json")
        #expect(project.specLink?.isDetached == false)
        #expect(project.specLink?.specRevision == 0)
        #expect(project.specLink?.contentFingerprint == preview.contentFingerprint)

        let specDocument = try #require(store.specDocuments.first)
        #expect(specDocument.projectId == project.id)
        #expect(specDocument.contentFingerprint == preview.contentFingerprint)
        #expect(specDocument.specFileName == "spec.json")
        #expect(specDocument.assetHydrated == true)
    }

    @Test @MainActor func commitDetachedImportDoesNotCreateSpecDocument() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("spec-import-tests-\(UUID().uuidString)", isDirectory: true)
        SpecImportService.specsRootDirectoryOverride = tempRoot
        defer {
            SpecImportService.specsRootDirectoryOverride = nil
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let store = ProjectStore.mock()
        let bytes = try fixtureBytes(named: "petstore-3.1", preferJSON: true)
        let preview = try await SpecImportService.preview(
            bytes: bytes,
            sourceHint: .json,
            source: .url,
            sourceURL: "https://example.test/openapi.json"
        )

        try SpecImportService.commit(preview: preview, to: store)

        #expect(store.specDocuments.isEmpty)
    }

    @Test @MainActor func commitLinkedMergeSetsDetachedFromOptions() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("spec-import-tests-\(UUID().uuidString)", isDirectory: true)
        SpecImportService.specsRootDirectoryOverride = tempRoot
        defer {
            SpecImportService.specsRootDirectoryOverride = nil
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let store = ProjectStore.mock()
        let existingProject = Project(name: "Petstore")
        let projectId = existingProject.id
        store.projects.append(existingProject)

        let bytes = try fixtureBytes(named: "petstore-3.1", preferJSON: false)
        var options = SpecImportOptions.default
        options.linkToSpec = .linked
        let preview = try await SpecImportService.preview(
            bytes: bytes,
            sourceHint: .yaml,
            source: .url,
            options: options,
            sourceURL: "https://example.test/openapi.yaml"
        )

        try SpecImportService.commit(
            preview: preview,
            to: store,
            importTarget: .existingProject,
            targetProjectId: projectId
        )

        let project = try #require(store.projects.first)
        #expect(project.specLink?.isDetached == false)
        #expect(project.specLink?.sourceURL == "https://example.test/openapi.yaml")
    }

    @Test func previewParsesMultiFileBundle() async throws {
        let bundleDir = Self.fixturesDirectory.appendingPathComponent("bundle-multi-file", isDirectory: true)
        let entryURL = try #require(SpecImportHelpers.findBundleEntry(in: bundleDir))
        let bytes = try Data(contentsOf: entryURL)

        let preview = try await SpecImportService.preview(
            SpecImportRequest(
                bytes: bytes,
                sourceHint: SpecImportHelpers.sourceHint(for: entryURL, data: bytes),
                source: .file,
                bundleEntryPath: entryURL.path,
                bundleSourceDirectory: bundleDir
            )
        )

        #expect(preview.projectName == "Multi-file Petstore")
        #expect(preview.operationCount == 3)
        #expect(preview.specFileName == "bundle/openapi.yaml")
        #expect(preview.bundleSourceDirectory == bundleDir)
        #expect(preview.bundleEntryPath == entryURL.path)
    }

    @Test @MainActor func commitCopiesBundleDirectoryToDisk() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("spec-import-tests-\(UUID().uuidString)", isDirectory: true)
        SpecImportService.specsRootDirectoryOverride = tempRoot
        defer {
            SpecImportService.specsRootDirectoryOverride = nil
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let bundleDir = Self.fixturesDirectory.appendingPathComponent("bundle-multi-file", isDirectory: true)
        let entryURL = try #require(SpecImportHelpers.findBundleEntry(in: bundleDir))
        let bytes = try Data(contentsOf: entryURL)
        let preview = try await SpecImportService.preview(
            SpecImportRequest(
                bytes: bytes,
                sourceHint: .yaml,
                source: .file,
                bundleEntryPath: entryURL.path,
                bundleSourceDirectory: bundleDir
            )
        )

        let store = ProjectStore.mock()
        try SpecImportService.commit(preview: preview, to: store)

        let projectDir = SpecImportService.specsDirectory(for: preview.projectId)
        let bundleDest = projectDir.appendingPathComponent("bundle", isDirectory: true)
        let entryDest = bundleDest.appendingPathComponent("openapi.yaml")
        let componentDest = bundleDest
            .appendingPathComponent("components/schemas/Pet.yaml")

        #expect(FileManager.default.fileExists(atPath: bundleDest.path))
        #expect(FileManager.default.fileExists(atPath: entryDest.path))
        #expect(FileManager.default.fileExists(atPath: componentDest.path))
        #expect(!FileManager.default.fileExists(atPath: projectDir.appendingPathComponent("spec.yaml").path))
    }

    // MARK: - Real-world fixtures

    struct RealWorldFixture: Sendable {
        let name: String
        let title: String
        let sourceURL: String
        let iconURL: String?
        let minOperations: Int
        let preferJSON: Bool

        init(
            name: String,
            title: String,
            sourceURL: String,
            iconURL: String? = nil,
            minOperations: Int,
            preferJSON: Bool = false
        ) {
            self.name = name
            self.title = title
            self.sourceURL = sourceURL
            self.iconURL = iconURL
            self.minOperations = minOperations
            self.preferJSON = preferJSON
        }
    }

    static let realWorldFixtures: [RealWorldFixture] = [
        RealWorldFixture(
            name: "1global-connect-api",
            title: "1GLOBAL Connect API",
            sourceURL: "https://docs.connect-api.1global.com/spec/version-2026-02-05/spec.yml",
            iconURL: "https://docs.connect.1global.com/img/logo.svg",
            minOperations: 91
        ),
        RealWorldFixture(
            name: "tagoio-api",
            title: "TagoIO API",
            sourceURL: "https://docs.tago.io/specs/tagoio-api.yaml",
            minOperations: 107
        ),
        RealWorldFixture(
            name: "tdeploy-api",
            title: "TagoIO Deploy API",
            sourceURL: "https://docs.tago.io/specs/tdeploy-api.yaml",
            minOperations: 5
        ),
        RealWorldFixture(
            name: "slack-api",
            title: "Slack Web API",
            sourceURL: "https://api.apis.guru/v2/specs/slack.com/1.7.0/openapi.yaml",
            minOperations: 100
        ),
        RealWorldFixture(
            name: "twilio-api",
            title: "Twilio - Api",
            sourceURL: "https://api.apis.guru/v2/specs/twilio.com/api/1.42.0/openapi.yaml",
            minOperations: 100
        ),
        RealWorldFixture(
            name: "notion-api",
            title: "Notion API",
            sourceURL: "https://api.apis.guru/v2/specs/notion.com/1.0.0/openapi.yaml",
            minOperations: 10
        ),
        RealWorldFixture(
            name: "kubernetes-api",
            title: "Kubernetes",
            sourceURL: "https://api.apis.guru/v2/specs/kubernetes.io/unversioned/swagger.yaml",
            minOperations: 500
        ),
        RealWorldFixture(
            name: "box-api",
            title: "Box Platform API",
            sourceURL: "https://api.apis.guru/v2/specs/box.com/2.0.0/openapi.yaml",
            minOperations: 200
        ),
        RealWorldFixture(
            name: "asana-api",
            title: "Asana",
            sourceURL: "https://api.apis.guru/v2/specs/asana.com/1.0/openapi.yaml",
            minOperations: 100
        ),
        RealWorldFixture(
            name: "trello-api",
            title: "Trello",
            sourceURL: "https://api.apis.guru/v2/specs/trello.com/1.0/openapi.yaml",
            minOperations: 200
        ),
        RealWorldFixture(
            name: "httpbin-api",
            title: "httpbin.org",
            sourceURL: "https://api.apis.guru/v2/specs/httpbin.org/0.9.2/openapi.yaml",
            minOperations: 50
        ),
        RealWorldFixture(
            name: "circleci-api",
            title: "CircleCI REST API",
            sourceURL: "https://api.apis.guru/v2/specs/circleci.com/v1/openapi.yaml",
            minOperations: 10
        ),
        RealWorldFixture(
            name: "launchdarkly-api",
            title: "LaunchDarkly REST API",
            sourceURL: "https://api.apis.guru/v2/specs/launchdarkly.com/5.3.0/swagger.yaml",
            minOperations: 50
        ),
        RealWorldFixture(
            name: "iot-account-service",
            title: "IoT Account Service API",
            sourceURL: "file:///iot-account-service.openapi.json",
            minOperations: 31,
            preferJSON: true
        ),
        RealWorldFixture(
            name: "iot-authentication-service",
            title: "Authentication Service API",
            sourceURL: "file:///iot-authentication-service.openapi.json",
            minOperations: 2,
            preferJSON: true
        ),
        RealWorldFixture(
            name: "iot-authorization-service",
            title: "IoT Authorization Service API",
            sourceURL: "file:///iot-authorization-service.openapi.json",
            minOperations: 12,
            preferJSON: true
        ),
        RealWorldFixture(
            name: "iot-background-operations-service",
            title: "IoT Background Operations Service API",
            sourceURL: "file:///iot-background-operations-service.openapi.json",
            minOperations: 10,
            preferJSON: true
        ),
        RealWorldFixture(
            name: "iot-order-service",
            title: "IoT Order Service API",
            sourceURL: "file:///iot-order-service.openapi.json",
            minOperations: 6,
            preferJSON: true
        ),
        RealWorldFixture(
            name: "iot-product-catalog-service",
            title: "IoT Product Catalog Service API",
            sourceURL: "file:///iot-product-catalog-service.openapi.json",
            minOperations: 56,
            preferJSON: true
        ),
        RealWorldFixture(
            name: "iot-subscription-service",
            title: "IoT Subscription Service API",
            sourceURL: "file:///iot-subscription-service.openapi.json",
            minOperations: 55,
            preferJSON: true
        ),
    ]

    @Test(arguments: Self.realWorldFixtures)
    func previewParsesRealWorldOpenAPIFixture(fixture: RealWorldFixture) async throws {
        let bytes = try fixtureBytes(named: fixture.name, preferJSON: fixture.preferJSON)
        let preview = try await SpecImportService.preview(
            bytes: bytes,
            sourceHint: fixture.preferJSON ? .json : .yaml,
            source: .url,
            sourceURL: fixture.sourceURL
        )

        #expect(preview.projectName == fixture.title)
        #expect(preview.operationCount >= fixture.minOperations)
        #expect(preview.format == .openapi)
        if let iconURL = fixture.iconURL {
            #expect(preview.mapped.project.iconURL == iconURL)
        }
    }

    @Test func previewParsesTagoIODocsSpecURL() async throws {
        let bytes = try fixtureBytes(named: "tagoio-api")
        let sourceURL = "https://docs.tago.io/specs/tagoio-api.yaml"

        let preview = try await SpecImportService.preview(
            bytes: bytes,
            sourceHint: .yaml,
            source: .url,
            sourceURL: sourceURL
        )

        #expect(preview.projectName == "TagoIO API")
        #expect(preview.operationCount == 107)
        #expect(preview.sourceURL == sourceURL)
        #expect(preview.format == .openapi)
    }

    @Test func previewParsesTDeployDocsSpecURL() async throws {
        let bytes = try fixtureBytes(named: "tdeploy-api")
        let sourceURL = "https://docs.tago.io/specs/tdeploy-api.yaml"

        let preview = try await SpecImportService.preview(
            bytes: bytes,
            sourceHint: .yaml,
            source: .url,
            sourceURL: sourceURL
        )

        #expect(preview.projectName == "TagoIO Deploy API")
        #expect(preview.operationCount == 5)
        #expect(preview.sourceURL == sourceURL)
        #expect(preview.format == .openapi)
    }

    @Test @MainActor func commitGroupedBatchImportsIoTServiceFolderIntoOneProject() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("spec-import-tests-\(UUID().uuidString)", isDirectory: true)
        SpecImportService.specsRootDirectoryOverride = tempRoot
        defer {
            SpecImportService.specsRootDirectoryOverride = nil
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let items = try await iotServiceBatchItems()
        let bindings = SpecImportService.makeEnvironmentBindings(for: items)
        let batch = SpecImportBatchPreview(items: items, sourceFolderName: "iot-services")
        let store = ProjectStore.mock()
        let project = try SpecImportService.commitGroupedBatch(
            preview: batch,
            projectName: "IoT Services",
            environmentName: "iot-services",
            environmentBindings: bindings,
            to: store,
            options: .default
        )

        #expect(project.name == "IoT Services")
        #expect(store.projects.count == 1)
        #expect(store.requests.count == batch.totalOperationCount)
        let folders = store.requestFolders(for: project.id)
        #expect(folders.contains(where: { $0.name.hasPrefix("IoT Account Service API") }))
        #expect(folders.contains(where: { $0.name.hasPrefix("Authentication Service API") }))

        let environments = store.environments(for: project.id)
        #expect(environments.count == 1)
        #expect(environments.first?.name == "iot-services")
        #expect(environments.first?.variables.contains(where: { $0.key == "iot_account_service_base_url" }) == true)

        let accountRequest = store.requests.first {
            $0.projectId == project.id && $0.httpData?.url.contains("{{iot_account_service_base_url}}") == true
        }
        #expect(accountRequest != nil)

        let sourcesDir = SpecImportService.specsDirectory(for: project.id)
            .appendingPathComponent("sources", isDirectory: true)
        #expect(FileManager.default.fileExists(atPath: sourcesDir.path))
    }

    @Test func combineGroupedBatchPrefixesFoldersWithSpecName() async throws {
        let accountBytes = try fixtureBytes(named: "iot-account-service", preferJSON: true)
        let authBytes = try fixtureBytes(named: "iot-authentication-service", preferJSON: true)
        // Source paths drive slug-based env var names (iot_account_service_base_url).
        let accountPreview = try await SpecImportService.preview(
            bytes: accountBytes,
            sourceHint: .json,
            source: .file,
            sourceURL: "/iot-account-service.openapi.json"
        )
        let authPreview = try await SpecImportService.preview(
            bytes: authBytes,
            sourceHint: .json,
            source: .file,
            sourceURL: "/iot-authentication-service.openapi.json"
        )

        let bindings = SpecImportService.makeEnvironmentBindings(for: [accountPreview, authPreview])
        let combined = SpecImportService.combineGroupedBatch(
            from: [accountPreview, authPreview],
            projectId: UUID(),
            projectName: "IoT Services",
            environmentName: "IoT Services",
            environmentBindings: bindings
        )

        #expect(combined.requests.count == accountPreview.operationCount + authPreview.operationCount)
        #expect(combined.folders.contains(where: { $0.name.hasPrefix("IoT Account Service API /") }))
        #expect(combined.folders.contains(where: { $0.name.hasPrefix("Authentication Service API /") }))
        #expect(combined.environments.count == 1)
        #expect(combined.environments.first?.variables.contains(where: { $0.key == "iot_account_service_base_url" }) == true)
        #expect(combined.requests.contains(where: { $0.httpData?.url.contains("{{iot_account_service_base_url}}") == true }))
    }

    @Test @MainActor func commitBatchImportsIoTServiceFolderAsSeparateProjects() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("spec-import-tests-\(UUID().uuidString)", isDirectory: true)
        SpecImportService.specsRootDirectoryOverride = tempRoot
        defer {
            SpecImportService.specsRootDirectoryOverride = nil
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let items = try await iotServiceBatchItems()
        let batch = SpecImportBatchPreview(items: items, sourceFolderName: "iot-services")
        let store = ProjectStore.mock()
        let imported = try SpecImportService.commitBatch(preview: batch, to: store, options: .default)

        #expect(imported.count == items.count)
        #expect(store.projects.count == items.count)
        #expect(store.requests.count == batch.totalOperationCount)
    }

    @Test func previewParses1GlobalConnectDocsSpecURL() async throws {
        let bytes = try fixtureBytes(named: "1global-connect-api")
        let sourceURL = "https://docs.connect-api.1global.com/spec/version-2026-02-05/spec.yml"

        let preview = try await SpecImportService.preview(
            bytes: bytes,
            sourceHint: .yaml,
            source: .url,
            sourceURL: sourceURL
        )

        #expect(preview.projectName == "1GLOBAL Connect API")
        #expect(preview.operationCount == 91)
        #expect(preview.sourceURL == sourceURL)
        #expect(preview.mapped.project.iconURL == "https://docs.connect.1global.com/img/logo.svg")
        #expect(preview.format == .openapi)
    }

    // MARK: - Helpers

    private func iotServiceBatchItems() async throws -> [SpecImportPreview] {
        let serviceNames = [
            "iot-account-service",
            "iot-authentication-service",
            "iot-authorization-service",
            "iot-background-operations-service",
            "iot-order-service",
            "iot-product-catalog-service",
            "iot-subscription-service",
        ]

        var items: [SpecImportPreview] = []
        for name in serviceNames {
            let bytes = try fixtureBytes(named: name, preferJSON: true)
            let preview = try await SpecImportService.preview(
                bytes: bytes,
                sourceHint: .json,
                source: .file,
                sourceURL: "/\(name).openapi.json"
            )
            items.append(preview)
        }
        return items
    }

    private func fixtureBytes(named name: String, preferJSON: Bool = false) throws -> Data {
        let yamlURL = Self.fixturesDirectory.appendingPathComponent("\(name).input.yaml")
        let ymlURL = Self.fixturesDirectory.appendingPathComponent("\(name).input.yml")
        let jsonURL = Self.fixturesDirectory.appendingPathComponent("\(name).input.json")

        let url: URL
        if preferJSON, FileManager.default.fileExists(atPath: jsonURL.path) {
            url = jsonURL
        } else if FileManager.default.fileExists(atPath: yamlURL.path) {
            url = yamlURL
        } else if FileManager.default.fileExists(atPath: ymlURL.path) {
            url = ymlURL
        } else if FileManager.default.fileExists(atPath: jsonURL.path) {
            url = jsonURL
        } else {
            throw FixtureError.missingInput(name)
        }

        return try Data(contentsOf: url)
    }

    private func projectDirFile(_ preview: SpecImportPreview, name: String) -> URL {
        SpecImportService.specsDirectory(for: preview.projectId).appendingPathComponent(name)
    }

    private enum FixtureError: Error {
        case missingInput(String)
    }
}