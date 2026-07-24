//
//  CKAssetValidationHarnessTests.swift
//  ReqeastTests
//
//  T39: CKAsset validation spike — opt-in, non-gating. Simulates 5 MiB
//  SpecDocument upload/download, secondary-device hydration, and conflict
//  during upload. Results inform timeout/retry tuning only.
//

import CloudKit
import CryptoKit
import Foundation
import Testing
@testable import Reqeast

// MARK: - Harness configuration

private enum CKAssetHarnessConfig {
    static let targetBytes = SpecDocument.maxSpecBytes
}

private struct CKAssetHarnessMetrics: Codable {
    var scenario: String
    var bytes: Int
    var durationSeconds: Double
    var recordedAt: String
    var platform: String

    enum CodingKeys: String, CodingKey {
        case scenario
        case bytes
        case durationSeconds = "duration_seconds"
        case recordedAt = "recorded_at"
        case platform
    }
}

private extension Duration {
    var secondsDouble: Double {
        let (seconds, attoseconds) = components
        return Double(seconds) + Double(attoseconds) / 1_000_000_000_000_000_000
    }
}

/// Opt-in spike (T39): excluded from `just test-all` because 5 MiB I/O is slow.
/// Enable via `just test-ckasset-harness`, which compiles with `RUN_CKASSET_HARNESS`.
private enum CKAssetHarnessGate {
    #if RUN_CKASSET_HARNESS
    static let enabled = true
    #else
    static let enabled = false
    #endif
}

@Suite("CKAssetValidationHarness", .serialized, .enabled(if: CKAssetHarnessGate.enabled))
struct CKAssetValidationHarnessTests {

    // MARK: - Scenarios

    @Test(
        "5 MiB upload build attaches CKAsset at cap",
        .timeLimit(.minutes(2))
    )
    @MainActor
    func fiveMiBUploadBuildAttachesCKAsset() throws {
        let service = CloudSyncService.shared
        let tempRoot = try Self.makeTempSpecsRoot()
        defer { Self.cleanup(tempRoot) }

        let projectId = UUID()
        let payload = Self.makeFiveMiBSpecData(marker: 0x01)
        try Self.writeSpecBytes(projectId: projectId, fileName: "spec.yaml", data: payload)

        var document = Self.makeSpecDocument(
            projectId: projectId,
            fingerprint: Self.fingerprint(for: payload),
            fileName: "spec.yaml"
        )

        let start = ContinuousClock.now
        let record = try #require(service.buildRecord(for: document))
        let duration = start.duration(to: ContinuousClock.now)

        let asset = try #require(record[SpecDocument.ckAssetField] as? CKAsset)
        let assetURL = try #require(asset.fileURL)
        let assetBytes = try Data(contentsOf: assetURL)
        #expect(assetBytes.count == CKAssetHarnessConfig.targetBytes)
        #expect(assetBytes == payload)

        document.lastUploadedFingerprint = document.contentFingerprint
        let unchanged = try #require(service.buildRecord(for: document))
        #expect(unchanged[SpecDocument.ckAssetField] as? CKAsset == nil)

        Self.recordMetrics(
            CKAssetHarnessMetrics(
                scenario: "upload_build",
                bytes: CKAssetHarnessConfig.targetBytes,
                durationSeconds: duration.secondsDouble,
                recordedAt: ISO8601DateFormatter().string(from: Date()),
                platform: "macOS"
            )
        )
    }

    @Test(
        "secondary device hydrates 5 MiB spec from CKAsset",
        .timeLimit(.minutes(2))
    )
    @MainActor
    func secondaryDeviceHydratesFiveMiBFromCKAsset() throws {
        let service = CloudSyncService.shared
        let secondaryRoot = try Self.makeTempSpecsRoot()
        defer { Self.cleanup(secondaryRoot) }

        let projectId = UUID()
        let payload = Self.makeFiveMiBSpecData(marker: 0x02)
        let fingerprint = Self.fingerprint(for: payload)

        let cloudAssetURL = secondaryRoot
            .appendingPathComponent("cloud-asset-\(UUID().uuidString).yaml")
        try payload.write(to: cloudAssetURL)

        let document = Self.makeSpecDocument(
            projectId: projectId,
            fingerprint: fingerprint,
            fileName: "spec.yaml",
            assetHydrated: false
        )

        let record = CKRecord(
            recordType: SpecDocument.syncRecordType.rawValue,
            recordID: service.recordID(for: document)
        )
        record["data"] = try JSONEncoder().encode(document) as NSData
        record["updatedAt"] = document.updatedAt as NSDate
        record[SpecDocument.fingerprintField] = fingerprint as NSString
        record[SpecDocument.ckAssetField] = CKAsset(fileURL: cloudAssetURL)

        var project = Project(name: "Linked")
        project.id = projectId
        project.specLink = SpecLink(
            format: .openapi,
            source: .url,
            contentFingerprint: fingerprint,
            importedAt: Date(),
            sourceURL: "https://example.com/openapi.yaml",
            isDetached: false
        )
        let store = ProjectStore.mock(projects: [project])

        let start = ContinuousClock.now
        #expect(service.applySpecDocumentUpsert(record: record, store: store))
        let duration = start.duration(to: ContinuousClock.now)

        let specURL = SpecImportService.specsDirectory(for: projectId).appendingPathComponent("spec.yaml")
        let hydrated = try Data(contentsOf: specURL)
        #expect(hydrated == payload)

        let fingerprintURL = SpecImportService.specsDirectory(for: projectId).appendingPathComponent("fingerprint.txt")
        #expect(try String(contentsOf: fingerprintURL, encoding: .utf8) == fingerprint)

        let applied = try #require(store.specDocuments.first)
        #expect(applied.assetHydrated == true)
        #expect(store.isSpecProjectReadOnly(projectId: projectId) == false)

        Self.recordMetrics(
            CKAssetHarnessMetrics(
                scenario: "secondary_device_hydrate",
                bytes: CKAssetHarnessConfig.targetBytes,
                durationSeconds: duration.secondsDouble,
                recordedAt: ISO8601DateFormatter().string(from: Date()),
                platform: "macOS"
            )
        )
    }

    @Test(
        "5 MiB round-trip preserves exact bytes",
        .timeLimit(.minutes(2))
    )
    @MainActor
    func fiveMiBRoundTripPreservesExactBytes() throws {
        let service = CloudSyncService.shared
        let primaryRoot = try Self.makeTempSpecsRoot()
        defer { Self.cleanup(primaryRoot) }

        let projectId = UUID()
        let payload = Self.makeFiveMiBSpecData(marker: 0x03)
        let fingerprint = Self.fingerprint(for: payload)
        try Self.writeSpecBytes(projectId: projectId, fileName: "spec.yaml", data: payload)

        let document = Self.makeSpecDocument(
            projectId: projectId,
            fingerprint: fingerprint,
            fileName: "spec.yaml"
        )

        let start = ContinuousClock.now
        let uploadRecord = try #require(service.buildRecord(for: document))
        let assetURL = try #require((uploadRecord[SpecDocument.ckAssetField] as? CKAsset)?.fileURL)

        let secondaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ckasset-harness-secondary-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: secondaryRoot, withIntermediateDirectories: true)
        SpecImportService.specsRootDirectoryOverride = secondaryRoot
        defer {
            SpecImportService.specsRootDirectoryOverride = nil
            try? FileManager.default.removeItem(at: secondaryRoot)
        }

        let secondaryStore = ProjectStore.mock()
        #expect(service.applySpecDocumentUpsert(record: uploadRecord, store: secondaryStore))
        let duration = start.duration(to: ContinuousClock.now)

        let hydratedURL = SpecImportService.specsDirectory(for: projectId).appendingPathComponent("spec.yaml")
        let hydrated = try Data(contentsOf: hydratedURL)
        #expect(hydrated == payload)
        #expect(try Data(contentsOf: assetURL) == hydrated)

        Self.recordMetrics(
            CKAssetHarnessMetrics(
                scenario: "round_trip",
                bytes: CKAssetHarnessConfig.targetBytes,
                durationSeconds: duration.secondsDouble,
                recordedAt: ISO8601DateFormatter().string(from: Date()),
                platform: "macOS"
            )
        )
    }

    @Test(
        "conflict during upload — server newer hydrates secondary with remote asset",
        .timeLimit(.minutes(2))
    )
    @MainActor
    func conflictDuringUploadServerNewerHydratesSecondary() throws {
        let service = CloudSyncService.shared
        let primaryRoot = try Self.makeTempSpecsRoot()
        defer { Self.cleanup(primaryRoot) }

        let projectId = UUID()
        let localPayload = Self.makeFiveMiBSpecData(marker: 0x10)
        let serverPayload = Self.makeFiveMiBSpecData(marker: 0x20)
        let localFingerprint = Self.fingerprint(for: localPayload)
        let serverFingerprint = Self.fingerprint(for: serverPayload)

        try Self.writeSpecBytes(projectId: projectId, fileName: "spec.yaml", data: localPayload)

        var localDocument = Self.makeSpecDocument(
            projectId: projectId,
            fingerprint: localFingerprint,
            fileName: "spec.yaml",
            updatedAt: Date(timeIntervalSince1970: 1_000)
        )
        let localRecord = try #require(service.buildRecord(for: localDocument))

        let serverAssetURL = primaryRoot
            .appendingPathComponent("server-asset-\(UUID().uuidString).yaml")
        try serverPayload.write(to: serverAssetURL)

        var serverDocument = Self.makeSpecDocument(
            projectId: projectId,
            fingerprint: serverFingerprint,
            fileName: "spec.yaml",
            updatedAt: Date(timeIntervalSince1970: 2_000),
            assetHydrated: true
        )
        serverDocument.lastUploadedFingerprint = serverFingerprint

        let serverRecord = CKRecord(
            recordType: SpecDocument.syncRecordType.rawValue,
            recordID: service.recordID(for: serverDocument)
        )
        serverRecord["data"] = try JSONEncoder().encode(serverDocument) as NSData
        serverRecord["updatedAt"] = serverDocument.updatedAt as NSDate
        serverRecord[SpecDocument.fingerprintField] = serverFingerprint as NSString
        serverRecord[SpecDocument.ckAssetField] = CKAsset(fileURL: serverAssetURL)

        let start = ContinuousClock.now
        #expect(service.resolveConflict(localRecord: localRecord, serverRecord: serverRecord) == .serverNewer)

        let secondaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ckasset-harness-conflict-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: secondaryRoot, withIntermediateDirectories: true)
        SpecImportService.specsRootDirectoryOverride = secondaryRoot
        defer {
            SpecImportService.specsRootDirectoryOverride = nil
            try? FileManager.default.removeItem(at: secondaryRoot)
        }

        let secondaryStore = ProjectStore.mock()
        #expect(service.applySpecDocumentUpsert(record: serverRecord, store: secondaryStore))
        let duration = start.duration(to: ContinuousClock.now)

        let hydratedURL = SpecImportService.specsDirectory(for: projectId).appendingPathComponent("spec.yaml")
        let hydrated = try Data(contentsOf: hydratedURL)
        #expect(hydrated == serverPayload)
        #expect(hydrated != localPayload)

        let applied = try #require(secondaryStore.specDocuments.first)
        #expect(applied.contentFingerprint == serverFingerprint)
        #expect(applied.assetHydrated == true)

        Self.recordMetrics(
            CKAssetHarnessMetrics(
                scenario: "conflict_server_newer_hydrate",
                bytes: CKAssetHarnessConfig.targetBytes,
                durationSeconds: duration.secondsDouble,
                recordedAt: ISO8601DateFormatter().string(from: Date()),
                platform: "macOS"
            )
        )
    }

    @Test(
        "conflict during upload — local newer keeps upload intent",
        .timeLimit(.minutes(2))
    )
    @MainActor
    func conflictDuringUploadLocalNewerKeepsUploadIntent() throws {
        let service = CloudSyncService.shared
        let tempRoot = try Self.makeTempSpecsRoot()
        defer { Self.cleanup(tempRoot) }

        let projectId = UUID()
        let localPayload = Self.makeFiveMiBSpecData(marker: 0x31)
        let serverPayload = Self.makeFiveMiBSpecData(marker: 0x32)
        let localFingerprint = Self.fingerprint(for: localPayload)
        let serverFingerprint = Self.fingerprint(for: serverPayload)

        try Self.writeSpecBytes(projectId: projectId, fileName: "spec.yaml", data: localPayload)

        var localDocument = Self.makeSpecDocument(
            projectId: projectId,
            fingerprint: localFingerprint,
            fileName: "spec.yaml",
            updatedAt: Date(timeIntervalSince1970: 3_000)
        )
        let localRecord = try #require(service.buildRecord(for: localDocument))

        let serverAssetURL = tempRoot
            .appendingPathComponent("stale-server-asset-\(UUID().uuidString).yaml")
        try serverPayload.write(to: serverAssetURL)

        var serverDocument = Self.makeSpecDocument(
            projectId: projectId,
            fingerprint: serverFingerprint,
            fileName: "spec.yaml",
            updatedAt: Date(timeIntervalSince1970: 2_000)
        )

        let serverRecord = CKRecord(
            recordType: SpecDocument.syncRecordType.rawValue,
            recordID: service.recordID(for: serverDocument)
        )
        serverRecord["data"] = try JSONEncoder().encode(serverDocument) as NSData
        serverRecord["updatedAt"] = serverDocument.updatedAt as NSDate
        serverRecord[SpecDocument.fingerprintField] = serverFingerprint as NSString
        serverRecord[SpecDocument.ckAssetField] = CKAsset(fileURL: serverAssetURL)

        #expect(service.resolveConflict(localRecord: localRecord, serverRecord: serverRecord) == .localNewer)
        #expect(localRecord[SpecDocument.ckAssetField] as? CKAsset != nil)
        #expect(service.shouldUploadSpecAsset(for: localDocument) == true)
    }

    // MARK: - Helpers

    private static func makeFiveMiBSpecData(marker: UInt8) -> Data {
        var header = Data("openapi: 3.0.3\ninfo:\n  title: ckasset-harness\n  x-marker: ".utf8)
        header.append(Data([marker]))
        header.append(Data("\n".utf8))
        var payload = header
        let padCount = CKAssetHarnessConfig.targetBytes - payload.count
        precondition(padCount > 0)
        payload.append(Data(repeating: 0x23, count: padCount))
        precondition(payload.count == CKAssetHarnessConfig.targetBytes)
        return payload
    }

    private static func fingerprint(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func makeSpecDocument(
        projectId: UUID,
        fingerprint: String,
        fileName: String,
        updatedAt: Date = Date(),
        assetHydrated: Bool = true
    ) -> SpecDocument {
        SpecDocument(
            id: projectId,
            projectId: projectId,
            contentFingerprint: fingerprint,
            specFileName: fileName,
            sourceURL: "https://example.com/openapi.yaml",
            classification: .standard,
            isDetached: false,
            assetHydrated: assetHydrated,
            updatedAt: updatedAt
        )
    }

    private static func makeTempSpecsRoot() throws -> URL {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ckasset-harness-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        SpecImportService.specsRootDirectoryOverride = tempRoot
        return tempRoot
    }

    private static func cleanup(_ tempRoot: URL) {
        SpecImportService.specsRootDirectoryOverride = nil
        try? FileManager.default.removeItem(at: tempRoot)
    }

    private static func writeSpecBytes(projectId: UUID, fileName: String, data: Data) throws {
        let projectDir = SpecImportService.specsDirectory(for: projectId)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        let specURL = projectDir.appendingPathComponent(fileName)
        try data.write(to: specURL, options: .atomic)
    }

    private static func recordMetrics(_ metrics: CKAssetHarnessMetrics) {
        let line = "[CKAssetHarness] \(metrics.scenario): \(metrics.bytes) bytes in \(String(format: "%.3f", metrics.durationSeconds))s"
        print(line)

        guard ProcessInfo.processInfo.environment["RECORD_CKASSET_HARNESS"] == "1" else { return }

        let fixturesDir: URL
        if let srcRoot = ProcessInfo.processInfo.environment["SRCROOT"] {
            fixturesDir = URL(fileURLWithPath: srcRoot, isDirectory: true)
                .appendingPathComponent("ReqeastTests/Fixtures/CKAssetHarness", isDirectory: true)
        } else {
            fixturesDir = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Fixtures/CKAssetHarness", isDirectory: true)
        }

        try? FileManager.default.createDirectory(at: fixturesDir, withIntermediateDirectories: true)
        let url = fixturesDir.appendingPathComponent("\(metrics.scenario).metrics.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(metrics) {
            try? data.write(to: url, options: .atomic)
        }
    }
}