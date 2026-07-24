//
//  ProtoBundleSyncTests.swift
//  ReqeastTests
//

import CloudKit
import Foundation
import Testing
@testable import Reqeast

@Suite("ProtoBundleSync", .serialized)
struct ProtoBundleSyncTests {

    @Test @MainActor func protoBundleUploadsAssetOnFingerprintChange() throws {
        let service = CloudSyncService.shared
        try withTempProtosRoot { _ in
            let projectId = UUID()
            let bundleId = UUID()
            try writeBundleOnDisk(projectId: projectId, bundleId: bundleId)

            var bundle = makeBundle(projectId: projectId, bundleId: bundleId, fingerprint: "fingerprint-a")
            let first = try #require(service.buildRecord(for: bundle))
            #expect(first[ProtoBundle.ckAssetField] as? CKAsset != nil)

            bundle.lastUploadedFingerprint = "fingerprint-a"
            bundle.contentFingerprint = "fingerprint-b"
            let second = try #require(service.buildRecord(for: bundle))
            #expect(second[ProtoBundle.ckAssetField] as? CKAsset != nil)
            #expect(second[ProtoBundle.fingerprintField] as? String == "fingerprint-b")
        }
    }

    @Test @MainActor func protoBundleSkipsAssetUploadWhenFingerprintUnchanged() throws {
        let service = CloudSyncService.shared
        try withTempProtosRoot { _ in
            let projectId = UUID()
            let bundleId = UUID()
            try writeBundleOnDisk(projectId: projectId, bundleId: bundleId)

            var bundle = makeBundle(projectId: projectId, bundleId: bundleId, fingerprint: "same-fingerprint")
            bundle.lastUploadedFingerprint = "same-fingerprint"
            #expect(service.shouldUploadProtoAsset(for: bundle) == false)

            let record = try #require(service.buildRecord(for: bundle))
            #expect(record[ProtoBundle.ckAssetField] as? CKAsset == nil)
        }
    }

    @Test @MainActor func protoBundleFetchHydratesAssetOnDisk() throws {
        let service = CloudSyncService.shared
        try withTempProtosRoot { _ in
            let projectId = UUID()
            let bundleId = UUID()
            let bundleDirectory = ProtoBundleService.bundleDirectory(projectId: projectId, bundleId: bundleId)
            try FileManager.default.createDirectory(at: bundleDirectory, withIntermediateDirectories: true)

            let descriptorBytes = Data("descriptor-bytes".utf8)
            try descriptorBytes.write(to: bundleDirectory.appendingPathComponent(ProtoBundle.descriptorsFileName))
            try ProtoBundleService.packBundleZip(bundleDirectory: bundleDirectory)
            let zipURL = bundleDirectory.appendingPathComponent(ProtoBundle.uploadZipFileName)

            try FileManager.default.removeItem(at: bundleDirectory.appendingPathComponent(ProtoBundle.descriptorsFileName))

            let bundle = makeBundle(
                projectId: projectId,
                bundleId: bundleId,
                fingerprint: "remote-fingerprint",
                assetHydrated: false
            )

            let record = CKRecord(recordType: "ProtoBundle", recordID: service.recordID(for: bundle))
            record["data"] = try JSONEncoder().encode(bundle) as NSData
            record["updatedAt"] = bundle.updatedAt as NSDate
            record[ProtoBundle.fingerprintField] = bundle.contentFingerprint as NSString
            record[ProtoBundle.ckAssetField] = CKAsset(fileURL: zipURL)

            let store = ProjectStore.mock()
            #expect(service.applyProtoBundleUpsert(record: record, store: store))

            let applied = try #require(store.protoBundles.first)
            #expect(applied.assetHydrated == true)
            #expect(ProtoBundle.loadDescriptorBytes(projectId: projectId, bundleId: bundleId) == descriptorBytes)
            #expect(store.isGrpcProtoReady(protoBundleId: bundleId))
        }
    }

    @Test @MainActor func protoBundleFetchWithoutAssetMarksReadOnly() throws {
        let service = CloudSyncService.shared
        try withTempProtosRoot { _ in
            let projectId = UUID()
            let bundleId = UUID()
            let bundle = makeBundle(
                projectId: projectId,
                bundleId: bundleId,
                fingerprint: "remote-fingerprint",
                assetHydrated: true
            )

            let record = CKRecord(recordType: "ProtoBundle", recordID: service.recordID(for: bundle))
            record["data"] = try JSONEncoder().encode(bundle) as NSData
            record["updatedAt"] = bundle.updatedAt as NSDate

            let store = ProjectStore.mock()
            #expect(service.applyProtoBundleUpsert(record: record, store: store))

            let applied = try #require(store.protoBundles.first)
            #expect(applied.assetHydrated == false)
            #expect(applied.isReadOnlyDueToMissingAsset)
            #expect(store.isGrpcProtoReady(protoBundleId: bundleId) == false)
        }
    }

    @Test @MainActor func protoBundleOversizedZipFailsBuildRecord() throws {
        let service = CloudSyncService.shared
        try withTempProtosRoot { _ in
            let projectId = UUID()
            let bundleId = UUID()
            let bundleDirectory = ProtoBundleService.bundleDirectory(projectId: projectId, bundleId: bundleId)
            try FileManager.default.createDirectory(at: bundleDirectory, withIntermediateDirectories: true)

            let oversized = Data(repeating: 0xAB, count: ProtoBundle.maxBundleBytes + 1)
            try oversized.write(to: bundleDirectory.appendingPathComponent(ProtoBundle.uploadZipFileName))

            let bundle = makeBundle(projectId: projectId, bundleId: bundleId, fingerprint: "big")
            let record = service.buildRecord(for: bundle)
            #expect(record == nil)
        }
    }

    @Test @MainActor func queueSaveBatchQueuesProtoBundlesBeforeProject() {
        let service = CloudSyncService.shared
        service.lastQueueSaveBatchRecordOrder = []

        let project = Project(name: "grpc")
        let bundle = ProtoBundle(
            projectId: project.id,
            name: "Greeter",
            contentFingerprint: "fp",
            entryFile: "hello.proto",
            fileCount: 1
        )

        service.queueSaveBatch(project: project, protoBundles: [bundle])

        let expectedOrder = [
            "ProtoBundle/\(bundle.id.uuidString)",
            "Project/\(project.id.uuidString)",
        ]
        #expect(service.lastQueueSaveBatchRecordOrder == expectedOrder)
    }

    private func makeBundle(
        projectId: UUID,
        bundleId: UUID,
        fingerprint: String,
        assetHydrated: Bool = true
    ) -> ProtoBundle {
        ProtoBundle(
            id: bundleId,
            projectId: projectId,
            name: "Greeter",
            contentFingerprint: fingerprint,
            entryFile: "hello.proto",
            fileCount: 1,
            assetHydrated: assetHydrated
        )
    }

    private func writeBundleOnDisk(projectId: UUID, bundleId: UUID) throws {
        let bundleDirectory = ProtoBundleService.bundleDirectory(projectId: projectId, bundleId: bundleId)
        try FileManager.default.createDirectory(at: bundleDirectory, withIntermediateDirectories: true)
        try Data("descriptor".utf8).write(to: bundleDirectory.appendingPathComponent(ProtoBundle.descriptorsFileName))
        try "fingerprint".write(
            to: bundleDirectory.appendingPathComponent(ProtoBundle.fingerprintFileName),
            atomically: true,
            encoding: .utf8
        )
        _ = try ProtoBundleService.packBundleZip(bundleDirectory: bundleDirectory)
    }

    private func withTempProtosRoot(
        _ body: @escaping @MainActor (URL) throws -> Void
    ) throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("proto-bundle-sync-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        try ProtoBundleService.$protosRootDirectoryOverride.withValue(tempRoot) {
            try body(tempRoot)
        }
    }
}